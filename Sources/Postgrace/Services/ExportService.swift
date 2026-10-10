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
                try await exportSchemaOrDatabase(
                    isSchema: true,
                    targetName: schemaName,
                    config: config,
                    destinationURL: destinationURL,
                    context: context
                )
            case .multipleSchemas(let schemaNames):
                try await exportMultipleSchemas(
                    schemaNames: schemaNames,
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

            if Task.isCancelled {
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try? FileManager.default.removeItem(at: destinationURL)
                }
                context.progress.status = .cancelled
                throw CancellationError()
            } else {
                context.progress.status = .completed("Successfully exported to \(destinationURL.lastPathComponent)")
            }
            context.notify()
        } catch is CancellationError {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            context.progress.status = .cancelled
            context.notify()
            throw CancellationError()
        } catch {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
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
        let engine = await postgresService.activeConfig?.engine ?? .postgresql
        if engine == .mysql || engine == .mariadb {
            let res = try? await postgresService.executeQuery("SHOW CREATE TABLE \(schema.mysqlQuotedIdentifier).\(table.mysqlQuotedIdentifier);")
            if let first = res?.rows.first, first.count >= 2, case .string(let ddl) = first[1] {
                return "\(ddl);\n\n"
            }
        }

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

    // MARK: - Schema and Database Export (Toolchain & Native Streaming Fallback)

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

            if config.cleanBeforeRestore {
                args.append("--clean")
                args.append("--if-exists")
            }

            if config.contentMode == .structureOnly {
                args.append("--schema-only")
            } else if config.contentMode == .dataOnly {
                args.append("--data-only")
            }

            if config.format == .customDump {
                args.append(contentsOf: ["-Z", "\(config.postgresOptions.customDumpCompressionLevel)"])
            }

            args.append(contentsOf: ["-f", destinationURL.path])

            context.progress.currentOperation = "Dumping \(schemaNames.count) schemas..."
            context.notify()

            try await toolchainService.runDump(config: connConfig, password: password, arguments: args) { [weak context] log in
                context?.progress.currentOperation = log.trimmingCharacters(in: .whitespacesAndNewlines)
                context?.notify()
            }
        } else {
            try await exportSchemasNative(
                schemaNames: schemaNames,
                config: config,
                destinationURL: destinationURL,
                context: context
            )
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
            } else if !config.selectedSchemas.isEmpty {
                for s in config.selectedSchemas {
                    args.append(contentsOf: ["-n", s])
                }
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
                args.append(contentsOf: ["-F", "c", "-Z", "\(config.postgresOptions.customDumpCompressionLevel)"])
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
            if isSchema {
                try await exportSchemasNative(
                    schemaNames: [targetName],
                    config: config,
                    destinationURL: destinationURL,
                    context: context
                )
            } else {
                var targetSchemas = config.selectedSchemas
                if targetSchemas.isEmpty {
                    let schemaQuery = """
                        SELECT nspname 
                        FROM pg_namespace 
                        WHERE nspname NOT LIKE 'pg_%' 
                          AND nspname != 'information_schema'
                        ORDER BY nspname ASC;
                    """
                    if let res = try? await postgresService.executeQuery(schemaQuery) {
                        for r in res.rows {
                            if let first = r.first, case .string(let s) = first {
                                targetSchemas.append(s)
                            }
                        }
                    }
                    if targetSchemas.isEmpty {
                        targetSchemas = ["public"]
                    }
                }
                try await exportSchemasNative(
                    schemaNames: targetSchemas,
                    config: config,
                    destinationURL: destinationURL,
                    context: context
                )
            }
        }
    }

    /// Native Swift streaming fallback for multi-schema and full database exports.
    /// Strictly enforces topological DDL ordering:
    /// Stage 01: Schema Declaration -> Stage 02: Search Path -> Stage 04: Custom Types & ENUMs ->
    /// Stage 05: Sequences -> Stage 06: Base Tables -> Stage 07: Data Loading ->
    /// Stage 08: Sequence Sync -> Stage 10: Foreign Keys -> Stage 11: Views.
    private func exportSchemasNative(
        schemaNames: [String],
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

        func writeSQL(_ text: String) throws {
            if let data = text.data(using: .utf8) {
                try bufferedHandle.write(data)
                context.progress.bytesTransferred += Int64(data.count)
            }
        }

        // Header Metadata
        let headerComments = """
        -- ============================================================
        -- Postgrace Database Dump (Native Swift NIO Streaming Engine)
        -- Scope: \(config.scope.title)
        -- Schemas: \(schemaNames.joined(separator: ", "))
        -- Mode: \(config.contentMode.rawValue)
        -- Date: \(Date())
        -- ============================================================

        """
        try writeSQL(headerComments)

        if config.postgresOptions.singleTransaction {
            try writeSQL("BEGIN;\n\n")
        }

        let engine = await postgresService.activeConfig?.engine ?? .postgresql

        // Stage 01: Clean & Schema Declaration
        if config.cleanBeforeRestore {
            for s in schemaNames {
                try writeSQL("DROP SCHEMA IF EXISTS \(s.pgQuotedIdentifier) CASCADE;\n")
            }
            try writeSQL("\n")
        }

        if config.postgresOptions.includeSchemaCreate {
            for s in schemaNames {
                try writeSQL("CREATE SCHEMA IF NOT EXISTS \(s.pgQuotedIdentifier);\n")
            }
            try writeSQL("\n")
        }

        // Stage 02: Search Path Setup
        if config.postgresOptions.setPathHeader && !schemaNames.isEmpty {
            let pathTokens = schemaNames.map { $0.pgQuotedIdentifier } + ["pg_catalog"]
            try writeSQL("SET search_path = \(pathTokens.joined(separator: ", "));\n\n")
        }

        // Stage 04: Custom Types & ENUMs
        if config.exportStructure && engine == .postgresql {
            for s in schemaNames {
                let enumQuery = """
                    SELECT t.typname, 
                           array_to_string(array_agg(quote_literal(e.enumlabel) ORDER BY e.enumsortorder), ', ') as enum_values
                    FROM pg_type t
                    JOIN pg_enum e ON t.oid = e.enumtypid
                    JOIN pg_namespace n ON n.oid = t.typnamespace
                    WHERE n.nspname = '\(s.pgEscapedLiteral)'
                    GROUP BY t.typname
                    ORDER BY t.typname;
                """
                if let res = try? await postgresService.executeQuery(enumQuery), !res.rows.isEmpty {
                    try writeSQL("-- Stage 04: Custom Types & ENUMs (\(s))\n")
                    for r in res.rows {
                        if r.count >= 2,
                           case .string(let typeName) = r[0],
                           case .string(let enumVals) = r[1] {
                            if config.cleanBeforeRestore {
                                try writeSQL("DROP TYPE IF EXISTS \(s.pgQuotedIdentifier).\(typeName.pgQuotedIdentifier) CASCADE;\n")
                            }
                            try writeSQL("CREATE TYPE \(s.pgQuotedIdentifier).\(typeName.pgQuotedIdentifier) AS ENUM (\(enumVals));\n")
                        }
                    }
                    try writeSQL("\n")
                }
            }
        }

        // Stage 05: Sequences
        if config.exportStructure && engine == .postgresql {
            for s in schemaNames {
                let seqQuery = """
                    SELECT c.relname
                    FROM pg_class c
                    JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE c.relkind = 'S' AND n.nspname = '\(s.pgEscapedLiteral)'
                    ORDER BY c.relname;
                """
                if let res = try? await postgresService.executeQuery(seqQuery), !res.rows.isEmpty {
                    try writeSQL("-- Stage 05: Sequences (\(s))\n")
                    for r in res.rows {
                        if let first = r.first, case .string(let seqName) = first {
                            if config.cleanBeforeRestore {
                                try writeSQL("DROP SEQUENCE IF EXISTS \(s.pgQuotedIdentifier).\(seqName.pgQuotedIdentifier) CASCADE;\n")
                            }
                            try writeSQL("CREATE SEQUENCE IF NOT EXISTS \(s.pgQuotedIdentifier).\(seqName.pgQuotedIdentifier);\n")
                        }
                    }
                    try writeSQL("\n")
                }
            }
        }

        // Stage 06: Base Tables (Structure Only)
        var tablesToExport: [ExportTableItem] = []
        if !config.selectedTables.isEmpty {
            tablesToExport = config.selectedTables.filter { schemaNames.contains($0.schema) }
        } else {
            let schemasClause = schemaNames.map { "'\($0.pgEscapedLiteral)'" }.joined(separator: ", ")
            let tablesQuery = """
                SELECT table_schema, table_name
                FROM information_schema.tables
                WHERE table_schema IN (\(schemasClause))
                  AND table_type = 'BASE TABLE'
                ORDER BY table_schema ASC, table_name ASC;
            """
            if let res = try? await postgresService.executeQuery(tablesQuery) {
                for r in res.rows {
                    if r.count >= 2,
                       case .string(let s) = r[0],
                       case .string(let t) = r[1] {
                        tablesToExport.append(ExportTableItem(schema: s, table: t))
                    }
                }
            }
        }

        if config.exportStructure {
            try writeSQL("-- Stage 06: Base Tables\n\n")
            for t in tablesToExport {
                if Task.isCancelled { throw CancellationError() }
                if config.cleanBeforeRestore || config.sqlIncludeDropTable {
                    try writeSQL("DROP TABLE IF EXISTS \(t.schema.pgQuotedIdentifier).\(t.table.pgQuotedIdentifier) CASCADE;\n")
                }
                let ddl = try await fetchTableDDL(schema: t.schema, table: t.table)
                try writeSQL(ddl)
            }
        }

        // Stage 07: Data Loading
        if config.exportData {
            try writeSQL("-- Stage 07: Data Loading\n\n")
            for (index, t) in tablesToExport.enumerated() {
                if Task.isCancelled { throw CancellationError() }
                context.progress.currentOperation = "Exporting data [\(index + 1)/\(tablesToExport.count)] \(t.schema).\(t.table)..."
                context.notify()

                var querySQL = "SELECT * FROM \(t.schema.pgQuotedIdentifier).\(t.table.pgQuotedIdentifier)"
                if !config.whereClause.isEmpty && tablesToExport.count == 1 {
                    querySQL += " WHERE \(config.whereClause)"
                }
                try await streamTableRowsToSQL(
                    schema: t.schema,
                    table: t.table,
                    querySQL: querySQL,
                    batchSize: config.sqlBatchSize,
                    bufferedHandle: bufferedHandle,
                    context: context
                )
            }
        }

        // Stage 08: Sequence Synchronization (setval)
        if config.exportData && engine == .postgresql {
            var hasEmittedSeqSyncHeader = false
            for s in schemaNames {
                let syncQuery = """
                    SELECT
                        s.relname AS sequence_name,
                        t.relname AS table_name,
                        a.attname AS column_name
                    FROM pg_class s
                    JOIN pg_depend d ON d.objid = s.oid AND d.classid = 'pg_class'::regclass AND d.refclassid = 'pg_class'::regclass
                    JOIN pg_class t ON t.oid = d.refobjid
                    JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = d.refobjsubid
                    JOIN pg_namespace n ON n.oid = s.relnamespace
                    WHERE s.relkind = 'S'
                      AND n.nspname = '\(s.pgEscapedLiteral)'
                    ORDER BY s.relname;
                """
                if let res = try? await postgresService.executeQuery(syncQuery), !res.rows.isEmpty {
                    for r in res.rows {
                        if r.count >= 3,
                           case .string(let seqName) = r[0],
                           case .string(let tableName) = r[1],
                           case .string(let colName) = r[2] {
                            if tablesToExport.contains(where: { $0.schema == s && $0.table == tableName }) {
                                if !hasEmittedSeqSyncHeader {
                                    try writeSQL("\n-- Stage 08: Sequence Synchronization\n")
                                    hasEmittedSeqSyncHeader = true
                                }
                                try writeSQL("SELECT setval('\(s.pgQuotedIdentifier).\(seqName.pgQuotedIdentifier)', (SELECT COALESCE(MAX(\(colName.pgQuotedIdentifier)), 1) FROM \(s.pgQuotedIdentifier).\(tableName.pgQuotedIdentifier)));\n")
                            }
                        }
                    }
                }
            }
            if hasEmittedSeqSyncHeader {
                try writeSQL("\n")
            }
        }

        // Stage 10: Foreign Key Constraints
        if config.exportStructure && engine == .postgresql {
            var hasEmittedFKHeader = false
            for s in schemaNames {
                let fkQuery = """
                    SELECT
                        con.conname AS constraint_name,
                        src_ns.nspname AS src_schema,
                        src_cl.relname AS src_table,
                        ref_ns.nspname AS ref_schema,
                        ref_cl.relname AS ref_table,
                        pg_get_constraintdef(con.oid) AS constraint_def
                    FROM pg_constraint con
                    JOIN pg_class src_cl ON src_cl.oid = con.conrelid
                    JOIN pg_namespace src_ns ON src_ns.oid = src_cl.relnamespace
                    JOIN pg_class ref_cl ON ref_cl.oid = con.confrelid
                    JOIN pg_namespace ref_ns ON ref_ns.oid = ref_cl.relnamespace
                    WHERE con.contype = 'f'
                      AND src_ns.nspname = '\(s.pgEscapedLiteral)'
                    ORDER BY con.conname;
                """
                if let res = try? await postgresService.executeQuery(fkQuery), !res.rows.isEmpty {
                    for r in res.rows {
                        if r.count >= 6,
                           case .string(let conName) = r[0],
                           case .string(let srcSchema) = r[1],
                           case .string(let srcTable) = r[2],
                           case .string(let refSchema) = r[3],
                           case .string(_) = r[4],
                           case .string(let conDef) = r[5] {
                            if tablesToExport.contains(where: { $0.schema == srcSchema && $0.table == srcTable }) {
                                if !hasEmittedFKHeader {
                                    try writeSQL("-- Stage 10: Foreign Key Constraints\n")
                                    hasEmittedFKHeader = true
                                }
                                let isExternal = !schemaNames.contains(refSchema)
                                if isExternal && !config.postgresOptions.includeExternalForeignKeys {
                                    try writeSQL("-- [EXTERNAL FK ISOLATED] ALTER TABLE \(srcSchema.pgQuotedIdentifier).\(srcTable.pgQuotedIdentifier) ADD CONSTRAINT \(conName.pgQuotedIdentifier) \(conDef);\n")
                                } else {
                                    try writeSQL("ALTER TABLE \(srcSchema.pgQuotedIdentifier).\(srcTable.pgQuotedIdentifier) ADD CONSTRAINT \(conName.pgQuotedIdentifier) \(conDef);\n")
                                }
                            }
                        }
                    }
                }
            }
            if hasEmittedFKHeader {
                try writeSQL("\n")
            }
        }

        // Stage 11: Standard & Materialized Views
        if config.exportStructure {
            var hasEmittedViewHeader = false
            for s in schemaNames {
                let viewQuery = """
                    SELECT table_name, view_definition
                    FROM information_schema.views
                    WHERE table_schema = '\(s.pgEscapedLiteral)'
                    ORDER BY table_name;
                """
                if let res = try? await postgresService.executeQuery(viewQuery), !res.rows.isEmpty {
                    for r in res.rows {
                        if r.count >= 2,
                           case .string(let viewName) = r[0],
                           case .string(let viewDef) = r[1] {
                            if !hasEmittedViewHeader {
                                try writeSQL("-- Stage 11: Views\n")
                                hasEmittedViewHeader = true
                            }
                            try writeSQL("CREATE OR REPLACE VIEW \(s.pgQuotedIdentifier).\(viewName.pgQuotedIdentifier) AS\n\(viewDef);\n\n")
                        }
                    }
                }
            }
        }

        // Footer
        if config.postgresOptions.singleTransaction {
            try writeSQL("COMMIT;\n")
        }

        try bufferedHandle.flush()
    }
}
