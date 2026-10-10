import Foundation

/// Service orchestrating data import tasks into Tables or Databases.
public final class ImportService {

    private let postgresService: PostgresService
    private let toolchainService = PostgresToolchainService.shared

    public init(postgresService: PostgresService) {
        self.postgresService = postgresService
    }

    private final class ImportContext: @unchecked Sendable {
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

    /// Performs data import according to the configuration.
    public func importData(
        config: ImportConfiguration,
        onProgress: @escaping (DataTransferProgress) -> Void
    ) async throws {
        var initialProgress = DataTransferProgress()
        initialProgress.status = .inProgress
        initialProgress.startTime = Date()

        let context = ImportContext(progress: initialProgress, onProgress: onProgress)
        context.notify()

        do {
            switch config.targetScope {
            case .table(let schema, let table):
                try await importTable(
                    schema: schema,
                    table: table,
                    config: config,
                    context: context
                )
            case .database(let dbName):
                try await importDatabase(
                    databaseName: dbName,
                    config: config,
                    context: context
                )
            }

            context.progress.status = .completed("Successfully imported \(context.progress.rowsProcessed) rows into \(config.targetScope.title)")
            context.notify()
        } catch {
            context.progress.status = .failed(error.localizedDescription)
            context.progress.errorLog.append(error.localizedDescription)
            context.notify()
            throw error
        }
    }

    // MARK: - Table Import (CSV / JSON)

    private func importTable(
        schema: String,
        table: String,
        config: ImportConfiguration,
        context: ImportContext
    ) async throws {
        let validMappings = config.columnMappings.compactMap { item -> (source: String, target: String)? in
            guard let target = item.targetColumn, !target.isEmpty else { return nil }
            return (item.sourceColumn, target)
        }

        guard !validMappings.isEmpty else {
            throw NSError(
                domain: "ImportService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No columns were mapped to target table '\(schema).\(table)'."]
            )
        }

        let targetColumns = validMappings.map(\.target)

        context.progress.currentOperation = "Importing data into \(schema).\(table)..."
        context.notify()

