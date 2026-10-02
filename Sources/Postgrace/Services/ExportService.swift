import Foundation

/// Service orchestrating data export tasks across Table, Schema, and Database scopes.
public final class ExportService {

    private let postgresService: PostgresService
    private let toolchainService = PostgresToolchainService.shared

    public init(postgresService: PostgresService) {
        self.postgresService = postgresService
    }

    private final class ExportContext: @unchecked Sendable {
        var progress: DataTransferProgress
        let onProgress: (DataTransferProgress) -> Void

        init(progress: DataTransferProgress, onProgress: @escaping (DataTransferProgress) -> Void) {
            self.progress = progress
            self.onProgress = onProgress
        }

        func notify() {
            onProgress(progress)
        }
    }

    /// Performs export according to the configuration, streaming progress via callback.
    public func export(
        config: ExportConfiguration,
        destinationURL: URL,
        onProgress: @escaping (DataTransferProgress) -> Void
    ) async throws {
        var initialProgress = DataTransferProgress()
        initialProgress.status = .inProgress
        initialProgress.startTime = Date()

        let context = ExportContext(progress: initialProgress, onProgress: onProgress)
        context.notify()

        do {
            switch config.scope {
            case .table(let schema, let table):
                try await exportTable(
                    schema: schema,
                    table: table,
                    config: config,
                    destinationURL: destinationURL,
                    context: context
                )
            case .schema(let schemaName, _):
                try await exportSchemaOrDatabase(
                    isSchema: true,
                    targetName: schemaName,
                    config: config,
                    destinationURL: destinationURL,
                    context: context
                )
            case .database(let dbName):
                try await exportSchemaOrDatabase(
                    isSchema: false,
                    targetName: dbName,
                    config: config,
                    destinationURL: destinationURL,
                    context: context
                )
            }

            context.progress.status = .completed("Successfully exported to \(destinationURL.lastPathComponent)")
            context.notify()
        } catch {
            context.progress.status = .failed(error.localizedDescription)
            context.progress.errorLog.append(error.localizedDescription)
            context.notify()
            throw error
        }
    }

    // MARK: - Native Table Export (Streaming)

    private func exportTable(
        schema: String,
        table: String,
        config: ExportConfiguration,
        destinationURL: URL,
        context: ExportContext
    ) async throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
        let fileHandle = try FileHandle(forWritingTo: destinationURL)
        defer { try? fileHandle.close() }

        let total = try? await postgresService.fetchTableRowCount(
            schema: schema,
            table: table,
            filterClause: config.whereClause
        )
        context.progress.totalRows = total
        context.progress.currentOperation = "Exporting table \(schema).\(table)..."
        context.notify()

        var querySQL = "SELECT * FROM \(schema.pgQuotedIdentifier).\(table.pgQuotedIdentifier)"
        let trimmedWhere = config.whereClause.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedWhere.isEmpty {
            querySQL += " WHERE \(trimmedWhere)"
        }
        if let limit = config.limit, limit > 0 {
            querySQL += " LIMIT \(limit)"
        }

