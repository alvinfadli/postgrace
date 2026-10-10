import Foundation
import MySQLNIO
import NIOCore
import NIOPosix
import NIOSSL
import Logging

/// Concrete driver managing connections and query execution for MySQL and MariaDB databases.
public actor MySQLDriver: DatabaseDriverProtocol {
    public let engine: DatabaseEngine
    private var connection: MySQLConnection?
    private var currentConfig: SavedConnection?
    private var currentPassword: String?
    private var connectionID: Int64?
    private let logger: Logger

    public private(set) var lastConnectionError: String?

    public init(engine: DatabaseEngine = .mysql, logger: Logger = Logger(label: "com.postgrace.mysql-driver")) {
        self.engine = engine
        self.logger = logger
    }

    public var isConnected: Bool {
        if let conn = connection {
            return !conn.isClosed
        }
        return false
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

    /// Constructs MySQL NIO TLS Configuration, respecting SSL mode and custom CA certificates.
    private func makeTLSConfiguration(for config: SavedConnection) -> TLSConfiguration? {
        guard config.sslMode.isTLSRequired else {
            return nil
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

        return nioTLS
    }

    public func connect(config: SavedConnection, password: String) async throws {
        if isConnected {
            try await disconnect()
        }

        let eventLoop = MultiThreadedEventLoopGroup.singleton.any()
        let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = config.port

        let socketAddress: SocketAddress
        do {
            socketAddress = try SocketAddress.makeAddressResolvingHost(host, port: port)
        } catch {
            let reason = MySQLDriver.formatError(error, host: host, port: port)
            self.lastConnectionError = reason
            throw DatabaseServiceError.connectionFailed(reason)
        }

        let tlsConfig = makeTLSConfiguration(for: config)

        do {
            let conn = try await MySQLConnection.connect(
                to: socketAddress,
                username: config.username,
                database: config.database,
                password: password.isEmpty ? nil : password,
                tlsConfiguration: tlsConfig,
                serverHostname: host,
                logger: logger,
                on: eventLoop
            ).get()

            self.connection = conn
            self.currentConfig = config
            self.currentPassword = password

            // Introspect connection / thread ID for KILL QUERY cancellation
            do {
                let rows = try await conn.simpleQuery("SELECT CONNECTION_ID() AS cid;").get()
                if let first = rows.first, let col = first.column("cid"), let cid = col.int64 {
                    self.connectionID = cid
                }
            } catch {
                logger.warning("Could not determine MySQL CONNECTION_ID(): \(error)")
            }
        } catch {
            let reason = MySQLDriver.formatError(error, host: host, port: port)
            self.lastConnectionError = reason
            throw DatabaseServiceError.connectionFailed(reason)
        }
    }

    public func disconnect() async throws {
        let conn = self.connection
        self.connection = nil
        self.currentConfig = nil
        self.currentPassword = nil
        self.connectionID = nil
        if let conn {
            _ = try? await conn.close().get()
        }
    }

    public func switchDatabase(to newDatabase: String) async throws {
        guard let conn = connection, !conn.isClosed, var config = currentConfig else {
            throw DatabaseServiceError.notConnected
        }
        let cleanName = newDatabase.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoted = cleanName.mysqlQuotedIdentifier
        do {
            _ = try await conn.simpleQuery("USE \(quoted);").get()
            config.database = cleanName
            self.currentConfig = config
        } catch {
            let msg = MySQLDriver.formatError(error, host: config.host, port: config.port)
            throw DatabaseServiceError.queryFailed(msg)
        }
    }

    public func testConnection(config: SavedConnection, password: String) async throws -> Bool {
        let eventLoop = MultiThreadedEventLoopGroup.singleton.any()
        let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = config.port

        do {
            let socketAddress = try SocketAddress.makeAddressResolvingHost(host, port: port)
            let tlsConfig = makeTLSConfiguration(for: config)

            let tempConn = try await MySQLConnection.connect(
                to: socketAddress,
                username: config.username,
                database: config.database,
                password: password.isEmpty ? nil : password,
                tlsConfiguration: tlsConfig,
                serverHostname: host,
                logger: logger,
                on: eventLoop
            ).get()

            _ = try await tempConn.simpleQuery("SELECT 1;").get()
            _ = try? await tempConn.close().get()
            return true
        } catch {
            let reason = MySQLDriver.formatError(error, host: host, port: port)
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
        guard let conn = connection, !conn.isClosed else {
            throw DatabaseServiceError.notConnected
        }

        let start = ContinuousClock.now

        do {
            let cmd = MySQLDirectQueryCommand(sql: sql)
            try await conn.send(cmd, logger: logger).get()

            let resultColumns = cmd.columns.map { col in
                ResultColumn(
                    name: col.name,
                    dataTypeOID: UInt32(col.columnType.rawValue),
                    dataTypeName: col.columnType.name
                )
            }

            var cellRows: [[CellValue]] = []
            cellRows.reserveCapacity(cmd.rows.count)

            for row in cmd.rows {
                var cellRow: [CellValue] = []
                cellRow.reserveCapacity(row.columnDefinitions.count)
                for (colDef, byteBuf) in zip(row.columnDefinitions, row.values) {
                    let cellVal = MySQLDriver.mapToCellValue(
                        type: colDef.columnType,
                        format: row.format,
                        buffer: byteBuf,
                        isUnsigned: colDef.flags.contains(.COLUMN_UNSIGNED)
                    )
                    cellRow.append(cellVal)
                }
                cellRows.append(cellRow)
            }

            let elapsed = ContinuousClock.now - start
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

            let affected = cmd.affectedRows > 0 ? Int(cmd.affectedRows) : cellRows.count

            return QueryResult(
                columns: resultColumns,
                rows: cellRows,
                executionTime: seconds,
                rowsAffected: affected,
                statusMessage: "OK"
            )
        } catch is CancellationError {
            throw DatabaseServiceError.queryFailed("Query cancelled by user.")
        } catch let error as DatabaseServiceError {
            throw error
        } catch {
            let msg = MySQLDriver.formatError(error, host: currentConfig?.host, port: currentConfig?.port)
            if msg.lowercased().contains("cancel") {
                throw DatabaseServiceError.queryFailed("Query cancelled by user.")
            }
            throw DatabaseServiceError.queryFailed(msg)
        }
    }

    public func fetchTableData(
        schema: String,
        table: String,
        filterClause: String = "",
        orderBy: String? = nil,
        limit: Int = 200,
        offset: Int = 0
    ) async throws -> QueryResult {
        let schemaQuoted = schema.mysqlQuotedIdentifier
        let tableQuoted = table.mysqlQuotedIdentifier
        var sql = "SELECT * FROM \(schemaQuoted).\(tableQuoted)"
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
        let schemaQuoted = schema.mysqlQuotedIdentifier
        let tableQuoted = table.mysqlQuotedIdentifier
        var sql = "SELECT COUNT(*) AS total FROM \(schemaQuoted).\(tableQuoted)"
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
        guard let conn = connection, !conn.isClosed else {
            throw DatabaseServiceError.notConnected
        }
        do {
            _ = try await conn.simpleQuery(sql).get()
        } catch {
            let msg = MySQLDriver.formatError(error, host: currentConfig?.host, port: currentConfig?.port)
            throw DatabaseServiceError.queryFailed(msg)
        }
    }

    public func streamQuery(
        _ sql: String,
        onRow: @escaping ([ResultColumn], [CellValue]) async throws -> Void
    ) async throws -> (columns: [ResultColumn], rowCount: Int64, executionTime: Double) {
        guard let conn = connection, !conn.isClosed else {
            throw DatabaseServiceError.notConnected
        }

        let start = ContinuousClock.now
        var totalRowCount: Int64 = 0
        var cachedColumns: [ResultColumn] = []

        do {
            let cmd = MySQLDirectQueryCommand(sql: sql) { row in
                if cachedColumns.isEmpty {
                    cachedColumns = row.columnDefinitions.map { col in
                        ResultColumn(
                            name: col.name,
                            dataTypeOID: UInt32(col.columnType.rawValue),
                            dataTypeName: col.columnType.name
                        )
                    }
                }
                var cellRow: [CellValue] = []
                for (colDef, byteBuf) in zip(row.columnDefinitions, row.values) {
                    let cellVal = MySQLDriver.mapToCellValue(
                        type: colDef.columnType,
                        format: row.format,
                        buffer: byteBuf,
                        isUnsigned: colDef.flags.contains(.COLUMN_UNSIGNED)
                    )
                    cellRow.append(cellVal)
                }
                Task {
                    try? await onRow(cachedColumns, cellRow)
                }
                totalRowCount += 1
            }

            try await conn.send(cmd, logger: logger).get()

            if cachedColumns.isEmpty {
                cachedColumns = cmd.columns.map { col in
                    ResultColumn(
                        name: col.name,
                        dataTypeOID: UInt32(col.columnType.rawValue),
                        dataTypeName: col.columnType.name
                    )
                }
            }

            let elapsed = ContinuousClock.now - start
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
            return (cachedColumns, totalRowCount, seconds)
        } catch is CancellationError {
            throw DatabaseServiceError.queryFailed("Query cancelled by user.")
        } catch {
            let msg = MySQLDriver.formatError(error, host: currentConfig?.host, port: currentConfig?.port)
            throw DatabaseServiceError.queryFailed(msg)
        }
    }

    public func executeBatchInsert(
        schema: String,
        table: String,
        columns: [String],
        rows: [[String]],
        treatEmptyAsNull: Bool = true
    ) async throws -> Int {
        guard !rows.isEmpty else { return 0 }
        let colsList = columns.map { $0.mysqlQuotedIdentifier }.joined(separator: ", ")
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
                    return "'\(val.mysqlEscapedLiteral)'"
                }.joined(separator: ", ")
                valueClauses.append("(\(rowVals))")
            }

            let sql = "INSERT INTO \(schema.mysqlQuotedIdentifier).\(table.mysqlQuotedIdentifier) (\(colsList)) VALUES \(valueClauses.joined(separator: ", "));"
            try await executeRawStatement(sql)
            totalInserted += chunk.count
        }

        return totalInserted
    }

    public func cancelRunningQuery() async {
        guard let cid = connectionID, let config = currentConfig else { return }
        let pwd = currentPassword ?? ""
        let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = config.port

        let eventLoop = MultiThreadedEventLoopGroup.singleton.any()

        do {
            let socketAddress = try SocketAddress.makeAddressResolvingHost(host, port: port)
            let tlsConfig = makeTLSConfiguration(for: config)

            let killConn = try await MySQLConnection.connect(
                to: socketAddress,
                username: config.username,
                database: config.database,
                password: pwd.isEmpty ? nil : pwd,
                tlsConfiguration: tlsConfig,
                serverHostname: host,
                logger: logger,
                on: eventLoop
            ).get()

            _ = try await killConn.simpleQuery("KILL QUERY \(cid);").get()
            _ = try? await killConn.close().get()
            logger.info("Successfully cancelled MySQL query for connection ID \(cid)")
        } catch {
            logger.warning("Failed to cancel MySQL query for connection ID \(cid): \(error)")
        }
    }

    // MARK: - Value & Error Mapping

    public static func mapToCellValue(
        type: MySQLProtocol.DataType,
        format: MySQLData.Format,
        buffer: ByteBuffer?,
        isUnsigned: Bool
    ) -> CellValue {
        guard let buf = buffer else {
            return .null
        }

        let data = MySQLData(type: type, format: format, buffer: buf, isUnsigned: isUnsigned)

        switch type {
        case .null:
            return .null

        case .tiny:
            // Check boolean or small integer
            if let b = data.bool, isUnsigned {
                return .bool(b)
            }
            if let i = data.int64 {
                return .int(i)
            }
            return .null

        case .short, .long, .longlong, .int24, .year:
            if let i = data.int64 {
                return .int(i)
            }
            return .null

        case .bit:
            if let b = data.bool {
                return .bool(b)
            }
            if let i = data.int64 {
                return .int(i)
            }
            return .null

        case .float, .double:
            if let d = data.double {
                return .double(d)
            }
            return .null

        case .decimal, .newdecimal:
            if let s = data.string {
                return .string(s)
            }
            return .null

        case .json:
            if let s = data.string {
                return .json(s)
            }
            return .null

        case .date, .newdate, .datetime, .datetime2, .timestamp, .timestamp2, .time, .time2:
            if let s = data.string {
                return .date(s)
            }
            return .null

        case .blob, .tinyBlob, .mediumBlob, .longBlob, .geometry:
            if var copyBuf = data.buffer,
               let bytes = copyBuf.readBytes(length: copyBuf.readableBytes) {
                return .data(Data(bytes))
            }
            return .null

        default:
            if let s = data.string {
                return .string(s)
            }
            return .null
        }
    }

    public static func formatError(_ error: Error, host: String? = nil, port: Int? = nil) -> String {
        if let mysqlErr = error as? MySQLError {
            switch mysqlErr {
            case .server(let errPacket):
                return "MySQL Error [\(errPacket.errorCode.rawValue)]: \(errPacket.errorMessage)"
            case .duplicateEntry(let msg):
                return "Duplicate entry: \(msg)"
            case .invalidSyntax(let msg):
                return "Syntax error: \(msg)"
            case .secureConnectionRequired:
                return "A secure TLS connection is required by the MySQL server. Set SSL Mode to Require."
            case .closed:
                return "MySQL connection was closed by the server."
            default:
                return mysqlErr.message
            }
        }

        let hostPort = (host != nil && port != nil) ? " (\(host!):\(port!))" : ""
        let desc = String(describing: error)
        let lower = desc.lowercased()

        if lower.contains("connection refused") || lower.contains("errno: 61") {
            return "Connection refused\(hostPort). Verify that MySQL/MariaDB server is running and accepting connections on port \(port ?? 3306)."
        }
        if lower.contains("timed out") || lower.contains("errno: 60") {
            return "Connection timed out\(hostPort). Check network connectivity and firewall rules."
        }
        if lower.contains("access denied") || lower.contains("1045") {
            return "Access denied for user. Please check your username and password."
        }
        if lower.contains("unknown database") || lower.contains("1049") {
            return "Unknown database. Please verify the default database name."
        }

        let loc = error.localizedDescription
        if !loc.contains("The operation couldn’t be completed") && !loc.isEmpty {
            return loc
        }

        return desc
    }
}

