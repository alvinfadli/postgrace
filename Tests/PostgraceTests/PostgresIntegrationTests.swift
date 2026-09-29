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
}

