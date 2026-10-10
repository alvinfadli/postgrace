import XCTest
@testable import Postgrace

final class ModelTests: XCTestCase {
    func testDatabaseEngineProperties() {
        XCTAssertEqual(DatabaseEngine.postgresql.defaultPort, 5432)
        XCTAssertEqual(DatabaseEngine.mysql.defaultPort, 3306)
        XCTAssertEqual(DatabaseEngine.mariadb.defaultPort, 3306)

        XCTAssertEqual(DatabaseEngine.postgresql.defaultDatabase, "postgres")
        XCTAssertEqual(DatabaseEngine.mysql.defaultDatabase, "mysql")
        XCTAssertEqual(DatabaseEngine.mariadb.defaultDatabase, "mysql")

        XCTAssertEqual(DatabaseEngine.postgresql.defaultUsername, "postgres")
        XCTAssertEqual(DatabaseEngine.mysql.defaultUsername, "root")
        XCTAssertEqual(DatabaseEngine.mariadb.defaultUsername, "root")

        XCTAssertEqual(DatabaseEngine.postgresql.quoteIdentifier("users"), "\"users\"")
        XCTAssertEqual(DatabaseEngine.mysql.quoteIdentifier("users"), "`users`")
        XCTAssertEqual(DatabaseEngine.mariadb.quoteIdentifier("users"), "`users`")

        XCTAssertEqual("my`table".mysqlQuotedIdentifier, "`my``table`")
        XCTAssertEqual("O'Reilly\\Test".mysqlEscapedLiteral, "O''Reilly\\\\Test")
    }