        switch config.format {
        case .csv:
            try await exportTableToCSV(
                querySQL: querySQL,
                config: config,
                fileHandle: fileHandle,
                context: context
            )
        case .json:
            try await exportTableToJSON(
                querySQL: querySQL,
                config: config,
                fileHandle: fileHandle,
                context: context
            )
        case .sql:
            try await exportTableToSQL(
                schema: schema,
                table: table,
                querySQL: querySQL,
                config: config,
                fileHandle: fileHandle,
                context: context
            )
        case .customDump:
            try await exportTableViaPgDump(
                schema: schema,
                table: table,
                destinationURL: destinationURL,
                context: context
            )
        }
    }

    private func exportTableToCSV(
        querySQL: String,
        config: ExportConfiguration,
        fileHandle: FileHandle,
        context: ExportContext
    ) async throws {
        var isFirstRow = true

        if config.csvIncludeBOM {
            if let bomData = "\u{FEFF}".data(using: .utf8) {
                try fileHandle.write(contentsOf: bomData)
                context.progress.bytesTransferred += Int64(bomData.count)
            }
        }

        _ = try await postgresService.streamQuery(querySQL) { columns, row in
            if isFirstRow {
                isFirstRow = false
                if config.csvIncludeHeaders {
                    let headerLine = CSVHandler.encodeRow(columns.map(\.name), delimiter: config.csvDelimiter) + "\n"
                    if let data = headerLine.data(using: .utf8) {
                        try fileHandle.write(contentsOf: data)
                        context.progress.bytesTransferred += Int64(data.count)
                    }
                }
            }

            let strValues = row.map { cell -> String in
                switch cell {
                case .null: return ""
                case .string(let s): return s
                case .int(let i): return "\(i)"
                case .double(let d): return "\(d)"
                case .bool(let b): return b ? "true" : "false"
                case .date(let d): return d
                case .data(let data): return data.base64EncodedString()
                case .json(let j): return j
                case .array(let a): return a
                }
            }

            let rowLine = CSVHandler.encodeRow(strValues, delimiter: config.csvDelimiter) + "\n"
            if let data = rowLine.data(using: .utf8) {
                try fileHandle.write(contentsOf: data)
                context.progress.bytesTransferred += Int64(data.count)
            }

            context.progress.rowsProcessed += 1
            if context.progress.rowsProcessed % 100 == 0 {
                context.notify()
            }
        }
    }

    private func exportTableToJSON(
        querySQL: String,
        config: ExportConfiguration,
        fileHandle: FileHandle,
        context: ExportContext
    ) async throws {
        let isNDJSON = config.jsonFlavor == .ndjson
        var isFirstRow = true

        if !isNDJSON {
            let startArray = "[\n"
            if let data = startArray.data(using: .utf8) {
                try fileHandle.write(contentsOf: data)
                context.progress.bytesTransferred += Int64(data.count)
            }
        }

        _ = try await postgresService.streamQuery(querySQL) { columns, row in
            var dict: [String: Any] = [:]
            for (idx, col) in columns.enumerated() {
                if idx < row.count {
                    let cell = row[idx]
                    switch cell {
                    case .null: dict[col.name] = NSNull()
                    case .string(let s): dict[col.name] = s
                    case .int(let i): dict[col.name] = i
                    case .double(let d): dict[col.name] = d
                    case .bool(let b): dict[col.name] = b
                    case .date(let d): dict[col.name] = d
                    case .data(let data): dict[col.name] = data.base64EncodedString()
                    case .json(let j): dict[col.name] = j
                    case .array(let a): dict[col.name] = a
                    }
                }
            }

            if let jsonString = JSONHandler.encodeRecord(dict) {
                let line: String
                if isNDJSON {
                    line = jsonString + "\n"
                } else {
                    line = (isFirstRow ? "  " : ",\n  ") + jsonString
                    isFirstRow = false
                }

                if let data = line.data(using: .utf8) {
                    try fileHandle.write(contentsOf: data)
                    context.progress.bytesTransferred += Int64(data.count)
                }
            }

            context.progress.rowsProcessed += 1
            if context.progress.rowsProcessed % 100 == 0 {
                context.notify()
            }
        }

        if !isNDJSON {
            let endArray = "\n]\n"
            if let data = endArray.data(using: .utf8) {
                try fileHandle.write(contentsOf: data)
                context.progress.bytesTransferred += Int64(data.count)
            }
        }
    }

    private func exportTableToSQL(
        schema: String,
        table: String,
        querySQL: String,
        config: ExportConfiguration,
        fileHandle: FileHandle,
        context: ExportContext
    ) async throws {
        let headerComments = """
        -- Postgrace SQL Dump
        -- Target: \(schema).\(table)
        -- Date: \(Date())
        
        BEGIN;
        
        """
        if let data = headerComments.data(using: .utf8) {
            try fileHandle.write(contentsOf: data)
            context.progress.bytesTransferred += Int64(data.count)
        }

        if config.sqlIncludeDropTable {
            let dropStmt = "DROP TABLE IF EXISTS \(schema.pgQuotedIdentifier).\(table.pgQuotedIdentifier);\n\n"
            if let data = dropStmt.data(using: .utf8) {
                try fileHandle.write(contentsOf: data)
                context.progress.bytesTransferred += Int64(data.count)
            }
        }

        var colNames: [String] = []
        var rowBatch: [[String]] = []
        let batchLimit = max(1, config.sqlBatchSize)

        func flushBatch() throws {
            guard !rowBatch.isEmpty else { return }
            let colsClause = colNames.map { $0.pgQuotedIdentifier }.joined(separator: ", ")
            var valueRows: [String] = []

            for r in rowBatch {
                let vals = r.map { val -> String in
                    if val.isEmpty { return "NULL" }
                    return "'\(val.pgEscapedLiteral)'"
                }.joined(separator: ", ")
                valueRows.append("(\(vals))")
            }

            let insertSQL = "INSERT INTO \(schema.pgQuotedIdentifier).\(table.pgQuotedIdentifier) (\(colsClause))\nVALUES\n  " +
                valueRows.joined(separator: ",\n  ") + ";\n\n"

            if let data = insertSQL.data(using: .utf8) {
                try fileHandle.write(contentsOf: data)
                context.progress.bytesTransferred += Int64(data.count)
            }
            rowBatch.removeAll(keepingCapacity: true)
        }

        _ = try await postgresService.streamQuery(querySQL) { columns, row in
            if colNames.isEmpty {
                colNames = columns.map(\.name)
            }

            let strValues = row.map { cell -> String in
                switch cell {
                case .null: return ""
                case .string(let s): return s
                case .int(let i): return "\(i)"
                case .double(let d): return "\(d)"
                case .bool(let b): return b ? "true" : "false"
                case .date(let d): return d
                case .data(let data): return "\\x" + data.map { String(format: "%02hhx", $0) }.joined()
                case .json(let j): return j
                case .array(let a): return a
                }
            }

            rowBatch.append(strValues)
            context.progress.rowsProcessed += 1

            if rowBatch.count >= batchLimit {
                try flushBatch()
                context.notify()
            }
        }

        try flushBatch()

        let footer = "COMMIT;\n"
        if let data = footer.data(using: .utf8) {
            try fileHandle.write(contentsOf: data)
            context.progress.bytesTransferred += Int64(data.count)
        }
    }

    private func exportTableViaPgDump(
        schema: String,
        table: String,
        destinationURL: URL,
        context: ExportContext
    ) async throws {
        guard let config = await postgresService.activeConfig,
              let password = await postgresService.activePassword else {
            throw PostgresServiceError.notConnected
        }

        let args = [
            "-h", config.host,
            "-p", "\(config.port)",
            "-U", config.username,
            "-d", config.database,
            "-t", "\(schema).\(table)",
            "-F", "c",
            "-f", destinationURL.path
        ]

        context.progress.currentOperation = "Running pg_dump for \(schema).\(table)..."
        context.notify()

        try await toolchainService.runDump(config: config, password: password, arguments: args) { [weak context] log in
            context?.progress.currentOperation = log.trimmingCharacters(in: .whitespacesAndNewlines)
            context?.notify()
        }
    }

    // MARK: - Schema and Database Export (Toolchain)

    private func exportSchemaOrDatabase(
        isSchema: Bool,
        targetName: String,
        config: ExportConfiguration,
        destinationURL: URL,
        context: ExportContext
    ) async throws {
        guard let connConfig = await postgresService.activeConfig,
              let password = await postgresService.activePassword else {
            throw PostgresServiceError.notConnected
        }

        if toolchainService.isPgDumpAvailable {
            var args = [
                "-h", connConfig.host,
                "-p", "\(connConfig.port)",
                "-U", connConfig.username,
                "-d", isSchema ? connConfig.database : targetName
            ]

            if isSchema {
                args.append(contentsOf: ["-n", targetName])
            }

            if config.cleanBeforeRestore {
                args.append("--clean")
                args.append("--if-exists")
            }

            if !config.exportStructure {
                args.append("--data-only")
            } else if !config.exportData {
                args.append("--schema-only")
            }

            switch config.format {
            case .customDump:
                args.append(contentsOf: ["-F", "c"])
            default:
                args.append(contentsOf: ["-F", "p"])
            }

            args.append(contentsOf: ["-f", destinationURL.path])

            context.progress.currentOperation = "Dumping \(isSchema ? "schema" : "database") \(targetName)..."
            context.notify()

            try await toolchainService.runDump(config: connConfig, password: password, arguments: args) { [weak context] log in
                context?.progress.currentOperation = log.trimmingCharacters(in: .whitespacesAndNewlines)
                context?.notify()
            }
        } else {
            throw NSError(
                domain: "ExportService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Full \(isSchema ? "schema" : "database") export requires pg_dump. Install PostgreSQL tools via Homebrew (`brew install libpq` or `brew install postgresql`)."]
            )
        }
    }
}
