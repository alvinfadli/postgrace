import Foundation
@testable import Postgrace

/// Mock implementation of DatabaseDriverProtocol for deterministic, headless unit testing.
public actor MockDatabaseDriver: DatabaseDriverProtocol {
    public var engine: DatabaseEngine
    public var isConnected: Bool = true
    public var currentDatabase: String? = "testdb"
    public var activeConfig: SavedConnection?
    public var activePassword: String? = "mock_secret"
    public var lastConnectionError: String?

    // Call tracking
    public var executedQueries: [String] = []
    public var executedRawStatements: [String] = []
    public var executedBatchInserts: [(schema: String, table: String, columns: [String], rows: [[String]], treatEmptyAsNull: Bool)] = []
    public var switchedDatabases: [String] = []
    public var cancelledQueriesCount: Int = 0

    // Configurable responses
    public var queryResultProvider: (@Sendable (String) throws -> QueryResult)?
    public var defaultQueryResult: QueryResult = QueryResult(
        columns: [ResultColumn(name: "id", dataTypeOID: 23, dataTypeName: "integer"), ResultColumn(name: "name", dataTypeOID: 25, dataTypeName: "text")],
        rows: [
            [CellValue.int(1), CellValue.string("Item 1")],
            [CellValue.int(2), CellValue.string("Item 2")]
        ],
        executionTime: 0.005,
        rowsAffected: 2,
        statusMessage: "SELECT 2"
    )

    public var streamedRows: [([ResultColumn], [CellValue])] = [
        ([ResultColumn(name: "id", dataTypeOID: 23, dataTypeName: "integer"), ResultColumn(name: "title", dataTypeOID: 25, dataTypeName: "text")], [CellValue.int(1), CellValue.string("Alpha")]),
        ([ResultColumn(name: "id", dataTypeOID: 23, dataTypeName: "integer"), ResultColumn(name: "title", dataTypeOID: 25, dataTypeName: "text")], [CellValue.int(2), CellValue.string("Beta")])
    ]

    public var rowCountForTable: [String: Int64] = [:]
    public var shouldFailConnect: Bool = false
    public var shouldFailQuery: Bool = false
    public var shouldFailBatchInsert: Bool = false

    public func setQueryResultProvider(_ provider: (@Sendable (String) throws -> QueryResult)?) {
        self.queryResultProvider = provider
    }

    public init(engine: DatabaseEngine = .postgresql) {
        self.engine = engine
        self.activeConfig = SavedConnection(name: "Mock Connection", host: "localhost", username: "postgres", database: "testdb")
    }

    public func connect(config: SavedConnection, password: String) async throws {
        if shouldFailConnect {
            lastConnectionError = "Mock connection failed"
            throw DatabaseServiceError.connectionFailed("Mock connection failed")
        }
        self.activeConfig = config
        self.activePassword = password
        self.isConnected = true
        self.currentDatabase = config.database
    }

    public func disconnect() async throws {
        self.isConnected = false
    }

    public func switchDatabase(to newDatabase: String) async throws {
        switchedDatabases.append(newDatabase)
        currentDatabase = newDatabase
    }

    public func testConnection(config: SavedConnection, password: String) async throws -> Bool {
        return !shouldFailConnect
    }

    public func executeQuery(_ sql: String) async throws -> QueryResult {
        executedQueries.append(sql)
        if shouldFailQuery {
            throw DatabaseServiceError.queryFailed("Mock query failure for: \(sql)")
        }
        if let provider = queryResultProvider {
            return try provider(sql)
        }
        return defaultQueryResult
    }

    public func fetchTableData(
        schema: String,
        table: String,
        filterClause: String,
        orderBy: String?,
        limit: Int,
        offset: Int
    ) async throws -> QueryResult {
        let sql = "SELECT * FROM \(schema).\(table) LIMIT \(limit) OFFSET \(offset)"
        return try await executeQuery(sql)
    }

    public func fetchTableRowCount(schema: String, table: String, filterClause: String) async throws -> Int64 {
        let key = "\(schema).\(table)"
        if let count = rowCountForTable[key] {
            return count
        }
        return Int64(defaultQueryResult.rows.count)
    }

    public func executeRawStatement(_ sql: String) async throws {
        executedRawStatements.append(sql)
        if shouldFailQuery {
            throw DatabaseServiceError.queryFailed("Raw statement error")
        }
    }

    public func streamQuery(
        _ sql: String,
        onRow: @escaping ([ResultColumn], [CellValue]) async throws -> Void
    ) async throws -> (columns: [ResultColumn], rowCount: Int64, executionTime: Double) {
        executedQueries.append(sql)
        if shouldFailQuery {
            throw DatabaseServiceError.queryFailed("Stream query error")
        }

        let columns = streamedRows.first?.0 ?? [ResultColumn(name: "id", dataTypeOID: 23, dataTypeName: "integer")]
        var count: Int64 = 0
        for (cols, row) in streamedRows {
            try await onRow(cols, row)
            count += 1
        }
        return (columns: columns, rowCount: count, executionTime: 0.01)
    }

    public func executeBatchInsert(
        schema: String,
        table: String,
        columns: [String],
        rows: [[String]],
        treatEmptyAsNull: Bool
    ) async throws -> Int {
        if shouldFailBatchInsert {
            throw DatabaseServiceError.queryFailed("Batch insert failed")
        }
        executedBatchInserts.append((schema, table, columns, rows, treatEmptyAsNull))
        return rows.count
    }

    public func cancelRunningQuery() async {
        cancelledQueriesCount += 1
    }
}
