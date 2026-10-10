import Foundation
import Logging
import PostgresNIO
import MySQLNIO

/// Errors that can occur during database service operations.
public enum DatabaseServiceError: Error, LocalizedError, Equatable {
    case notConnected
    case connectionFailed(String)
    case queryFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to the database."
        case .connectionFailed(let reason):
            if reason.hasPrefix("Connection failed:") {
                return reason
            }
            return "Connection failed: \(reason)"
        case .queryFailed(let reason):
            return "Query failed: \(reason)"
        }
    }
}

/// Backwards-compatible alias for existing codebase and tests.
public typealias PostgresServiceError = DatabaseServiceError

/// Unified service managing database driver sessions (PostgreSQL, MySQL, MariaDB) and query execution.
public actor DatabaseService {
    private var activeDriver: (any DatabaseDriverProtocol)?
    private let logger: Logger

    /// The most recent connection error message, if any.
    public private(set) var lastConnectionError: String?

    public init(logger: Logger = Logger(label: "com.postgrace.database-service")) {
        self.logger = logger
    }

    #if DEBUG
    public func setActiveDriverForTesting(_ driver: (any DatabaseDriverProtocol)?) {
        self.activeDriver = driver
    }
    #endif

    /// The name of the active database, if connected.
    public var currentDatabase: String? {
        get async {
            await activeDriver?.currentDatabase
        }
    }

    /// The active connection configuration, if connected.
    public var activeConfig: SavedConnection? {
        get async {
            await activeDriver?.activeConfig
        }
    }

    /// The active connection password, if connected.
    public var activePassword: String? {
        get async {
            await activeDriver?.activePassword
        }
    }

    /// Checks if the service is currently connected to a database.
    public var isConnected: Bool {
        get async {
            await activeDriver?.isConnected ?? false
        }
    }

    /// Connects to a database using the provided configuration and engine.
    public func connect(config: SavedConnection, password: String) async throws {
        if let driver = activeDriver {
            try? await driver.disconnect()
            self.activeDriver = nil
        }

        self.lastConnectionError = nil

        let driver: any DatabaseDriverProtocol
        switch config.engine {
        case .postgresql:
            driver = PostgresDriver(logger: logger)
        case .mysql, .mariadb:
            driver = MySQLDriver(engine: config.engine, logger: logger)
        }

        do {
            try await driver.connect(config: config, password: password)
            self.activeDriver = driver
        } catch {
            let reason = await driver.lastConnectionError ?? DatabaseService.formatError(error, host: config.host, port: config.port)
            self.lastConnectionError = reason
            throw DatabaseServiceError.connectionFailed(reason)
        }
    }

    /// Switches the active connection to another database on the same host using existing credentials.
    public func switchDatabase(to newDatabase: String) async throws {
        guard let driver = activeDriver else {
            throw DatabaseServiceError.notConnected
        }
        try await driver.switchDatabase(to: newDatabase)
    }

    /// Disconnects from the current database.
    public func disconnect() async throws {
        if let driver = activeDriver {
            try await driver.disconnect()
            self.activeDriver = nil
        }
    }

    /// Cancels the currently running query on the server.
    public func cancelRunningQuery() async {
        if let driver = activeDriver {
            await driver.cancelRunningQuery()
        }
    }

    /// Tests the connection without persisting it.
    public func testConnection(config: SavedConnection, password: String) async throws -> Bool {
        self.lastConnectionError = nil
        let driver: any DatabaseDriverProtocol
        switch config.engine {
        case .postgresql:
            driver = PostgresDriver(logger: logger)
        case .mysql, .mariadb:
            driver = MySQLDriver(engine: config.engine, logger: logger)
        }

        let success = try await driver.testConnection(config: config, password: password)
        if !success {
            self.lastConnectionError = await driver.lastConnectionError
        }
        return success
    }

    /// Executes a SQL query and returns the tabular results.
    public func executeQuery(_ sql: String) async throws -> QueryResult {
        guard let driver = activeDriver else {
            throw DatabaseServiceError.notConnected
        }
        return try await driver.executeQuery(sql)
    }

    /// Fetches paginated data from a table with an optional WHERE filter clause and optional ORDER BY clause.
    public func fetchTableData(
        schema: String,
        table: String,
        filterClause: String = "",
        orderBy: String? = nil,
        limit: Int = 200,
        offset: Int = 0
    ) async throws -> QueryResult {
        guard let driver = activeDriver else {
            throw DatabaseServiceError.notConnected
        }
        return try await driver.fetchTableData(
            schema: schema,
            table: table,
            filterClause: filterClause,
            orderBy: orderBy,
            limit: limit,
            offset: offset
        )
    }

    /// Fetches the total row count for a table with an optional WHERE filter clause.
    public func fetchTableRowCount(schema: String, table: String, filterClause: String = "") async throws -> Int64 {
        guard let driver = activeDriver else {
            throw DatabaseServiceError.notConnected
        }
        return try await driver.fetchTableRowCount(schema: schema, table: table, filterClause: filterClause)
    }

    /// Executes a single raw SQL command (e.g. DDL or transaction command).
    public func executeRawStatement(_ sql: String) async throws {
        guard let driver = activeDriver else {
            throw DatabaseServiceError.notConnected
        }
        try await driver.executeRawStatement(sql)
    }

    /// Streams query results row by row to an asynchronous callback without accumulating rows in memory.
    public func streamQuery(
        _ sql: String,
        onRow: @escaping ([ResultColumn], [CellValue]) async throws -> Void
    ) async throws -> (columns: [ResultColumn], rowCount: Int64, executionTime: Double) {
        guard let driver = activeDriver else {
            throw DatabaseServiceError.notConnected
        }
        return try await driver.streamQuery(sql, onRow: onRow)
    }

    /// Executes a batched multi-row INSERT statement safely with escaped literals.
    public func executeBatchInsert(
        schema: String,
        table: String,
        columns: [String],
        rows: [[String]],
        treatEmptyAsNull: Bool = true
    ) async throws -> Int {
        guard let driver = activeDriver else {
            throw DatabaseServiceError.notConnected
        }
        return try await driver.executeBatchInsert(
            schema: schema,
            table: table,
            columns: columns,
            rows: rows,
            treatEmptyAsNull: treatEmptyAsNull
        )
    }

    // MARK: - Error Diagnostics & Formatting

    /// Formats any PostgreSQL, MySQL, network, TLS, or system error into a clean, human-readable message.
    public static func formatError(_ error: Error, host: String? = nil, port: Int? = nil) -> String {
        if error is PSQLError {
            return PostgresDriver.formatError(error, host: host, port: port)
        }
        if error is MySQLError {
            return MySQLDriver.formatError(error, host: host, port: port)
        }
        if let serviceErr = error as? DatabaseServiceError {
            return serviceErr.localizedDescription
        }

        // Check if error domain or description indicates PSQLError or MySQLError
        let nsError = error as NSError
        if nsError.domain == "PostgresNIO.PSQLError" {
            return PostgresDriver.formatError(error, host: host, port: port)
        }
        if nsError.domain == "MySQLNIO.MySQLError" {
            return MySQLDriver.formatError(error, host: host, port: port)
        }

        return PostgresDriver.formatError(error, host: host, port: port)
    }
}

/// Backwards-compatible alias for existing codebase and tests.
public typealias PostgresService = DatabaseService
