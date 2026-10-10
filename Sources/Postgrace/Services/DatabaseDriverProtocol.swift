import Foundation

/// Protocol defining the interface for an underlying database driver (PostgreSQL, MySQL, MariaDB).
public protocol DatabaseDriverProtocol: Actor {
    /// The database engine handled by this driver instance.
    var engine: DatabaseEngine { get }

    /// Whether this driver is currently connected to a database server.
    var isConnected: Bool { get }

    /// The name of the active database/catalog.
    var currentDatabase: String? { get }

    /// The active connection configuration, if connected.
    var activeConfig: SavedConnection? { get }

    /// The active password in use, if connected.
    var activePassword: String? { get }

    /// The most recent connection error message, if any.
    var lastConnectionError: String? { get }

    /// Connects to the database server using the given configuration and password.
    func connect(config: SavedConnection, password: String) async throws

    /// Disconnects from the database server.
    func disconnect() async throws

    /// Switches the active database on the current server.
    func switchDatabase(to newDatabase: String) async throws

    /// Tests the connection credentials and connectivity without persisting.
    func testConnection(config: SavedConnection, password: String) async throws -> Bool

    /// Executes a SQL query and returns the tabular result.
    func executeQuery(_ sql: String) async throws -> QueryResult

    /// Fetches paginated data from a table with optional filter and ordering.
    func fetchTableData(
        schema: String,
        table: String,
        filterClause: String,
        orderBy: String?,
        limit: Int,
        offset: Int
    ) async throws -> QueryResult

    /// Fetches the total row count for a table with optional filter.
    func fetchTableRowCount(schema: String, table: String, filterClause: String) async throws -> Int64

    /// Executes a single raw statement (e.g. DDL or transaction statement).
    func executeRawStatement(_ sql: String) async throws

    /// Streams query rows row-by-row to an asynchronous callback.
    func streamQuery(
        _ sql: String,
        onRow: @escaping ([ResultColumn], [CellValue]) async throws -> Void
    ) async throws -> (columns: [ResultColumn], rowCount: Int64, executionTime: Double)

    /// Executes a batched multi-row INSERT statement.
    func executeBatchInsert(
        schema: String,
        table: String,
        columns: [String],
        rows: [[String]],
        treatEmptyAsNull: Bool
    ) async throws -> Int

    /// Cancels the currently executing query on this session.
    func cancelRunningQuery() async
}
