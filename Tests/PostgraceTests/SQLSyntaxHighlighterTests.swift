import XCTest
import AppKit
@testable import Postgrace

final class SQLSyntaxHighlighterTests: XCTestCase {

    func testKeywordsCommandsFunctionsAndTypes() {
        let sql = "SELECT id, COUNT(*) FROM users WHERE status = 'active' AND age >= 21 LIMIT 10;"
        let tokens = SQLSyntaxHighlighter.tokenize(sql)
        let nsString = sql as NSString

        func tokenKind(for word: String) -> SQLTokenKind? {
            tokens.first(where: { nsString.substring(with: $0.range) == word })?.kind
        }

        XCTAssertEqual(tokenKind(for: "SELECT"), .keyword)
        XCTAssertEqual(tokenKind(for: "id"), .identifier)
        XCTAssertEqual(tokenKind(for: "COUNT"), .function)
        XCTAssertEqual(tokenKind(for: "FROM"), .keyword)
        XCTAssertEqual(tokenKind(for: "users"), .identifier)
        XCTAssertEqual(tokenKind(for: "WHERE"), .keyword)
        XCTAssertEqual(tokenKind(for: "status"), .identifier)
        XCTAssertEqual(tokenKind(for: "="), .operatorSymbol)
        XCTAssertEqual(tokenKind(for: "'active'"), .stringLiteral)
        XCTAssertEqual(tokenKind(for: "AND"), .keyword)
        XCTAssertEqual(tokenKind(for: "age"), .identifier)
        XCTAssertEqual(tokenKind(for: ">="), .operatorSymbol)
        XCTAssertEqual(tokenKind(for: "21"), .numericLiteral)
        XCTAssertEqual(tokenKind(for: "LIMIT"), .keyword)
        XCTAssertEqual(tokenKind(for: "10"), .numericLiteral)
    }

    func testDDLCommandsAndDataTypes() {
        let sql = "CREATE TABLE public.accounts (id BIGSERIAL PRIMARY KEY, balance NUMERIC(12, 2) NOT NULL DEFAULT 0.00, metadata JSONB);"
        let tokens = SQLSyntaxHighlighter.tokenize(sql)
        let nsString = sql as NSString

        func tokenKind(for word: String) -> SQLTokenKind? {
            tokens.first(where: { nsString.substring(with: $0.range) == word })?.kind
        }

        XCTAssertEqual(tokenKind(for: "CREATE"), .command)
        XCTAssertEqual(tokenKind(for: "TABLE"), .command)
        XCTAssertEqual(tokenKind(for: "BIGSERIAL"), .dataType)
        XCTAssertEqual(tokenKind(for: "PRIMARY"), .keyword)
        XCTAssertEqual(tokenKind(for: "KEY"), .keyword)
        XCTAssertEqual(tokenKind(for: "NUMERIC"), .dataType)
        XCTAssertEqual(tokenKind(for: "0.00"), .numericLiteral)
        XCTAssertEqual(tokenKind(for: "JSONB"), .dataType)
    }

    func testCommentsAndDollarQuotedStrings() {
        let sql = """
        -- Single line comment
        # MySQL line comment
        /* Nested /* block */ comment */
        SELECT $tag$SELECT * FROM ignored;$tag$, 'it''s escaped', $1, TRUE, NULL;
        """
        let tokens = SQLSyntaxHighlighter.tokenize(sql)
        let nsString = sql as NSString

        let commentTokens = tokens.filter { $0.kind == .comment }.map { nsString.substring(with: $0.range) }
        XCTAssertEqual(commentTokens.count, 3)
        XCTAssertTrue(commentTokens[0].hasPrefix("-- Single line comment"))
        XCTAssertTrue(commentTokens[1].hasPrefix("# MySQL line comment"))
        XCTAssertEqual(commentTokens[2], "/* Nested /* block */ comment */")

        let stringTokens = tokens.filter { $0.kind == .stringLiteral }.map { nsString.substring(with: $0.range) }
        XCTAssertEqual(stringTokens, ["$tag$SELECT * FROM ignored;$tag$", "'it''s escaped'"])

        let numberTokens = tokens.filter { $0.kind == .numericLiteral }.map { nsString.substring(with: $0.range) }
        XCTAssertEqual(numberTokens, ["$1", "TRUE", "NULL"])
    }

    func testDottedMemberDoesNotMisclassifyColumnAsKeywordOrType() {
        let sql = "SELECT u.date, u.key, schema_name.custom_func(10) FROM \"Users\" u;"
        let tokens = SQLSyntaxHighlighter.tokenize(sql)
        let nsString = sql as NSString

        func tokenKind(for word: String) -> SQLTokenKind? {
            tokens.first(where: { nsString.substring(with: $0.range) == word })?.kind
        }

        XCTAssertEqual(tokenKind(for: "date"), .identifier, "u.date column should be classified as identifier, not dataType")
        XCTAssertEqual(tokenKind(for: "key"), .identifier, "u.key column should be classified as identifier, not keyword")
        XCTAssertEqual(tokenKind(for: "custom_func"), .function, "schema_name.custom_func(...) should be classified as function")
        XCTAssertEqual(tokenKind(for: "\"Users\""), .identifier)
    }

    func testUnicodeAndEmojiUTF16RangeSafety() {
        let sql = "SELECT '🚀🎉' AS emoji, COUNT(*) FROM users -- comment with 💡"
        let textStorage = NSTextStorage(string: sql)
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        SQLSyntaxHighlighter.highlight(textStorage, font: font)
        XCTAssertEqual(textStorage.length, (sql as NSString).length)

        let attributed = SQLSyntaxHighlighter.attributedString(for: sql, fontSize: 12)
        XCTAssertEqual(String(attributed.characters), sql)
    }
}