    func testSavedConnectionBackwardsCompatibility() throws {
        // Legacy JSON without 'engine' property
        let legacyJSON = """
        {
            "id": "123e4567-e89b-12d3-a456-426614174000",
            "name": "Legacy Postgres Profile",
            "host": "localhost",
            "port": 5432,
            "username": "postgres",
            "database": "postgres",
            "sslMode": "disable",
            "colorTag": "blue",
            "createdAt": "2026-10-01T00:00:00Z",
            "updatedAt": "2026-10-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let conn = try decoder.decode(SavedConnection.self, from: legacyJSON)

        XCTAssertEqual(conn.engine, .postgresql, "Legacy configs without 'engine' key MUST default to .postgresql")
        XCTAssertEqual(conn.name, "Legacy Postgres Profile")
        XCTAssertEqual(conn.port, 5432)
    }

    func testSavedConnectionMySQLAndMariaDB() throws {
        let mysqlConn = SavedConnection(
            name: "Local MySQL",
            engine: .mysql,
            username: "root",
            database: "ecommerce"
        )
        XCTAssertEqual(mysqlConn.engine, .mysql)
        XCTAssertEqual(mysqlConn.port, 3306, "Default port for MySQL should be 3306")

        let mariadbConn = SavedConnection(
            name: "Local MariaDB",
            engine: .mariadb,
            username: "root",
            database: "analytics"
        )
        XCTAssertEqual(mariadbConn.engine, .mariadb)
        XCTAssertEqual(mariadbConn.port, 3306, "Default port for MariaDB should be 3306")

        let encoder = JSONEncoder()
        let data = try encoder.encode(mysqlConn)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SavedConnection.self, from: data)
        XCTAssertEqual(decoded.engine, .mysql)
        XCTAssertEqual(decoded.port, 3306)
    }

    func testSavedConnectionSafeModeProperties() throws {
        // Localhost addresses
        let localHosts = ["localhost", "127.0.0.1", "::1", "docker.local", "  localhost  "]
        for host in localHosts {
            let conn = SavedConnection(name: "Local", host: host, username: "pg", database: "test")
            XCTAssertTrue(conn.isLocalhost, "Host '\(host)' should be evaluated as localhost")
            XCTAssertFalse(conn.isSafeModeLocked, "Localhost should not lock Safe Mode")
            XCTAssertFalse(conn.isSafeModeEffective, "Safe Mode should be OFF by default on localhost")

            var enabledConn = conn
            enabledConn.isSafeModeEnabled = true
            XCTAssertTrue(enabledConn.isSafeModeEffective, "Safe Mode should be ON when explicitly enabled")
        }

        // Remote hosts
        let remoteHosts = ["db.aws.com", "10.0.1.5", "192.168.1.100", "supabase.co", "postgres.prod.internal"]
        for host in remoteHosts {
            let conn = SavedConnection(name: "Remote", host: host, username: "pg", database: "prod")
            XCTAssertFalse(conn.isLocalhost, "Host '\(host)' should be evaluated as remote")
            XCTAssertTrue(conn.isSafeModeLocked, "Remote host MUST be locked to Safe Mode")
            XCTAssertTrue(conn.isSafeModeEffective, "Safe Mode MUST be permanently active on remote host")

            // Even if explicitly set to false, effective safe mode on remote is always TRUE
            var attemptedBypass = conn
            attemptedBypass.isSafeModeEnabled = false
            XCTAssertTrue(attemptedBypass.isSafeModeEffective, "Remote Safe Mode cannot be bypassed")
        }
    }
    
    func testCellValueDisplayString() {
        XCTAssertEqual(CellValue.null.displayString, "NULL")
        XCTAssertEqual(CellValue.string("hello").displayString, "hello")
        XCTAssertEqual(CellValue.int(42).displayString, "42")
        XCTAssertEqual(CellValue.double(3.14).displayString, "3.14")
        XCTAssertEqual(CellValue.bool(true).displayString, "true")
        XCTAssertEqual(CellValue.bool(false).displayString, "false")
        XCTAssertEqual(CellValue.json("{\"a\":1}").displayString, "{\"a\":1}")
        XCTAssertEqual(CellValue.array("{1,2,3}").displayString, "{1,2,3}")
    }
    
    func testQueryResultProperties() {
        let columns = [
            ResultColumn(name: "id", dataTypeOID: 23, dataTypeName: "int4"),
            ResultColumn(name: "name", dataTypeOID: 25, dataTypeName: "text")
        ]
        let rows: [[CellValue]] = [
            [.int(1), .string("Alice")],
            [.int(2), .null]
        ]
        let result = QueryResult(
            columns: columns,
            rows: rows,
            executionTime: 0.015,
            rowsAffected: 2,
            statusMessage: "SELECT 2"
        )
        
        XCTAssertEqual(result.columns.count, 2)
        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0][0], .int(1))
        XCTAssertEqual(result.rows[1][1], .null)
        XCTAssertEqual(result.executionTime, 0.015)
        XCTAssertEqual(result.rowsAffected, 2)
        XCTAssertEqual(result.statusMessage, "SELECT 2")
    }

    func testFilterRuleSQLExpression() {
        // Equals numeric
        let numRule = FilterRule(column: "id", op: .equals, value: "42")
        XCTAssertEqual(numRule.toSQLExpression(), "\"id\" = 42")

        // Equals string
        let strRule = FilterRule(column: "status", op: .equals, value: "active")
        XCTAssertEqual(strRule.toSQLExpression(), "\"status\" = 'active'")

        // Not equals
        let notEqRule = FilterRule(column: "role", op: .notEquals, value: "guest")
        XCTAssertEqual(notEqRule.toSQLExpression(), "\"role\" != 'guest'")

        // Comparison operators
        let gtRule = FilterRule(column: "price", op: .greaterThan, value: "19.99")
        XCTAssertEqual(gtRule.toSQLExpression(), "\"price\" > 19.99")

        let lteRule = FilterRule(column: "stock", op: .lessThanOrEqual, value: "0")
        XCTAssertEqual(lteRule.toSQLExpression(), "\"stock\" <= 0")

        // Contains (ILIKE)
        let containsRule = FilterRule(column: "email", op: .contains, value: "example.com")
        XCTAssertEqual(containsRule.toSQLExpression(), "\"email\"::text ILIKE '%example.com%'")

        // Starts with
        let startsRule = FilterRule(column: "name", op: .startsWith, value: "John")
        XCTAssertEqual(startsRule.toSQLExpression(), "\"name\"::text ILIKE 'John%'")

        // Ends with
        let endsRule = FilterRule(column: "filename", op: .endsWith, value: ".pdf")
        XCTAssertEqual(endsRule.toSQLExpression(), "\"filename\"::text ILIKE '%.pdf'")

        // IS NULL and IS NOT NULL
        let isNullRule = FilterRule(column: "deleted_at", op: .isNull, value: "")
        XCTAssertEqual(isNullRule.toSQLExpression(), "\"deleted_at\" IS NULL")

        let isNotNullRule = FilterRule(column: "confirmed_at", op: .isNotNull, value: "")
        XCTAssertEqual(isNotNullRule.toSQLExpression(), "\"confirmed_at\" IS NOT NULL")

        // SQL injection escaping in string value
        let injectRule = FilterRule(column: "user", op: .equals, value: "admin' OR '1'='1")
        XCTAssertEqual(injectRule.toSQLExpression(), "\"user\" = 'admin'' OR ''1''=''1'")

        // Empty column returns nil
        let emptyCol = FilterRule(column: "", op: .equals, value: "abc")
        XCTAssertNil(emptyCol.toSQLExpression())

        // Empty value on value-requiring operator returns nil
        let emptyVal = FilterRule(column: "status", op: .equals, value: "")
        XCTAssertNil(emptyVal.toSQLExpression())
    }
}
