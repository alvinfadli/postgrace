import XCTest
@testable import Postgrace

final class PostgresIntegrationTests: XCTestCase {
    
    var postgresService: PostgresService!
    var schemaService: SchemaService!
    let config = SavedConnection(
        name: "Local Homebrew PG",
        host: "localhost",
        port: 5432,
        username: "ddt",
        database: "postgres",
        sslMode: .disable
    )
    
    override func setUp() async throws {
        postgresService = PostgresService()
        schemaService = SchemaService(postgresService: postgresService)
    }
    
    override func tearDown() async throws {
        try? await postgresService.disconnect()
    }
    
    func testLiveConnectionAndQueryExecution() async throws {
        // Test connection check
        let isReachable = try await postgresService.testConnection(config: config, password: "")
        guard isReachable else {
            throw XCTSkip("Local PostgreSQL is not reachable on localhost:5432 with user ddt. Skipping live integration test.")
        }
        
        // Connect
        try await postgresService.connect(config: config, password: "")
        let connected = await postgresService.isConnected
        XCTAssertTrue(connected, "Service should be connected")
        
        // Execute multi-type query
        let sql = """
        SELECT 42 AS int_val,
               'Postgrace' AS str_val,
               3.14159::float8 AS float_val,
               true AS bool_val,
               NULL AS null_val,
               '{"version": 1}'::jsonb AS json_val;
        """
        let result = try await postgresService.executeQuery(sql)
        
        XCTAssertEqual(result.columns.count, 6)
        XCTAssertEqual(result.rows.count, 1)
        
        let row = result.rows[0]
        XCTAssertEqual(row[0], .int(42))
        XCTAssertEqual(row[1], .string("Postgrace"))
        if case .double(let d) = row[2] {
            XCTAssertEqual(d, 3.14159, accuracy: 0.0001)
        } else {
            XCTFail("Expected double for float_val")
        }
        XCTAssertEqual(row[3], .bool(true))
        XCTAssertEqual(row[4], .null)
        if case .json(let j) = row[5] {
            XCTAssertTrue(j.contains("version"))
        } else {
            XCTFail("Expected json for json_val")
        }
    }
    
    func testSchemaIntrospectionAndTableLifecycle() async throws {
        let isReachable = try await postgresService.testConnection(config: config, password: "")
        guard isReachable else {
            throw XCTSkip("Local PostgreSQL not reachable.")
        }
        
        try await postgresService.connect(config: config, password: "")
        
        // 1. Fetch databases
        let databases = try await schemaService.fetchDatabases()
        XCTAssertFalse(databases.isEmpty)
        XCTAssertTrue(databases.contains { $0.name == "postgres" })
        
        // 2. Fetch schemas
        let schemas = try await schemaService.fetchSchemas()
        XCTAssertFalse(schemas.isEmpty)
        XCTAssertTrue(schemas.contains { $0.name == "public" })
        
        // 3. Create temporary table for schema validation
        let tempTableName = "postgrace_qa_\(Int.random(in: 1000...9999))"
        _ = try await postgresService.executeQuery("""
        CREATE TABLE public.\(tempTableName) (
            id SERIAL PRIMARY KEY,
            title VARCHAR(100) NOT NULL,
            views INT DEFAULT 0
        );
        """)
        
        defer {
            Task {
                _ = try? await self.postgresService.executeQuery("DROP TABLE IF EXISTS public.\(tempTableName);")
            }
        }
        
        // Insert sample rows
        _ = try await postgresService.executeQuery("""
        INSERT INTO public.\(tempTableName) (title, views) VALUES
            ('First Post', 10),
            ('Second Post', 25),
            ('Third Post', 100);
        """)
        
        // 4. Test fetchTables
        let tables = try await schemaService.fetchTables(schema: "public")
        let foundTable = tables.first { $0.name == tempTableName }
        XCTAssertNotNil(foundTable, "Created table should be listed in public schema")
        
        // 5. Test fetchColumns
        let columns = try await schemaService.fetchColumns(schema: "public", table: tempTableName)
        XCTAssertEqual(columns.count, 3)
        let idCol = columns.first { $0.name == "id" }
        XCTAssertNotNil(idCol)
        XCTAssertTrue(idCol?.isPrimaryKey == true, "id column should be primary key")
        
        let titleCol = columns.first { $0.name == "title" }
        XCTAssertNotNil(titleCol)
        XCTAssertFalse(titleCol?.isNullable ?? true, "title column should not be nullable")
        
        // 6. Test fetchTableRowCount and fetchTableData
        let count = try await postgresService.fetchTableRowCount(schema: "public", table: tempTableName)
        XCTAssertEqual(count, 3)
        
        let pagedData = try await postgresService.fetchTableData(schema: "public", table: tempTableName, limit: 2, offset: 1)
        XCTAssertEqual(pagedData.rows.count, 2)
        
        // Cleanup table
        _ = try await postgresService.executeQuery("DROP TABLE IF EXISTS public.\(tempTableName);")
    }
    
