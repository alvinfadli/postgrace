import Foundation
import PostgresNIO
import Logging
import NIOCore
import NIOPosix

/// Errors that can occur during PostgreSQL service operations.
public enum PostgresServiceError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to the database."
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .queryFailed(let reason):
            return "Query failed: \(reason)"
        }
    }
}

/// Service for managing a connection to a PostgreSQL database and executing queries.
public actor PostgresService {
    private var connection: PostgresConnection?
    private var currentConfig: SavedConnection?
    private var currentPassword: String?
    private var backendPID: Int32?
    private let logger: Logger

    public init(logger: Logger = Logger(label: "com.postgrace.postgres-service")) {
        self.logger = logger
    }

    /// The name of the active database, if connected.
    public var currentDatabase: String? {
        currentConfig?.database
    }

    /// The active connection configuration, if connected.
    public var activeConfig: SavedConnection? {
        currentConfig
    }

    /// Connects to the PostgreSQL database using the provided configuration.
    public func connect(config: SavedConnection, password: String) async throws {
        if connection != nil {
            try await disconnect()
        }

        var tlsConfig: PostgresConnection.Configuration.TLS = .disable
        if config.sslMode == .require {
            var nioTLS = TLSConfiguration.makeClientConfiguration()
            nioTLS.certificateVerification = .fullVerification
            tlsConfig = try .require(.init(configuration: nioTLS))
        }

        let pgConfig = PostgresConnection.Configuration(
            host: config.host,
            port: config.port,
            username: config.username,
            password: password,
            database: config.database,
            tls: tlsConfig
        )

        do {
            self.connection = try await PostgresConnection.connect(
                on: MultiThreadedEventLoopGroup.singleton.any(),
                configuration: pgConfig,
                id: 1,
                logger: logger
            )
            self.currentConfig = config
            self.currentPassword = password

            // Introspect backend process ID for query cancellation
            do {
                if let rows = try await self.connection?.query("SELECT pg_backend_pid();", logger: logger) {
                    for try await row in rows {
                        let columns = row.makeRandomAccess()
                        if let first = columns.first, let pid = try? first.decode(Int32.self) {
                            self.backendPID = pid
                        }
                        break
                    }
                }
            } catch {
                logger.warning("Could not determine pg_backend_pid: \(error)")
            }
        } catch {
            throw PostgresServiceError.connectionFailed(error.localizedDescription)
        }
    }

    /// Switches the active connection to another database on the same host using existing credentials.
    public func switchDatabase(to newDatabase: String) async throws {
        guard let config = currentConfig, let password = currentPassword else {
            throw PostgresServiceError.notConnected
        }
        var updatedConfig = config
        updatedConfig.database = newDatabase
        try await connect(config: updatedConfig, password: password)
    }

    /// Disconnects from the current PostgreSQL database.
    public func disconnect() async throws {
        if let conn = connection {
            try await conn.close()
            self.connection = nil
            self.currentConfig = nil
            self.currentPassword = nil
            self.backendPID = nil
        }
    }

    /// Cancels the currently running query by sending pg_cancel_backend to PostgreSQL.
    public func cancelRunningQuery() async {
        guard let pid = backendPID, let config = currentConfig else { return }
        let pwd = currentPassword ?? ""

        var tlsConfig: PostgresConnection.Configuration.TLS = .disable
        if config.sslMode == .require {
            var nioTLS = TLSConfiguration.makeClientConfiguration()
            nioTLS.certificateVerification = .fullVerification
            tlsConfig = (try? .require(.init(configuration: nioTLS))) ?? .disable
        }

        let cancelConfig = PostgresConnection.Configuration(
            host: config.host,
            port: config.port,
            username: config.username,
            password: pwd,
            database: config.database,
            tls: tlsConfig
        )

        do {
            let cancelConn = try await PostgresConnection.connect(
                on: MultiThreadedEventLoopGroup.singleton.any(),
                configuration: cancelConfig,
                id: 999,
                logger: logger
            )
            _ = try await cancelConn.query(PostgresQuery(stringLiteral: "SELECT pg_cancel_backend(\(pid));"), logger: logger)
            try await cancelConn.close()
            logger.info("Successfully sent pg_cancel_backend for backend PID \(pid)")
        } catch {
            logger.warning("Failed to cancel backend PID \(pid): \(error)")
        }
    }

    /// Tests the connection without persisting it.
    public func testConnection(config: SavedConnection, password: String) async throws -> Bool {
        var tlsConfig: PostgresConnection.Configuration.TLS = .disable
        if config.sslMode == .require {
            var nioTLS = TLSConfiguration.makeClientConfiguration()
            nioTLS.certificateVerification = .fullVerification
            tlsConfig = try .require(.init(configuration: nioTLS))
        }

        let pgConfig = PostgresConnection.Configuration(
            host: config.host,
            port: config.port,
            username: config.username,
            password: password,
            database: config.database,
            tls: tlsConfig
        )

        do {
            let tempConnection = try await PostgresConnection.connect(
                on: MultiThreadedEventLoopGroup.singleton.any(),
                configuration: pgConfig,
                id: 0,
                logger: logger
            )
            try await tempConnection.close()
            return true
        } catch {
            return false
        }
    }

    /// Checks if the service is currently connected to a database.
    public var isConnected: Bool {
        connection != nil
    }

    /// Executes a SQL query and returns the results.
    public func executeQuery(_ sql: String) async throws -> QueryResult {
        guard let conn = connection else {
            throw PostgresServiceError.notConnected
        }

        let start = ContinuousClock.now
        var resultColumns: [ResultColumn] = []
        var cellRows: [[CellValue]] = []

        do {
            let rows = try await conn.query(PostgresQuery(stringLiteral: sql), logger: logger)

            // Extract column metadata directly from row sequence (works even for 0-row results)
            for col in rows.columns {
                resultColumns.append(ResultColumn(
                    name: col.name,
                    dataTypeOID: col.dataType.rawValue,
                    dataTypeName: "\(col.dataType)"
                ))
            }

            for try await row in rows {
                let columns = row.makeRandomAccess()

                var cellRow: [CellValue] = []
                for cell in columns {
                    // Check for NULL first
                    guard cell.bytes != nil else {
                        cellRow.append(.null)
                        continue
                    }

                    // Decode based on PostgreSQL data type for better fidelity
                    switch cell.dataType {
                    case .bool:
                        if let v = try? cell.decode(Bool.self) {
                            cellRow.append(.bool(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .oid:
                        var buffer = cell.bytes
                        if let u32 = buffer?.readInteger(as: UInt32.self) {
                            cellRow.append(.int(Int64(u32)))
                        } else {
                            cellRow.append(.null)
                        }
                    case .int2:
                        if let v = try? cell.decode(Int16.self) {
                            cellRow.append(.int(Int64(v)))
                        } else if let v = try? cell.decode(Int64.self) {
                            cellRow.append(.int(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .int4:
                        if let v = try? cell.decode(Int32.self) {
                            cellRow.append(.int(Int64(v)))
                        } else if let v = try? cell.decode(Int64.self) {
                            cellRow.append(.int(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .int8:
                        if let v = try? cell.decode(Int64.self) {
                            cellRow.append(.int(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .float4:
                        if let v = try? cell.decode(Float.self) {
                            cellRow.append(.double(Double(v)))
                        } else {
                            cellRow.append(.null)
                        }
                    case .float8:
                        if let v = try? cell.decode(Double.self) {
                            cellRow.append(.double(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .numeric:
                        // Prioritize Decimal decoding to retain exact precision (e.g. monetary / crypto / high-precision values)
                        if let dec = try? cell.decode(Decimal.self) {
                            cellRow.append(.string("\(dec)"))
                        } else if let v = try? cell.decode(Double.self) {
                            cellRow.append(.double(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .json, .jsonb:
                        if let v = try? cell.decode(String.self) {
                            cellRow.append(.json(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .timestamp, .timestamptz:
                        if let date = try? cell.decode(Date.self) {
                            let formatter = DateFormatter()
                            formatter.locale = Locale(identifier: "en_US_POSIX")
                            formatter.timeZone = cell.dataType == .timestamptz ? TimeZone.current : TimeZone(secondsFromGMT: 0)
                            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                            cellRow.append(.date(formatter.string(from: date)))
                        } else if let v = try? cell.decode(String.self) {
                            cellRow.append(.date(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .date:
                        if let date = try? cell.decode(Date.self) {
                            let formatter = DateFormatter()
                            formatter.locale = Locale(identifier: "en_US_POSIX")
                            formatter.timeZone = TimeZone(secondsFromGMT: 0)
                            formatter.dateFormat = "yyyy-MM-dd"
                            cellRow.append(.date(formatter.string(from: date)))
                        } else if let v = try? cell.decode(String.self) {
                            cellRow.append(.date(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .time, .timetz:
                        if let v = try? cell.decode(String.self) {
                            cellRow.append(.date(v))
                        } else {
                            var buffer = cell.bytes
                            if let microseconds = buffer?.readInteger(as: Int64.self) {
                                let totalSeconds = microseconds / 1_000_000
                                let hours = totalSeconds / 3600
                                let mins = (totalSeconds % 3600) / 60
                                let secs = totalSeconds % 60
                                cellRow.append(.date(String(format: "%02d:%02d:%02d", hours, mins, secs)))
                            } else {
                                cellRow.append(.null)
                            }
                        }
                    case .bytea:
                        if let v = try? cell.decode(Data.self) {
                            cellRow.append(.data(v))
                        } else {
                            cellRow.append(.null)
                        }
                    default:
                        // Fallback: try String (PostgreSQL text format handles most types)
                        if let v = try? cell.decode(String.self) {
                            cellRow.append(.string(v))
                        } else {
                            cellRow.append(.null)
                        }
                    }
                }
                cellRows.append(cellRow)
            }
        } catch is CancellationError {
            throw PostgresServiceError.queryFailed("Query cancelled by user.")
        } catch let error as PostgresServiceError {
            throw error
        } catch let psqlError as PSQLError {
            let msg = psqlError.serverInfo?[.message] ?? "\(psqlError)"
            if msg.lowercased().contains("cancel") {
                throw PostgresServiceError.queryFailed("Query cancelled by user.")
            }
            throw PostgresServiceError.queryFailed(msg)
        } catch {
            if error.localizedDescription.lowercased().contains("cancel") {
                throw PostgresServiceError.queryFailed("Query cancelled by user.")
            }
            throw PostgresServiceError.queryFailed(String(describing: error))
        }

        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

        return QueryResult(
            columns: resultColumns,
            rows: cellRows,
            executionTime: seconds,
            rowsAffected: cellRows.count,
            statusMessage: "OK"
        )
    }

    /// Fetches paginated data from a table with an optional WHERE filter clause and optional ORDER BY clause.
    public func fetchTableData(schema: String, table: String, filterClause: String = "", orderBy: String? = nil, limit: Int = 200, offset: Int = 0) async throws -> QueryResult {
        var sql = "SELECT * FROM \(schema.pgQuotedIdentifier).\(table.pgQuotedIdentifier)"
        let trimmed = filterClause.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sql += " WHERE \(trimmed)"
        }
        if let order = orderBy, !order.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sql += " ORDER BY \(order)"
        }
        sql += " LIMIT \(limit) OFFSET \(offset)"
        return try await executeQuery(sql)
    }

    /// Fetches the total row count for a table with an optional WHERE filter clause.
    public func fetchTableRowCount(schema: String, table: String, filterClause: String = "") async throws -> Int64 {
        var sql = "SELECT COUNT(*) AS total FROM \(schema.pgQuotedIdentifier).\(table.pgQuotedIdentifier)"
        let trimmed = filterClause.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sql += " WHERE \(trimmed)"
        }
        let result = try await executeQuery(sql)
        if let firstRow = result.rows.first, let firstCell = firstRow.first {
            if case .int(let count) = firstCell { return count }
            if case .string(let str) = firstCell, let count = Int64(str) { return count }
        }
        return 0
    }
}