// MARK: - Direct Query Command

final class MySQLDirectQueryCommand: MySQLCommand, @unchecked Sendable {
    let sql: String
    enum State {
        case ready
        case columns(count: UInt64)
        case rows
        case done
    }
    var state: State
    var columns: [MySQLProtocol.ColumnDefinition41] = []
    var rows: [MySQLRow] = []
    var affectedRows: UInt64 = 0
    let onRow: ((MySQLRow) -> Void)?

    init(sql: String, onRow: ((MySQLRow) -> Void)? = nil) {
        self.sql = sql
        self.state = .ready
        self.onRow = onRow
    }

    func handle(packet: inout MySQLPacket, capabilities: MySQLProtocol.CapabilityFlags) throws -> MySQLCommandState {
        guard !packet.isError else {
            self.state = .done
            let err = try packet.decode(MySQLProtocol.ERR_Packet.self, capabilities: capabilities)
            switch err.errorCode {
            case .DUP_ENTRY:
                throw MySQLError.duplicateEntry(err.errorMessage)
            case .PARSE_ERROR:
                throw MySQLError.invalidSyntax(err.errorMessage)
            default:
                throw MySQLError.server(err)
            }
        }

        switch self.state {
        case .ready:
            if packet.isOK {
                self.state = .done
                let okPacket = try packet.decode(MySQLProtocol.OK_Packet.self, capabilities: capabilities)
                self.affectedRows = okPacket.affectedRows
                return MySQLCommandState(done: true)
            } else {
                let res = try packet.decode(MySQLProtocol.COM_QUERY_Response.self, capabilities: capabilities)
                self.state = .columns(count: res.columnCount)
                return MySQLCommandState()
            }

        case .columns(let total):
            let col = try packet.decode(MySQLProtocol.ColumnDefinition41.self, capabilities: capabilities)
            self.columns.append(col)
            if self.columns.count == numericCast(total) {
                self.state = .rows
            }
            return MySQLCommandState()

        case .rows:
            guard !packet.isEOF else {
                self.state = .done
                return MySQLCommandState(done: true)
            }
            let data = try MySQLProtocol.TextResultSetRow.decode(from: &packet, columnCount: self.columns.count)
            let row = MySQLRow(
                format: .text,
                columnDefinitions: self.columns,
                values: data.values
            )
            self.rows.append(row)
            self.onRow?(row)
            return MySQLCommandState()

        case .done:
            throw MySQLError.protocolError
        }
    }

    func activate(capabilities: MySQLProtocol.CapabilityFlags) throws -> MySQLCommandState {
        let packet = try MySQLPacket.encode(MySQLProtocol.COM_QUERY(query: self.sql), capabilities: capabilities)
        return MySQLCommandState(response: [packet])
    }
}
