import XCTest
@testable import Postgrace

final class ModelTests: XCTestCase {
    func testSavedConnectionCodable() throws {
        let original = SavedConnection(
            name: "Local Dev",
            host: "127.0.0.1",
            port: 5432,
            username: "postgres",
            database: "testdb",
            sslMode: .require,
            colorTag: .blue
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SavedConnection.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "Local Dev")
        XCTAssertEqual(decoded.host, "127.0.0.1")
        XCTAssertEqual(decoded.port, 5432)
        XCTAssertEqual(decoded.username, "postgres")
        XCTAssertEqual(decoded.database, "testdb")
        XCTAssertEqual(decoded.sslMode, .require)
        XCTAssertEqual(decoded.colorTag, .blue)
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
