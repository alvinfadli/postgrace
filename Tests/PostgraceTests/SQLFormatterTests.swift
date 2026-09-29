import XCTest
@testable import Postgrace

final class SQLFormatterTests: XCTestCase {
    func testBasicSelectFormatting() {
        let input = "select id, name, email from users where active = true order by id desc limit 50;"
        let output = SQLFormatter.format(input)

        XCTAssertTrue(output.contains("SELECT id, name, email"))
        XCTAssertTrue(output.contains("FROM users"))
        XCTAssertTrue(output.contains("WHERE active = true"))
        XCTAssertTrue(output.contains("ORDER BY id DESC"))
        XCTAssertTrue(output.contains("LIMIT 50;"))
    }

    func testPreservesStringLiterals() {
        let input = "select * from logs where message = 'select from where';"
        let output = SQLFormatter.format(input)

        XCTAssertTrue(output.contains("'select from where'"))
    }

    func testJoinsAndClauses() {
        let input = "select u.id, p.title from users u left join posts p on u.id = p.user_id group by u.id;"
        let output = SQLFormatter.format(input)

        XCTAssertTrue(output.contains("LEFT JOIN"))
        XCTAssertTrue(output.contains("ON"))
        XCTAssertTrue(output.contains("GROUP BY"))
    }
}