        switch config.sourceType {
        case .csv:
            let delimiterChar = config.csvDelimiter.first ?? ","
            let (fileHeaders, _) = try CSVHandler.inspect(url: config.sourceURL, delimiter: delimiterChar, maxPreviewRows: 1)
            let headerIndices: [Int?] = validMappings.map { mapping in
                fileHeaders.firstIndex(of: mapping.source)
            }

            _ = try await CSVHandler.parseInBatches(
                url: config.sourceURL,
                delimiter: delimiterChar,
                hasHeaders: config.hasHeaders,
                batchSize: config.batchSize
            ) { rowBatch in
                var projectedRows: [[String]] = []
                for row in rowBatch {
                    var projectedRow: [String] = []
                    for idxOpt in headerIndices {
                        if let idx = idxOpt, idx < row.count {
                            projectedRow.append(row[idx])
                        } else {
                            projectedRow.append("")
                        }
                    }
                    projectedRows.append(projectedRow)
                }

                if Task.isCancelled {
                    throw CancellationError()
                }

                do {
                    _ = try await self.postgresService.executeBatchInsert(
                        schema: schema,
                        table: table,
                        columns: targetColumns,
                        rows: projectedRows,
                        treatEmptyAsNull: config.treatEmptyAsNull
                    )
                    context.progress.rowsProcessed += Int64(projectedRows.count)
                    context.notify()
                } catch {
                    if config.conflictPolicy == .abort {
                        throw error
                    } else {
                        context.progress.errorLog.append("Batch error: \(error.localizedDescription)")
                    }
                }
            }

        case .json:
            _ = try await JSONHandler.parseInBatches(
                url: config.sourceURL,
                batchSize: config.batchSize
            ) { recordBatch in
                if Task.isCancelled {
                    throw CancellationError()
                }

                var projectedRows: [[String]] = []
                for record in recordBatch {
                    var projectedRow: [String] = []
                    for mapping in validMappings {
                        projectedRow.append(record[mapping.source] ?? "")
                    }
                    projectedRows.append(projectedRow)
                }

                do {
                    _ = try await self.postgresService.executeBatchInsert(
                        schema: schema,
                        table: table,
                        columns: targetColumns,
                        rows: projectedRows,
                        treatEmptyAsNull: config.treatEmptyAsNull
                    )
                    context.progress.rowsProcessed += Int64(projectedRows.count)
                    context.notify()
                } catch {
                    if config.conflictPolicy == .abort {
                        throw error
                    } else {
                        context.progress.errorLog.append("Batch error: \(error.localizedDescription)")
                    }
                }
            }

        case .sql:
            try await executeSQLScript(
                fileURL: config.sourceURL,
                context: context
            )

        case .customDump:
            throw NSError(
                domain: "ImportService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Binary .dump archives must be restored at the Database level, not into an individual table."]
            )
        }
    }

    // MARK: - Database Import / Restore

    private func importDatabase(
        databaseName: String,
        config: ImportConfiguration,
        context: ImportContext
    ) async throws {
        guard let connConfig = await postgresService.activeConfig,
              let password = await postgresService.activePassword else {
            throw PostgresServiceError.notConnected
        }

        // Pre-create any missing user schemas referenced in the import file
        await ensureRequiredSchemasExist(
            databaseName: databaseName,
            config: config,
            connConfig: connConfig,
            password: password
        )

        switch config.sourceType {
        case .customDump:
            guard toolchainService.isPgRestoreAvailable else {
                throw NSError(
                    domain: "ImportService",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "pg_restore was not found on this system. Install PostgreSQL client tools via Homebrew (`brew install postgresql`)."]
                )
            }

            let args = [
                "-h", connConfig.host,
                "-p", "\(connConfig.port)",
                "-U", connConfig.username,
                "-d", databaseName,
                "--clean",
                "--if-exists",
                "--no-owner",
                config.sourceURL.path
            ]

            context.progress.currentOperation = "Restoring dump into \(databaseName) via pg_restore..."
            context.notify()

            try await toolchainService.runRestore(config: connConfig, password: password, arguments: args) { [weak context] log in
                context?.progress.currentOperation = log.trimmingCharacters(in: .whitespacesAndNewlines)
                context?.notify()
            }

        case .sql:
            if toolchainService.isPsqlAvailable {
                let args = [
                    "-h", connConfig.host,
                    "-p", "\(connConfig.port)",
                    "-U", connConfig.username,
                    "-d", databaseName,
                    "-f", config.sourceURL.path
                ]

                context.progress.currentOperation = "Executing SQL script in \(databaseName) via psql..."
                context.notify()

                try await toolchainService.runPsql(config: connConfig, password: password, arguments: args) { [weak context] log in
                    context?.progress.currentOperation = log.trimmingCharacters(in: .whitespacesAndNewlines)
                    context?.notify()
                }
            } else {
                try await executeSQLScript(
                    fileURL: config.sourceURL,
                    context: context
                )
            }

        case .csv, .json:
            throw NSError(
                domain: "ImportService",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "CSV and JSON files must be imported into a specific table."]
            )
        }
    }

    private func executeSQLScript(
        fileURL: URL,
        context: ImportContext
    ) async throws {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let statements = SQLScriptSplitter.split(content)

        context.progress.totalRows = Int64(statements.count)
        context.progress.currentOperation = "Executing SQL script..."
        context.notify()

        for stmt in statements {
            if Task.isCancelled {
                throw CancellationError()
            }

            let trimmed = stmt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            try await postgresService.executeRawStatement(trimmed)
            context.progress.rowsProcessed += 1

            if context.progress.rowsProcessed % 20 == 0 {
                context.notify()
            }
        }
    }

    /// Automatically discovers all schemas referenced in the import file (dump TOC or SQL script)
    /// and pre-creates them in the target database using `CREATE SCHEMA IF NOT EXISTS`.
    private func ensureRequiredSchemasExist(
        databaseName: String,
        config: ImportConfiguration,
        connConfig: SavedConnection,
        password: String
    ) async {
        var referencedSchemas = Set<String>()

        switch config.sourceType {
        case .customDump:
            if let tocLines = try? await toolchainService.listDumpTOC(fileURL: config.sourceURL) {
                let twoWordDescriptors: Set<String> = [
                    "TABLE DATA", "FK CONSTRAINT", "CHECK CONSTRAINT",
                    "SEQUENCE SET", "MATERIALIZED VIEW", "INDEX ATTACH",
                    "OPERATOR CLASS", "OPERATOR FAMILY", "ROW SECURITY",
                    "EVENT TRIGGER", "BLOB DATA"
                ]

                let invalidSchemaNames: Set<String> = [
                    "-", "public", "DATA", "CONSTRAINT", "SET", "OWNED", "BY",
                    "VIEW", "ATTACH", "CLASS", "FAMILY", "SECURITY", "TRIGGER",
                    "TABLE", "SEQUENCE", "INDEX", "FUNCTION", "PROCEDURE"
                ]

                for line in tocLines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix(";") || trimmed.isEmpty { continue }
                    let parts = trimmed.split(separator: ";", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let rawTokens = parts[1].split(separator: " ").map(String.init)
                    // Drop catalogId and objectId (first 2 tokens)
                    guard rawTokens.count > 2 else { continue }
                    let tokens = Array(rawTokens.dropFirst(2))

                    var schemaCandidate: String? = nil

                    if tokens[0] == "SCHEMA" {
                        // Format: SCHEMA - <tag> <owner>
                        if tokens.count >= 3 && tokens[1] == "-" {
                            schemaCandidate = tokens[2]
                        } else if tokens.count >= 2 && tokens[1] != "-" {
                            schemaCandidate = tokens[1]
                        }
                    } else if tokens.count >= 4 && tokens[0] == "SEQUENCE" && tokens[1] == "OWNED" && tokens[2] == "BY" {
                        schemaCandidate = tokens[3]
                    } else if tokens.count >= 4 && tokens[0] == "MATERIALIZED" && tokens[1] == "VIEW" && tokens[2] == "DATA" {
                        schemaCandidate = tokens[3]
                    } else if tokens.count >= 3 && twoWordDescriptors.contains("\(tokens[0]) \(tokens[1])") {
                        schemaCandidate = tokens[2]
                    } else if tokens.count >= 2 {
                        schemaCandidate = tokens[1]
                    }

                    if let cand = schemaCandidate,
                       !invalidSchemaNames.contains(cand),
                       !cand.hasPrefix("pg_"),
                       cand != "information_schema" {
                        referencedSchemas.insert(cand)
                    }
                }
            }

        case .sql:
            if let content = try? String(contentsOf: config.sourceURL, encoding: .utf8) {
                let pattern = #"(?:CREATE\s+(?:TABLE|VIEW|MATERIALIZED\s+VIEW|TYPE|SEQUENCE)|INSERT\s+INTO|COPY|ALTER\s+TABLE)\s+(?:IF\s+NOT\s+EXISTS\s+)?["']?([a-zA-Z0-9_]+)["']?\s*\."#
                if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                    let nsrange = NSRange(content.startIndex..<content.endIndex, in: content)
                    let matches = regex.matches(in: content, options: [], range: nsrange)
                    for match in matches {
                        if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: content) {
                            let schema = String(content[r])
                            if !schema.hasPrefix("pg_") && schema != "information_schema" && schema != "public" {
                                referencedSchemas.insert(schema)
                            }
                        }
                    }
                }
            }

        case .csv, .json:
            break
        }

        // Clean up any accidentally created empty spurious schemas with RESTRICT
        let cleanupSQL = "DROP SCHEMA IF EXISTS \"DATA\" RESTRICT; DROP SCHEMA IF EXISTS \"CONSTRAINT\" RESTRICT;"
        if toolchainService.isPsqlAvailable {
            let cleanupArgs = [
                "-h", connConfig.host,
                "-p", "\(connConfig.port)",
                "-U", connConfig.username,
                "-d", databaseName,
                "-c", cleanupSQL
            ]
            try? await toolchainService.runPsql(config: connConfig, password: password, arguments: cleanupArgs) { _ in }
        } else if connConfig.database == databaseName {
            try? await postgresService.executeRawStatement(cleanupSQL)
        }

        referencedSchemas.remove("public")
        guard !referencedSchemas.isEmpty else { return }

        let createStatements = referencedSchemas.map { "CREATE SCHEMA IF NOT EXISTS \($0.pgQuotedIdentifier);" }.joined(separator: " ")
        if toolchainService.isPsqlAvailable {
            let args = [
                "-h", connConfig.host,
                "-p", "\(connConfig.port)",
                "-U", connConfig.username,
                "-d", databaseName,
                "-c", createStatements
            ]
            try? await toolchainService.runPsql(config: connConfig, password: password, arguments: args) { _ in }
        } else if connConfig.database == databaseName {
            for s in referencedSchemas {
                try? await postgresService.executeRawStatement("CREATE SCHEMA IF NOT EXISTS \(s.pgQuotedIdentifier);")
            }
        }
    }
}
