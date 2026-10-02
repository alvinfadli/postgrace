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

    private final class BufferedFileHandle {
        private let fileHandle: FileHandle
        private var buffer = Data()
        private let bufferLimit: Int = 64 * 1024 // 64 KB write buffer

        init(fileHandle: FileHandle) {
            self.fileHandle = fileHandle
            buffer.reserveCapacity(bufferLimit)
        }

        func write(_ data: Data) throws {
            buffer.append(data)
            if buffer.count >= bufferLimit {
                try flush()
            }
        }

        func flush() throws {
            guard !buffer.isEmpty else { return }
            try fileHandle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }

        func close() {
            try? flush()
            try? fileHandle.close()
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
            case .multipleTables(let items):
                let tables = items.isEmpty ? config.selectedTables : items
                try await exportMultipleTables(
                    tables: tables,
                    config: config,
                    destinationURL: destinationURL,
                    context: context
                )
            case .schema(let schemaName, _):
                if !toolchainService.isPgDumpAvailable && !config.selectedTables.isEmpty {
                    try await exportMultipleTables(
                        tables: config.selectedTables,
                        config: config,
                        destinationURL: destinationURL,
                        context: context
                    )
                } else {
                    try await exportSchemaOrDatabase(
                        isSchema: true,
                        targetName: schemaName,
                        config: config,
                        destinationURL: destinationURL,
                        context: context
                    )
                }
            case .multipleSchemas(let schemaNames):
                try await exportMultipleSchemas(
                    schemaNames: schemaNames,
                    config: config,
                    destinationURL: destinationURL,
                    context: context
                )
            case .database(let dbName):
                if !toolchainService.isPgDumpAvailable && !config.selectedTables.isEmpty {
                    try await exportMultipleTables(
                        tables: config.selectedTables,
                        config: config,
                        destinationURL: destinationURL,
                        context: context
                    )
                } else {
                    try await exportSchemaOrDatabase(
                        isSchema: false,
                        targetName: dbName,
                        config: config,
                        destinationURL: destinationURL,
                        context: context
                    )
                }
            }

            if Task.isCancelled {
                context.progress.status = .cancelled
            } else {
                context.progress.status = .completed("Successfully exported to \(destinationURL.lastPathComponent)")
            }
            context.notify()
        } catch is CancellationError {
            context.progress.status = .cancelled
            context.notify()
            throw CancellationError()
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
        let bufferedHandle = BufferedFileHandle(fileHandle: fileHandle)
        defer { bufferedHandle.close() }

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
                bufferedHandle: bufferedHandle,
                context: context
            )
        case .json:
            try await exportTableToJSON(
                querySQL: querySQL,
                config: config,
                bufferedHandle: bufferedHandle,
                context: context
            )
        case .sql:
            try await exportTableToSQL(
                schema: schema,
                table: table,
                querySQL: querySQL,
                config: config,
                bufferedHandle: bufferedHandle,
                context: context
            )
        case .customDump:
            try await exportTableViaPgDump(
                schema: schema,
                table: table,
                config: config,
                destinationURL: destinationURL,
                context: context
            )
        }

        try bufferedHandle.flush()
    }

    private func exportTableToCSV(
        querySQL: String,
        config: ExportConfiguration,
        bufferedHandle: BufferedFileHandle,
        context: ExportContext
    ) async throws {
        var isFirstRow = true

        if config.csvIncludeBOM {
            if let bomData = "\u{FEFF}".data(using: .utf8) {
                try bufferedHandle.write(bomData)
                context.progress.bytesTransferred += Int64(bomData.count)
            }
        }

        _ = try await postgresService.streamQuery(querySQL) { columns, row in
            if Task.isCancelled {
                throw CancellationError()
            }

            if isFirstRow {
                isFirstRow = false
                if config.csvIncludeHeaders {
                    let headerLine = CSVHandler.encodeRow(columns.map(\.name), delimiter: config.csvDelimiter) + "\n"
                    if let data = headerLine.data(using: .utf8) {
                        try bufferedHandle.write(data)
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
                try bufferedHandle.write(data)
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
        bufferedHandle: BufferedFileHandle,
        context: ExportContext
    ) async throws {
        let isNDJSON = config.jsonFlavor == .ndjson
        var isFirstRow = true

        if !isNDJSON {
            let startArray = "[\n"
            if let data = startArray.data(using: .utf8) {
                try bufferedHandle.write(data)
                context.progress.bytesTransferred += Int64(data.count)
            }
        }

        _ = try await postgresService.streamQuery(querySQL) { columns, row in
            if Task.isCancelled {
                throw CancellationError()
            }

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
                    try bufferedHandle.write(data)
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
                try bufferedHandle.write(data)
                context.progress.bytesTransferred += Int64(data.count)
            }
        }
    }

    /// Fetches table DDL definition (CREATE TABLE IF NOT EXISTS with columns, types, defaults, and primary keys).
    private func fetchTableDDL(schema: String, table: String) async throws -> String {
        let colQuery = """
            SELECT c.column_name, c.data_type, c.udt_name, c.is_nullable, 
                   c.column_default, c.character_maximum_length,
                   CASE WHEN kcu.column_name IS NOT NULL THEN true ELSE false END as is_primary_key
            FROM information_schema.columns c
            LEFT JOIN information_schema.table_constraints tc 
                   ON tc.table_schema = c.table_schema AND tc.table_name = c.table_name AND tc.constraint_type = 'PRIMARY KEY'
            LEFT JOIN information_schema.key_column_usage kcu 
                   ON kcu.constraint_name = tc.constraint_name AND kcu.column_name = c.column_name
            WHERE c.table_schema = '\(schema.pgEscapedLiteral)' AND c.table_name = '\(table.pgEscapedLiteral)'
            ORDER BY c.ordinal_position;
        """
        let result = try await postgresService.executeQuery(colQuery)
        guard !result.rows.isEmpty else { return "" }

        var columnDefs: [String] = []
        var primaryKeys: [String] = []

        for row in result.rows {
            guard row.count >= 7,
                  case .string(let colName) = row[0],
                  case .string(let dataType) = row[1] else { continue }

            let isNullable: Bool = {
                if case .string(let s) = row[3] { return s.lowercased() == "yes" }
                return true
            }()

            let defVal: String? = {
                if case .string(let s) = row[4] { return s }
                return nil
            }()

            let maxLen: Int? = {
                if case .int(let i) = row[5] { return Int(i) }
                return nil
            }()

            let isPk: Bool = {
                if case .bool(let b) = row[6] { return b }
                return false
            }()

            if isPk && !primaryKeys.contains(colName.pgQuotedIdentifier) {
                primaryKeys.append(colName.pgQuotedIdentifier)
            }

            var typeDecl = dataType
            if dataType == "character varying", let len = maxLen {
                typeDecl = "varchar(\(len))"
            } else if dataType == "character", let len = maxLen {
                typeDecl = "char(\(len))"
            } else if dataType == "USER-DEFINED", case .string(let udt) = row[2] {
                typeDecl = udt
            }

            var colDef = "\(colName.pgQuotedIdentifier) \(typeDecl)"
            if let def = defVal, !def.isEmpty {
                colDef += " DEFAULT \(def)"
            }
            if !isNullable {
                colDef += " NOT NULL"
            }
            columnDefs.append(colDef)
        }

        if !primaryKeys.isEmpty {
            columnDefs.append("PRIMARY KEY (\(primaryKeys.joined(separator: ", ")))")
        }

        return "CREATE TABLE IF NOT EXISTS \(schema.pgQuotedIdentifier).\(table.pgQuotedIdentifier) (\n  " +
            columnDefs.joined(separator: ",\n  ") +
            "\n);\n\n"
    }

    private func streamTableRowsToSQL(
        schema: String,
        table: String,
        querySQL: String,
        batchSize: Int,
        bufferedHandle: BufferedFileHandle,
        context: ExportContext
    ) async throws {
        var colNames: [String] = []
        var rowBatch: [[String]] = []
        let batchLimit = max(1, batchSize)

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
                try bufferedHandle.write(data)
                context.progress.bytesTransferred += Int64(data.count)
            }
            rowBatch.removeAll(keepingCapacity: true)
        }

        _ = try await postgresService.streamQuery(querySQL) { columns, row in
            if Task.isCancelled {
                throw CancellationError()
            }

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
    }

    private func exportTableToSQL(
        schema: String,
        table: String,
        querySQL: String,
        config: ExportConfiguration,
        bufferedHandle: BufferedFileHandle,
        context: ExportContext
    ) async throws {
        let headerComments = """
        -- Postgrace SQL Dump
        -- Target: \(schema).\(table)
        -- Mode: \(config.contentMode.rawValue)
        -- Date: \(Date())
        
        BEGIN;
        
        """
        if let data = headerComments.data(using: .utf8) {
            try bufferedHandle.write(data)
            context.progress.bytesTransferred += Int64(data.count)
        }

        if config.sqlIncludeDropTable {
            let dropStmt = "DROP TABLE IF EXISTS \(schema.pgQuotedIdentifier).\(table.pgQuotedIdentifier);\n\n"
            if let data = dropStmt.data(using: .utf8) {
                try bufferedHandle.write(data)
                context.progress.bytesTransferred += Int64(data.count)
            }
        }

        // 1. Export Table Structure (DDL)
        if config.exportStructure {
            let ddl = try await fetchTableDDL(schema: schema, table: table)
            if let data = ddl.data(using: .utf8) {
                try bufferedHandle.write(data)
                context.progress.bytesTransferred += Int64(data.count)
            }
        }

        // 2. Export Table Data (INSERT batches)
        if config.exportData {
            try await streamTableRowsToSQL(
                schema: schema,
                table: table,
                querySQL: querySQL,
                batchSize: config.sqlBatchSize,
                bufferedHandle: bufferedHandle,
                context: context
            )
        }

        let footer = "COMMIT;\n"
        if let data = footer.data(using: .utf8) {
            try bufferedHandle.write(data)
            context.progress.bytesTransferred += Int64(data.count)
        }
    }

    private func exportTableViaPgDump(
        schema: String,
        table: String,
        config: ExportConfiguration,
        destinationURL: URL,
        context: ExportContext
    ) async throws {
        guard let connConfig = await postgresService.activeConfig,
              let password = await postgresService.activePassword else {
            throw PostgresServiceError.notConnected
        }

        var args = [
            "-h", connConfig.host,
            "-p", "\(connConfig.port)",
            "-U", connConfig.username,
            "-d", connConfig.database,
            "-t", "\(schema).\(table)",
            "-F", "c"
        ]

        if config.contentMode == .structureOnly {
            args.append("--schema-only")
        } else if config.contentMode == .dataOnly {
            args.append("--data-only")
        }

        if config.cleanBeforeRestore {
            args.append("--clean")
            args.append("--if-exists")
        }

        args.append(contentsOf: ["-f", destinationURL.path])

        context.progress.currentOperation = "Running pg_dump for \(schema).\(table)..."
        context.notify()

        try await toolchainService.runDump(config: connConfig, password: password, arguments: args) { [weak context] log in
            context?.progress.currentOperation = log.trimmingCharacters(in: .whitespacesAndNewlines)
            context?.notify()
        }
    }

    // MARK: - Multi-Table Export

    private func exportMultipleTables(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        destinationURL: URL,
        context: ExportContext
    ) async throws {
        guard !tables.isEmpty else {
            throw NSError(
                domain: "ExportService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No tables selected for export."]
            )
        }

        switch config.format {
        case .sql:
            try await exportMultipleTablesToSQL(
                tables: tables,
                config: config,
                destinationURL: destinationURL,
                context: context
            )
        case .customDump:
            try await exportMultipleTablesViaPgDump(
                tables: tables,
                config: config,
                destinationURL: destinationURL,
                context: context
            )
        case .json:
            try await exportMultipleTablesToJSON(
                tables: tables,
                config: config,
                destinationURL: destinationURL,
                context: context
            )
        case .csv:
            // Single CSV cannot hold multiple tables; export first or stream sequentially
            if let first = tables.first {
                try await exportTable(
                    schema: first.schema,
                    table: first.table,
                    config: config,
                    destinationURL: destinationURL,
                    context: context
                )
            }
        }
    }

    private func exportMultipleTablesToSQL(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        destinationURL: URL,
        context: ExportContext
    ) async throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
        let fileHandle = try FileHandle(forWritingTo: destinationURL)
        let bufferedHandle = BufferedFileHandle(fileHandle: fileHandle)
        defer { bufferedHandle.close() }

        let headerComments = """
        -- Postgrace Multi-Table SQL Dump
        -- Tables: \(tables.map(\.id).joined(separator: ", "))
        -- Mode: \(config.contentMode.rawValue)
        -- Date: \(Date())

        BEGIN;

        """
        if let data = headerComments.data(using: .utf8) {
            try bufferedHandle.write(data)
            context.progress.bytesTransferred += Int64(data.count)
        }

        for (index, item) in tables.enumerated() {
            if Task.isCancelled {
                throw CancellationError()
            }

            context.progress.currentOperation = "Exporting [\(index + 1)/\(tables.count)] \(item.schema).\(item.table)..."
            context.notify()

            let sectionHeader = "\n-- ------------------------------------------------------------\n-- Table: \(item.schema).\(item.table)\n-- ------------------------------------------------------------\n\n"
            if let data = sectionHeader.data(using: .utf8) {
                try bufferedHandle.write(data)
            }

            if config.sqlIncludeDropTable {
                let dropStmt = "DROP TABLE IF EXISTS \(item.schema.pgQuotedIdentifier).\(item.table.pgQuotedIdentifier);\n\n"
                if let data = dropStmt.data(using: .utf8) {
                    try bufferedHandle.write(data)
                }
            }

            if config.exportStructure {
                let ddl = try await fetchTableDDL(schema: item.schema, table: item.table)
                if let data = ddl.data(using: .utf8) {
                    try bufferedHandle.write(data)
                    context.progress.bytesTransferred += Int64(data.count)
                }
            }

            if config.exportData {
                var querySQL = "SELECT * FROM \(item.schema.pgQuotedIdentifier).\(item.table.pgQuotedIdentifier)"
                let trimmedWhere = config.whereClause.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedWhere.isEmpty {
                    querySQL += " WHERE \(trimmedWhere)"
                }
                if let limit = config.limit, limit > 0 {
                    querySQL += " LIMIT \(limit)"
                }

                try await streamTableRowsToSQL(
                    schema: item.schema,
                    table: item.table,
                    querySQL: querySQL,
                    batchSize: config.sqlBatchSize,
                    bufferedHandle: bufferedHandle,
                    context: context
                )
            }
        }

        let footer = "COMMIT;\n"
        if let data = footer.data(using: .utf8) {
            try bufferedHandle.write(data)
            context.progress.bytesTransferred += Int64(data.count)
        }

        try bufferedHandle.flush()
    }

    private func exportMultipleTablesViaPgDump(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        destinationURL: URL,
        context: ExportContext
    ) async throws {
        guard let connConfig = await postgresService.activeConfig,
              let password = await postgresService.activePassword else {
            throw PostgresServiceError.notConnected
        }

        if toolchainService.isPgDumpAvailable {
            let formatFlag = config.format == .customDump ? "c" : "p"
            var args = [
                "-h", connConfig.host,
                "-p", "\(connConfig.port)",
                "-U", connConfig.username,
                "-d", connConfig.database,
                "-F", formatFlag
            ]

            for item in tables {
                args.append(contentsOf: ["-t", "\(item.schema).\(item.table)"])
            }

            if config.cleanBeforeRestore {
                args.append("--clean")
                args.append("--if-exists")
            }

            if config.contentMode == .structureOnly {
                args.append("--schema-only")
            } else if config.contentMode == .dataOnly {
                args.append("--data-only")
            }

            args.append(contentsOf: ["-f", destinationURL.path])

            context.progress.currentOperation = "Running pg_dump for \(tables.count) tables..."
            context.notify()

            try await toolchainService.runDump(config: connConfig, password: password, arguments: args) { [weak context] log in
                context?.progress.currentOperation = log.trimmingCharacters(in: .whitespacesAndNewlines)
                context?.notify()
            }
        } else {
            try await exportMultipleTablesToSQL(
                tables: tables,
                config: config,
                destinationURL: destinationURL,
                context: context
            )
        }
    }

    private func exportMultipleTablesToJSON(
        tables: [ExportTableItem],
        config: ExportConfiguration,
        destinationURL: URL,
        context: ExportContext
    ) async throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        FileManager.default.createFile(atPath: destinationURL.path, contents: nil, attributes: nil)
        let fileHandle = try FileHandle(forWritingTo: destinationURL)
        let bufferedHandle = BufferedFileHandle(fileHandle: fileHandle)
        defer { bufferedHandle.close() }

        let startObj = "{\n"
        if let data = startObj.data(using: .utf8) {
            try bufferedHandle.write(data)
        }

        for (tIndex, item) in tables.enumerated() {
            if Task.isCancelled {
                throw CancellationError()
            }

            context.progress.currentOperation = "Exporting JSON [\(tIndex + 1)/\(tables.count)] \(item.schema).\(item.table)..."
            context.notify()

            let tableKey = "  \"\(item.schema).\(item.table)\": [\n"
            if let data = tableKey.data(using: .utf8) {
                try bufferedHandle.write(data)
            }

            var querySQL = "SELECT * FROM \(item.schema.pgQuotedIdentifier).\(item.table.pgQuotedIdentifier)"
            let trimmedWhere = config.whereClause.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedWhere.isEmpty {
                querySQL += " WHERE \(trimmedWhere)"
            }
            if let limit = config.limit, limit > 0 {
                querySQL += " LIMIT \(limit)"
            }

            var isFirstRow = true
            _ = try await postgresService.streamQuery(querySQL) { columns, row in
                if Task.isCancelled {
                    throw CancellationError()
                }

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
                    let line = (isFirstRow ? "    " : ",\n    ") + jsonString
                    isFirstRow = false
                    if let data = line.data(using: .utf8) {
                        try bufferedHandle.write(data)
                        context.progress.bytesTransferred += Int64(data.count)
                    }
                }

                context.progress.rowsProcessed += 1
                if context.progress.rowsProcessed % 100 == 0 {
                    context.notify()
                }
            }

            let endTable = "\n  ]" + (tIndex < tables.count - 1 ? ",\n" : "\n")
            if let data = endTable.data(using: .utf8) {
                try bufferedHandle.write(data)
            }
        }

        let endObj = "}\n"
        if let data = endObj.data(using: .utf8) {
            try bufferedHandle.write(data)
        }

        try bufferedHandle.flush()
    }

    // MARK: - Schema and Database Export (Toolchain)

    private func exportMultipleSchemas(
        schemaNames: [String],
        config: ExportConfiguration,
        destinationURL: URL,
        context: ExportContext
    ) async throws {
        guard let connConfig = await postgresService.activeConfig,
              let password = await postgresService.activePassword else {
            throw PostgresServiceError.notConnected
        }

        if toolchainService.isPgDumpAvailable {
            let formatFlag = config.format == .customDump ? "c" : "p"
            var args = [
                "-h", connConfig.host,
                "-p", "\(connConfig.port)",
                "-U", connConfig.username,
                "-d", connConfig.database,
                "-F", formatFlag
            ]

            for s in schemaNames {
                args.append(contentsOf: ["-n", s])
            }

            for t in config.selectedTables {
                args.append(contentsOf: ["-t", "\(t.schema).\(t.table)"])
            }

            if config.cleanBeforeRestore {
                args.append("--clean")
                args.append("--if-exists")
            }

            if config.contentMode == .structureOnly {
                args.append("--schema-only")
            } else if config.contentMode == .dataOnly {
                args.append("--data-only")
            }

            args.append(contentsOf: ["-f", destinationURL.path])

            context.progress.currentOperation = "Dumping \(schemaNames.count) schemas..."
            context.notify()

            try await toolchainService.runDump(config: connConfig, password: password, arguments: args) { [weak context] log in
                context?.progress.currentOperation = log.trimmingCharacters(in: .whitespacesAndNewlines)
                context?.notify()
            }
        } else {
            if !config.selectedTables.isEmpty {
                try await exportMultipleTablesToSQL(
                    tables: config.selectedTables,
                    config: config,
                    destinationURL: destinationURL,
                    context: context
                )
            } else {
                throw NSError(
                    domain: "ExportService",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Full schema export requires pg_dump. Install PostgreSQL tools via Homebrew (`brew install libpq`)."]
                )
            }
        }
    }

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

            for t in config.selectedTables {
                args.append(contentsOf: ["-t", "\(t.schema).\(t.table)"])
            }

            if config.cleanBeforeRestore {
                args.append("--clean")
                args.append("--if-exists")
            }

            if config.contentMode == .structureOnly {
                args.append("--schema-only")
            } else if config.contentMode == .dataOnly {
                args.append("--data-only")
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