    func testInvalidQueryThrowsExpectedError() async throws {
        let isReachable = try await postgresService.testConnection(config: config, password: "")
        guard isReachable else {
            throw XCTSkip("PostgreSQL not reachable.")
        }
        try await postgresService.connect(config: config, password: "")
        
        do {
            _ = try await postgresService.executeQuery("SELECT * FROM non_existent_table_12345;")
            XCTFail("Should have thrown queryFailed error")
        } catch let error as PostgresServiceError {
            if case .queryFailed(let reason) = error {
                XCTAssertTrue(reason.contains("does not exist") || reason.contains("relation"), "Reason was: \(reason)")
            } else {
                XCTFail("Expected queryFailed error case, got: \(error)")
            }
        } catch {
            XCTFail("Expected PostgresServiceError, got: \(error)")
        }
    }
    
    func testQueryExecutionWhenNotConnected() async throws {
        let disconnectedService = PostgresService()
        do {
            _ = try await disconnectedService.executeQuery("SELECT 1;")
            XCTFail("Should have thrown notConnected error")
        } catch let error as PostgresServiceError {
            if case .notConnected = error {
                // Expected
            } else {
                XCTFail("Expected notConnected error, got: \(error)")
            }
        }
    }
    
    func testLiveInConnectionDatabaseSwitching() async throws {
        let isReachable = try await postgresService.testConnection(config: config, password: "")
        guard isReachable else {
            throw XCTSkip("PostgreSQL not reachable.")
        }
        
        // 1. Connect to initial database "postgres"
        try await postgresService.connect(config: config, password: "")
        let initialDb = await postgresService.currentDatabase
        XCTAssertEqual(initialDb, "postgres")
        
        let initialResult = try await postgresService.executeQuery("SELECT current_database();")
        XCTAssertEqual(initialResult.rows.first?.first, .string("postgres"))
        
        // 2. Discover another available database
        let databases = try await schemaService.fetchDatabases()
        guard let targetDb = databases.first(where: { $0.name != "postgres" && $0.name != "template1" && $0.name != "template0" }) else {
            return // Skip switch if no other database exists
        }
        
        // 3. Switch to target database
        try await postgresService.switchDatabase(to: targetDb.name)
        let switchedDb = await postgresService.currentDatabase
        XCTAssertEqual(switchedDb, targetDb.name)
        
        let switchedResult = try await postgresService.executeQuery("SELECT current_database();")
        XCTAssertEqual(switchedResult.rows.first?.first, .string(targetDb.name))
        
        // 4. Switch back cleanly to "postgres"
        try await postgresService.switchDatabase(to: "postgres")
        let restoredDb = await postgresService.currentDatabase
        XCTAssertEqual(restoredDb, "postgres")
    }

    func testTableDataFilteringWithWhereClause() async throws {
        let isReachable = try await postgresService.testConnection(config: config, password: "")
        guard isReachable else {
            throw XCTSkip("PostgreSQL not reachable.")
        }
        try await postgresService.connect(config: config, password: "")

        let tempTableName = "postgrace_filter_\(Int.random(in: 1000...9999))"
        _ = try await postgresService.executeQuery("""
        CREATE TABLE public.\(tempTableName) (
            id INT PRIMARY KEY,
            status VARCHAR(20) NOT NULL
        );
        """)
        _ = try await postgresService.executeQuery("""
        INSERT INTO public.\(tempTableName) (id, status) VALUES
            (1, 'active'),
            (2, 'inactive'),
            (3, 'active'),
            (4, 'pending');
        """)
        defer {
            Task {
                _ = try? await self.postgresService.executeQuery("DROP TABLE IF EXISTS public.\(tempTableName);")
            }
        }

        // Test unfiltered count
        let totalCount = try await postgresService.fetchTableRowCount(schema: "public", table: tempTableName, filterClause: "")
        XCTAssertEqual(totalCount, 4)

        // Test filtered count
        let filteredCount = try await postgresService.fetchTableRowCount(schema: "public", table: tempTableName, filterClause: "status = 'active'")
        XCTAssertEqual(filteredCount, 2)

        // Test filtered data
        let filteredData = try await postgresService.fetchTableData(schema: "public", table: tempTableName, filterClause: "status = 'active'", limit: 10, offset: 0)
        XCTAssertEqual(filteredData.rows.count, 2)
    }

    func testUserPrivilegeIntrospection() async throws {
        let isReachable = try await postgresService.testConnection(config: config, password: "")
        guard isReachable else {
            throw XCTSkip("PostgreSQL not reachable.")
        }
        try await postgresService.connect(config: config, password: "")

        let privs = try await schemaService.fetchUserPrivileges()
        XCTAssertEqual(privs.username, "ddt")
        XCTAssertFalse(privs.privilegeLevelDescription.isEmpty)

        // Schema privileges check
        XCTAssertFalse(privs.schemaPrivileges.isEmpty)
        if let publicPriv = privs.schemaPrivileges["public"] {
            XCTAssertTrue(publicPriv.canUsage)
        } else {
            XCTFail("Expected public schema privileges")
        }

        // Schema details check
        let schemaDetails = try await schemaService.fetchSchemaDetails()
        XCTAssertFalse(schemaDetails.isEmpty)
        XCTAssertTrue(schemaDetails.contains { $0.name == "public" })
    }

