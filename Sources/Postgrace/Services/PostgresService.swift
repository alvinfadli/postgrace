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

                // Build column metadata from the first row
                if resultColumns.isEmpty {
                    for i in 0..<columns.count {
                        resultColumns.append(ResultColumn(
                            name: "col_\(i)",
                            dataTypeOID: 0,
                            dataTypeName: "text"
                        ))
                    }
                }

                var cellRow: [CellValue] = []
                for i in 0..<columns.count {
                    let cell = columns[i]
                    // Decode everything as String for maximum compatibility
                    // PostgreSQL text format can represent all types
                    if let value = try? cell.decode(String.self) {
                        cellRow.append(.string(value))
                    } else if let value = try? cell.decode(Int64.self) {
                        cellRow.append(.int(value))
                    } else if let value = try? cell.decode(Bool.self) {
                        cellRow.append(.bool(value))
                    } else if let value = try? cell.decode(Double.self) {
                        cellRow.append(.double(value))
                    } else {
                        cellRow.append(.null)
                    }
                }
                cellRows.append(cellRow)
            }
        } catch let error as PostgresServiceError {
            throw error
        } catch {
            throw PostgresServiceError.queryFailed(error.localizedDescription)
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
}
