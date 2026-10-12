import Foundation
import PostgresNIO
import Logging
import NIOCore
import NIOPosix
import NIOSSL

/// Concrete driver managing connections and query execution for PostgreSQL databases.
public actor PostgresDriver: DatabaseDriverProtocol {
    public let engine: DatabaseEngine = .postgresql
    private var connection: PostgresConnection?
    private var currentConfig: SavedConnection?
    private var currentPassword: String?
    private var backendPID: Int32?
    private let logger: Logger

    public private(set) var lastConnectionError: String?

    public init(logger: Logger = Logger(label: "com.postgrace.postgres-driver")) {
        self.logger = logger
    }

    public var isConnected: Bool {
        connection != nil
    }

    public var currentDatabase: String? {
        currentConfig?.database
    }

    public var activeConfig: SavedConnection? {
        currentConfig
    }

    public var activePassword: String? {
        currentPassword
    }

    // MARK: - Connection Lifecycle

    /// Constructs Postgres NIO TLS Configuration, respecting SSL mode and custom CA certificates.
    private func makeTLSConfiguration(for config: SavedConnection) throws -> PostgresConnection.Configuration.TLS {
        guard config.sslMode.isTLSRequired else {
            return .disable
        }
        var nioTLS = TLSConfiguration.makeClientConfiguration()
        switch config.sslMode {
        case .verifyFull:
            nioTLS.certificateVerification = .fullVerification
        case .verifyCA:
            nioTLS.certificateVerification = .noHostnameVerification
        default:
            nioTLS.certificateVerification = .none
        }

        // Custom Root CA certificate support
        if let caPath = config.caCertPath?.trimmingCharacters(in: .whitespacesAndNewlines), !caPath.isEmpty {
            if FileManager.default.fileExists(atPath: caPath) {
                do {
                    let certs = try NIOSSLCertificate.fromPEMFile(caPath)
                    if !certs.isEmpty {
                        nioTLS.trustRoots = .certificates(certs)
                    }
                } catch {
                    logger.warning("Failed to load custom CA certificate from \(caPath): \(error)")
                }
            } else {
                logger.warning("Custom CA certificate file not found: \(caPath)")
            }
        }

        return try .require(.init(configuration: nioTLS))
    }

    public func connect(config: SavedConnection, password: String) async throws {
        if connection != nil {
            try await disconnect()
        }

        let tlsConfig = try makeTLSConfiguration(for: config)

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
            let reason = PostgresDriver.formatError(error, host: config.host, port: config.port)
            self.lastConnectionError = reason
            throw DatabaseServiceError.connectionFailed(reason)
        }
    }

    public func switchDatabase(to newDatabase: String) async throws {
        guard let config = currentConfig, let password = currentPassword else {
            throw DatabaseServiceError.notConnected
        }
        var updatedConfig = config
        updatedConfig.database = newDatabase
        try await connect(config: updatedConfig, password: password)
    }

    public func disconnect() async throws {
        let conn = self.connection
        self.connection = nil
        self.currentConfig = nil
        self.currentPassword = nil
        self.backendPID = nil
        if let conn {
            try? await conn.close()
        }
    }

    public func cancelRunningQuery() async {
        guard let pid = backendPID, let config = currentConfig else { return }
        let pwd = currentPassword ?? ""
        let tlsConfig = (try? makeTLSConfiguration(for: config)) ?? .disable

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

    public func testConnection(config: SavedConnection, password: String) async throws -> Bool {
        let tlsConfig = try makeTLSConfiguration(for: config)

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
            let reason = PostgresDriver.formatError(error, host: config.host, port: config.port)
            self.lastConnectionError = reason
            return false
        }
    }

    // MARK: - Query Execution

    public func executeQuery(_ sql: String) async throws -> QueryResult {
        let stmts = SQLScriptSplitter.split(sql)
        if stmts.count > 1 {
            var lastResult: QueryResult?
            var totalTime: Double = 0
            for stmt in stmts {
                let res = try await executeSingleQuery(stmt)
                totalTime += res.executionTime
                lastResult = res
            }
            if let last = lastResult {
                return QueryResult(
                    columns: last.columns,
                    rows: last.rows,
                    executionTime: totalTime,
                    rowsAffected: last.rowsAffected,
                    statusMessage: last.statusMessage
                )
            }
        }
        return try await executeSingleQuery(sql)
    }

    private func executeSingleQuery(_ sql: String) async throws -> QueryResult {
        guard let conn = connection else {
            throw DatabaseServiceError.notConnected
        }

        let start = ContinuousClock.now
        var resultColumns: [ResultColumn] = []
        var cellRows: [[CellValue]] = []

        do {
            let rows = try await conn.query(PostgresQuery(stringLiteral: sql), logger: logger)

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
                    guard cell.bytes != nil else {
                        cellRow.append(.null)
                        continue
                    }

                    switch cell.dataType {
                    case .bool:
                        if let v = try? cell.decode(Bool.self) { cellRow.append(.bool(v)) } else { cellRow.append(.null) }
                    case .oid:
                        var buffer = cell.bytes
                        if let u32 = buffer?.readInteger(as: UInt32.self) { cellRow.append(.int(Int64(u32))) } else { cellRow.append(.null) }
                    case .int2:
                        if let v = try? cell.decode(Int16.self) { cellRow.append(.int(Int64(v))) }
                        else if let v = try? cell.decode(Int64.self) { cellRow.append(.int(v)) }
                        else { cellRow.append(.null) }
                    case .int4:
                        if let v = try? cell.decode(Int32.self) { cellRow.append(.int(Int64(v))) }
                        else if let v = try? cell.decode(Int64.self) { cellRow.append(.int(v)) }
                        else { cellRow.append(.null) }
                    case .int8:
                        if let v = try? cell.decode(Int64.self) { cellRow.append(.int(v)) } else { cellRow.append(.null) }
                    case .float4:
                        if let v = try? cell.decode(Float.self) { cellRow.append(.double(Double(v))) } else { cellRow.append(.null) }
                    case .float8:
                        if let v = try? cell.decode(Double.self) { cellRow.append(.double(v)) } else { cellRow.append(.null) }
                    case .numeric:
                        if let dec = try? cell.decode(Decimal.self) { cellRow.append(.string("\(dec)")) }
                        else if let v = try? cell.decode(Double.self) { cellRow.append(.double(v)) }
                        else { cellRow.append(.null) }
                    case .json, .jsonb:
                        if let v = try? cell.decode(String.self) { cellRow.append(.json(v)) } else { cellRow.append(.null) }
                    case .timestamp, .timestamptz:
                        if let date = try? cell.decode(Date.self) {
                            let formatted = PostgresDateFormatters.formatTimestamp(date, isLocal: cell.dataType == .timestamptz)
                            cellRow.append(.date(formatted))
                        } else if let v = try? cell.decode(String.self) {
                            cellRow.append(.date(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .date:
                        if let date = try? cell.decode(Date.self) {
                            let formatted = PostgresDateFormatters.formatDate(date)
                            cellRow.append(.date(formatted))
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
                        if let v = try? cell.decode(Data.self) { cellRow.append(.data(v)) } else { cellRow.append(.null) }
                    default:
                        if let v = try? cell.decode(String.self) { cellRow.append(.string(v)) } else { cellRow.append(.null) }
                    }
                }
                cellRows.append(cellRow)
            }
        } catch is CancellationError {
            throw DatabaseServiceError.queryFailed("Query cancelled by user.")
        } catch let error as DatabaseServiceError {
            throw error
        } catch {
            let msg = PostgresDriver.formatError(error, host: currentConfig?.host, port: currentConfig?.port)
            if msg.lowercased().contains("cancel") {
                throw DatabaseServiceError.queryFailed("Query cancelled by user.")
            }
            throw DatabaseServiceError.queryFailed(msg)
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

    public func fetchTableData(
        schema: String,
        table: String,
        filterClause: String = "",
        orderBy: String? = nil,
        limit: Int = 200,
        offset: Int = 0
    ) async throws -> QueryResult {
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

    public func executeRawStatement(_ sql: String) async throws {
        guard let conn = connection else {
            throw DatabaseServiceError.notConnected
        }
        do {
            _ = try await conn.query(PostgresQuery(stringLiteral: sql), logger: logger)
        } catch {
            let msg = PostgresDriver.formatError(error, host: currentConfig?.host, port: currentConfig?.port)
            throw DatabaseServiceError.queryFailed(msg)
        }
    }

    public func streamQuery(
        _ sql: String,
        onRow: @escaping ([ResultColumn], [CellValue]) async throws -> Void
    ) async throws -> (columns: [ResultColumn], rowCount: Int64, executionTime: Double) {
        guard let conn = connection else {
            throw DatabaseServiceError.notConnected
        }

        let start = ContinuousClock.now
        var resultColumns: [ResultColumn] = []
        var totalRowCount: Int64 = 0

        do {
            let rows = try await conn.query(PostgresQuery(stringLiteral: sql), logger: logger)

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
                    guard cell.bytes != nil else {
                        cellRow.append(.null)
                        continue
                    }

                    switch cell.dataType {
                    case .bool:
                        if let v = try? cell.decode(Bool.self) { cellRow.append(.bool(v)) } else { cellRow.append(.null) }
                    case .oid:
                        var buffer = cell.bytes
                        if let u32 = buffer?.readInteger(as: UInt32.self) { cellRow.append(.int(Int64(u32))) } else { cellRow.append(.null) }
                    case .int2:
                        if let v = try? cell.decode(Int16.self) { cellRow.append(.int(Int64(v))) } else { cellRow.append(.null) }
                    case .int4:
                        if let v = try? cell.decode(Int32.self) { cellRow.append(.int(Int64(v))) } else { cellRow.append(.null) }
                    case .int8:
                        if let v = try? cell.decode(Int64.self) { cellRow.append(.int(v)) } else { cellRow.append(.null) }
                    case .float4:
                        if let v = try? cell.decode(Float.self) { cellRow.append(.double(Double(v))) } else { cellRow.append(.null) }
                    case .float8:
                        if let v = try? cell.decode(Double.self) { cellRow.append(.double(v)) } else { cellRow.append(.null) }
                    case .numeric:
                        if let dec = try? cell.decode(Decimal.self) { cellRow.append(.string("\(dec)")) }
                        else if let v = try? cell.decode(Double.self) { cellRow.append(.double(v)) }
                        else { cellRow.append(.null) }
                    case .json, .jsonb:
                        if let v = try? cell.decode(String.self) { cellRow.append(.json(v)) } else { cellRow.append(.null) }
                    case .timestamp, .timestamptz:
                        if let date = try? cell.decode(Date.self) {
                            let formatted = PostgresDateFormatters.formatTimestamp(date, isLocal: cell.dataType == .timestamptz)
                            cellRow.append(.date(formatted))
                        } else if let v = try? cell.decode(String.self) {
                            cellRow.append(.date(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .date:
                        if let date = try? cell.decode(Date.self) {
                            let formatted = PostgresDateFormatters.formatDate(date)
                            cellRow.append(.date(formatted))
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
                        if let v = try? cell.decode(Data.self) { cellRow.append(.data(v)) } else { cellRow.append(.null) }
                    default:
                        if let v = try? cell.decode(String.self) { cellRow.append(.string(v)) } else { cellRow.append(.null) }
                    }
                }

                try await onRow(resultColumns, cellRow)
                totalRowCount += 1
            }
        } catch is CancellationError {
            throw DatabaseServiceError.queryFailed("Query cancelled by user.")
        } catch let error as DatabaseServiceError {
            throw error
        } catch {
            let msg = PostgresDriver.formatError(error, host: currentConfig?.host, port: currentConfig?.port)
            if msg.lowercased().contains("cancel") {
                throw DatabaseServiceError.queryFailed("Query cancelled by user.")
            }
            throw DatabaseServiceError.queryFailed(msg)
        }

        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
        return (resultColumns, totalRowCount, seconds)
    }

    public func executeBatchInsert(
        schema: String,
        table: String,
        columns: [String],
        rows: [[String]],
        treatEmptyAsNull: Bool = true
    ) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        let colsList = columns.map { $0.pgQuotedIdentifier }.joined(separator: ", ")
        let chunkSize = 250
        var totalInserted = 0

        for i in stride(from: 0, to: rows.count, by: chunkSize) {
            let end = min(i + chunkSize, rows.count)
            let chunk = rows[i..<end]

            var valueClauses: [String] = []
            for row in chunk {
                let rowVals = row.map { val -> String in
                    if val.isEmpty {
                        return treatEmptyAsNull ? "NULL" : "''"
                    }
                    return "'\(val.pgEscapedLiteral)'"
                }.joined(separator: ", ")
                valueClauses.append("(\(rowVals))")
            }

            let sql = "INSERT INTO \(schema.pgQuotedIdentifier).\(table.pgQuotedIdentifier) (\(colsList)) VALUES \(valueClauses.joined(separator: ", "));"
            try await executeRawStatement(sql)
            totalInserted += chunk.count
        }

        return totalInserted
    }

    // MARK: - Error Diagnostics & Formatting

    public static func formatError(_ error: Error, host: String? = nil, port: Int? = nil) -> String {
        if let psqlError = error as? PSQLError {
            var serverParts: [String] = []
            if let msg = psqlError.serverInfo?[.message], !msg.isEmpty {
                serverParts.append(msg)
            }
            if let detail = psqlError.serverInfo?[.detail], !detail.isEmpty {
                serverParts.append("Detail: \(detail)")
            }
            if let hint = psqlError.serverInfo?[.hint], !hint.isEmpty {
                serverParts.append("Hint: \(hint)")
            }
            if !serverParts.isEmpty {
                return serverParts.joined(separator: " — ")
            }

            if let underlying = psqlError.underlying {
                return extractReadableUnderlyingError(underlying, host: host, port: port)
            }

            return humanReadableCodeDescription(psqlError.code, host: host, port: port)
        }

        if let serviceErr = error as? DatabaseServiceError {
            return serviceErr.localizedDescription
        }

        let nsError = error as NSError
        if nsError.domain == "PostgresNIO.PSQLError" {
            let hostPort = (host != nil && port != nil) ? " on \(host!):\(port!)" : ""
            return "Connection failed\(hostPort). Verify that PostgreSQL server is running and accepting connections."
        }

        let desc = error.localizedDescription
        if desc.contains("The operation couldn’t be completed") || desc.contains("The operation couldn't be completed") || desc.contains("error 1") {
            if let reason = nsError.localizedFailureReason, !reason.isEmpty {
                return reason
            }
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                return extractReadableUnderlyingError(underlying, host: host, port: port)
            }
            let hostPort = (host != nil && port != nil) ? " on \(host!):\(port!)" : ""
            return "Connection failed\(hostPort). Verify server address, port, and credentials."
        }
        return desc
    }

    private static func extractReadableUnderlyingError(_ error: Error, host: String? = nil, port: Int? = nil) -> String {
        let hostPort = (host != nil && port != nil) ? " (\(host!):\(port!))" : ""
        let desc = String(describing: error)
        let lower = desc.lowercased()

        if lower.contains("connection refused") || lower.contains("connectionrefused") || lower.contains("errno: 61") {
            return "Connection refused\(hostPort). Verify that PostgreSQL is running and accepting connections."
        }
        if lower.contains("timed out") || lower.contains("etimedout") || lower.contains("errno: 60") {
            return "Connection timed out\(hostPort). Check network connectivity and firewall settings."
        }
        if lower.contains("no route to host") || lower.contains("errno: 65") || lower.contains("network is unreachable") {
            return "Host unreachable\(hostPort). Verify host address and network connection."
        }
        if lower.contains("nodename nor servname provided") || lower.contains("not known") {
            return "Host not found\(hostPort). Could not resolve hostname."
        }
        if lower.contains("ssl") || lower.contains("handshake") || lower.contains("certificate") {
            return "SSL/TLS negotiation failed: \(desc). Try setting SSL Mode to Disable or Require."
        }

        let loc = error.localizedDescription
        if !loc.contains("The operation couldn’t be completed") && !loc.contains("error 1") && !loc.isEmpty {
            return loc
        }

        return desc
    }

    private static func humanReadableCodeDescription(_ code: PSQLError.Code, host: String? = nil, port: Int? = nil) -> String {
        let hostPort = (host != nil && port != nil) ? " on \(host!):\(port!)" : ""
        switch code {
        case .connectionError:
            return "Failed to establish TCP connection\(hostPort). Check that PostgreSQL is running and port is correct."
        case .serverClosedConnection:
            return "PostgreSQL server closed the connection unexpectedly."
        case .authMechanismRequiresPassword:
            return "Authentication requires a password, but none was provided."
        case .saslError:
            return "Password authentication failed (SCRAM/SASL verification failed. Please check username and password)."
        case .unsupportedAuthMechanism:
            return "PostgreSQL requested an authentication mechanism not supported by this client."
        case .sslUnsupported:
            return "PostgreSQL server does not support SSL/TLS connections. Set SSL Mode to 'Disable' in connection options."
        case .failedToAddSSLHandler:
            return "Failed to establish secure TLS session. Verify SSL Mode or certificate."
        case .receivedUnencryptedDataAfterSSLRequest:
            return "Received unencrypted response after requesting SSL connection."
        case .server:
            return "PostgreSQL server error."
        case .queryCancelled:
            return "Query was cancelled by user."
        case .clientClosedConnection:
            return "Connection closed by client."
        default:
            return "PostgreSQL error: \(code.description)"
        }
    }
}

/// High-performance thread-safe cached date formatters avoiding thousands of ICU allocations in row loops.
private final class PostgresDateFormatters: @unchecked Sendable {
    private static let timestampUTC: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let timestampLocal: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let dateUTC: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let lock = NSLock()

    static func formatTimestamp(_ date: Date, isLocal: Bool) -> String {
        lock.lock()
        defer { lock.unlock() }
        return (isLocal ? timestampLocal : timestampUTC).string(from: date)
    }

    static func formatDate(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return dateUTC.string(from: date)
    }
}
