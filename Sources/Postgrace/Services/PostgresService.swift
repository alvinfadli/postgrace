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
    private let logger: Logger

    public init(logger: Logger = Logger(label: "com.postgrace.postgres-service")) {
        self.logger = logger
    }

    /// Connects to the PostgreSQL database using the provided configuration.
    public func connect(config: SavedConnection, password: String) async throws {
        if connection != nil {
            try await disconnect()
        }

        var tlsConfig: PostgresConnection.Configuration.TLS = .disable
        if config.sslMode == .require {
            var nioTLS = TLSConfiguration.makeClientConfiguration()
            nioTLS.certificateVerification = .none
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
        } catch {
            throw PostgresServiceError.connectionFailed(error.localizedDescription)
        }
    }

    /// Disconnects from the current PostgreSQL database.
    public func disconnect() async throws {
        if let conn = connection {
            try await conn.close()
            self.connection = nil
        }
    }

    /// Tests the connection without persisting it.
    public func testConnection(config: SavedConnection, password: String) async throws -> Bool {
        var tlsConfig: PostgresConnection.Configuration.TLS = .disable
        if config.sslMode == .require {
            var nioTLS = TLSConfiguration.makeClientConfiguration()
            nioTLS.certificateVerification = .none
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

            for try await row in rows {
                let columns = row.makeRandomAccess()

                // Build column metadata from the first row's cell descriptors
                if resultColumns.isEmpty {
                    for cell in columns {
                        resultColumns.append(ResultColumn(
                            name: cell.columnName,
                            dataTypeOID: cell.dataType.rawValue,
                            dataTypeName: "\(cell.dataType)"
                        ))
                    }
                }

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
                        if let v = try? cell.decode(Double.self) {
                            cellRow.append(.double(v))
                        } else if let v = try? cell.decode(String.self) {
                            cellRow.append(.string(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .json, .jsonb:
                        if let v = try? cell.decode(String.self) {
                            cellRow.append(.json(v))
                        } else {
                            cellRow.append(.null)
                        }
                    case .timestamp, .timestamptz, .date, .time, .timetz:
                        if let v = try? cell.decode(String.self) {
                            cellRow.append(.date(v))
                        } else {
                            cellRow.append(.null)
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
        } catch let error as PostgresServiceError {
            throw error
        } catch let psqlError as PSQLError {
            let msg = psqlError.serverInfo?[.message] ?? "\(psqlError)"
            throw PostgresServiceError.queryFailed(msg)
        } catch {
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

    /// Fetches paginated data from a table.
    public func fetchTableData(schema: String, table: String, limit: Int = 200, offset: Int = 0) async throws -> QueryResult {
        let sql = "SELECT * FROM \"\(schema)\".\"\(table)\" LIMIT \(limit) OFFSET \(offset)"
        return try await executeQuery(sql)
    }

    /// Fetches the total row count for a table.
    public func fetchTableRowCount(schema: String, table: String) async throws -> Int64 {
        let sql = "SELECT COUNT(*) AS total FROM \"\(schema)\".\"\(table)\""
        let result = try await executeQuery(sql)
        if let firstRow = result.rows.first, let firstCell = firstRow.first {
            if case .int(let count) = firstCell { return count }
            if case .string(let str) = firstCell, let count = Int64(str) { return count }
        }
        return 0
    }
}