    func testSchemaCrudLifecycle() async throws {
        let isReachable = try await postgresService.testConnection(config: config, password: "")
        guard isReachable else {
            throw XCTSkip("PostgreSQL not reachable.")
        }
        try await postgresService.connect(config: config, password: "")

        let rand = Int.random(in: 1000...9999)
        let schema1 = "postgrace_sch_\(rand)"
        let schema2 = "postgrace_renamed_\(rand)"

        // 1. Create Schema
        try await schemaService.createSchema(name: schema1)
        var details = try await schemaService.fetchSchemaDetails()
        XCTAssertTrue(details.contains { $0.name == schema1 }, "Created schema should exist")

        // 2. Rename Schema
        try await schemaService.renameSchema(from: schema1, to: schema2)
        details = try await schemaService.fetchSchemaDetails()
        XCTAssertFalse(details.contains { $0.name == schema1 }, "Old schema name should no longer exist")
        XCTAssertTrue(details.contains { $0.name == schema2 }, "Renamed schema should exist")

        // 3. Drop Schema
        try await schemaService.dropSchema(name: schema2, cascade: true)
        details = try await schemaService.fetchSchemaDetails()
        XCTAssertFalse(details.contains { $0.name == schema2 }, "Dropped schema should be removed")
    }

    func testTableCrudLifecycle() async throws {
        let isReachable = try await postgresService.testConnection(config: config, password: "")
        guard isReachable else {
            throw XCTSkip("PostgreSQL not reachable.")
        }
        try await postgresService.connect(config: config, password: "")

        let rand = Int.random(in: 1000...9999)
        let table1 = "postgrace_tbl_\(rand)"
        let table2 = "postgrace_tbl_renamed_\(rand)"

        let columns = [
            NewColumnDefinition(name: "id", dataType: "bigserial", isPrimaryKey: true, isNullable: false, defaultValue: ""),
            NewColumnDefinition(name: "title", dataType: "text", isPrimaryKey: false, isNullable: false, defaultValue: ""),
            NewColumnDefinition(name: "views", dataType: "integer", isPrimaryKey: false, isNullable: true, defaultValue: "0")
        ]

        // 1. Create Table
        try await schemaService.createTable(schema: "public", name: table1, columns: columns)
        var tableDetails = try await schemaService.fetchTableDetails(schema: "public")
        XCTAssertTrue(tableDetails.contains { $0.name == table1 }, "Created table should exist in table details")

        let createdTable = tableDetails.first { $0.name == table1 }
        XCTAssertNotNil(createdTable)
        XCTAssertEqual(createdTable?.columnCount, 3)
        XCTAssertTrue(createdTable?.canInsert == true)

        // 2. Rename Table
        try await schemaService.renameTable(schema: "public", from: table1, to: table2)
        tableDetails = try await schemaService.fetchTableDetails(schema: "public")
        XCTAssertFalse(tableDetails.contains { $0.name == table1 })
        XCTAssertTrue(tableDetails.contains { $0.name == table2 })

        // 3. Insert and Truncate Table
        _ = try await postgresService.executeQuery("INSERT INTO public.\(table2) (title, views) VALUES ('Test post', 42);")
        let countBefore = try await postgresService.fetchTableRowCount(schema: "public", table: table2, filterClause: "")
        XCTAssertEqual(countBefore, 1)

        try await schemaService.truncateTable(schema: "public", name: table2)
        let countAfter = try await postgresService.fetchTableRowCount(schema: "public", table: table2, filterClause: "")
        XCTAssertEqual(countAfter, 0)

        // 4. Drop Table
        try await schemaService.dropTable(schema: "public", name: table2, cascade: true)
        tableDetails = try await schemaService.fetchTableDetails(schema: "public")
        XCTAssertFalse(tableDetails.contains { $0.name == table2 })
    }

    func testQueryCancellation() async throws {
        let isReachable = try await postgresService.testConnection(config: config, password: "")
        guard isReachable else {
            throw XCTSkip("Local PostgreSQL is not reachable on localhost:5432 with user ddt. Skipping live integration test.")
        }

        try await postgresService.connect(config: config, password: "")

        let startTime = Date()
        let queryTask = Task { () -> QueryResult in
            try await postgresService.executeQuery("SELECT pg_sleep(5);")
        }

        // Wait 100ms for query to start executing on the PostgreSQL backend
        try await Task.sleep(nanoseconds: 100_000_000)

        // Abort the running query
        await postgresService.cancelRunningQuery()

        do {
            _ = try await queryTask.value
            XCTFail("Query should have been aborted")
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            XCTAssertLessThan(duration, 3.0, "Query cancellation should abort promptly, not wait the full 5 seconds")
            XCTAssertTrue(error.localizedDescription.lowercased().contains("cancel"), "Error should reflect query cancellation")
        }
    }
}


