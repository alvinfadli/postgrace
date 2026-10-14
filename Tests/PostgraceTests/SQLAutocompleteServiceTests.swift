import XCTest
@testable import Postgrace

final class SQLAutocompleteServiceTests: XCTestCase {

    func testCurrentWordExtraction() {
        let text = "SELECT * FROM users WHERE u"
        let (word, range) = SQLAutocompleteService.currentWord(in: text, at: text.count)
        XCTAssertEqual(word, "u")
        XCTAssertEqual(range.location, text.count - 1)
        XCTAssertEqual(range.length, 1)

        // Empty at beginning
        let (emptyWord, emptyRange) = SQLAutocompleteService.currentWord(in: "", at: 0)
        XCTAssertEqual(emptyWord, "")
        XCTAssertEqual(emptyRange.length, 0)

        // Dotted identifier
        let dotted = "SELECT users.em"
        let (dotWord, dotRange) = SQLAutocompleteService.currentWord(in: dotted, at: dotted.count)
        XCTAssertEqual(dotWord, "users.em")
        XCTAssertEqual(dotRange.location, 7)
    }

    func testKeywordAndFunctionSuggestions() {
        let (prefix, _, items) = SQLAutocompleteService.suggestions(
            for: "SEL",
            at: 3,
            tables: [:],
            columns: [:],
            schemas: []
        )
        XCTAssertEqual(prefix, "SEL")
        XCTAssertTrue(items.contains(where: { $0.text == "SELECT" }))

        // Function suggestion
        let (_, _, fnItems) = SQLAutocompleteService.suggestions(
            for: "cou",
            at: 3,
            tables: [:],
            columns: [:],
            schemas: []
        )
        XCTAssertTrue(fnItems.contains(where: { $0.text == "COUNT(*)" }))
    }

    func testTableAndColumnSuggestions() {
        let sampleTables: [String: [TableInfo]] = [
            "public": [
                TableInfo(schema: "public", name: "users", oid: 101, estimatedRowCount: 50, tableType: .table),
                TableInfo(schema: "public", name: "orders", oid: 102, estimatedRowCount: 120, tableType: .table)
            ],
            "merchant": [
                TableInfo(schema: "merchant", name: "store", oid: 201, estimatedRowCount: 15, tableType: .table)
            ]
        ]
        let sampleColumns: [String: [ColumnInfo]] = [
            "public.users": [
                ColumnInfo(name: "id", ordinalPosition: 1, dataType: "int4", isNullable: false, defaultValue: nil, isPrimaryKey: true, characterMaxLength: nil),
                ColumnInfo(name: "email", ordinalPosition: 2, dataType: "varchar", isNullable: false, defaultValue: nil, isPrimaryKey: false, characterMaxLength: 255)
            ],
            "merchant.store": [
                ColumnInfo(name: "store_id", ordinalPosition: 1, dataType: "uuid", isNullable: false, defaultValue: nil, isPrimaryKey: true, characterMaxLength: nil)
            ]
        ]

        // Table suggestion
        let (_, _, tblItems) = SQLAutocompleteService.suggestions(
            for: "SELECT * FROM us",
            at: 16,
            tables: sampleTables,
            columns: sampleColumns,
            schemas: []
        )
        XCTAssertTrue(tblItems.contains(where: { $0.text == "users" && $0.kind == .table }))

        // Column suggestion
        let (_, _, colItems) = SQLAutocompleteService.suggestions(
            for: "SELECT em",
            at: 9,
            tables: sampleTables,
            columns: sampleColumns,
            schemas: []
        )
        XCTAssertTrue(colItems.contains(where: { $0.text == "email" && $0.kind == .column }))

        // Scoped column suggestion: users. keeps "users." prefix
        let (_, _, scopedItems) = SQLAutocompleteService.suggestions(
            for: "SELECT users.",
            at: 13,
            tables: sampleTables,
            columns: sampleColumns,
            schemas: []
        )
        XCTAssertTrue(scopedItems.contains(where: { $0.insertText == "users.email" && $0.kind == .column }))

        // Scoped schema.table suggestion: merchant.st keeps "merchant." schema prefix
        let schemaQuery = "SELECT * FROM merchant.st"
        let (_, schemaReplaceRange, schemaTableItems) = SQLAutocompleteService.suggestions(
            for: schemaQuery,
            at: schemaQuery.count,
            tables: sampleTables,
            columns: sampleColumns,
            schemas: []
        )
        guard let storeItem = schemaTableItems.first(where: { $0.kind == .table }) else {
            XCTFail("Expected merchant.store table suggestion")
            return
        }
        XCTAssertEqual(storeItem.text, "merchant.store")
        XCTAssertEqual(storeItem.insertText, "merchant.store")
        let replaced = (schemaQuery as NSString).replacingCharacters(in: schemaReplaceRange, with: storeItem.insertText)
        XCTAssertEqual(replaced, "SELECT * FROM merchant.store")

        // Scoped schema.table.column suggestion: merchant.store.st keeps "merchant.store." prefix
        let threePartQuery = "SELECT merchant.store.st"
        let (_, _, threePartItems) = SQLAutocompleteService.suggestions(
            for: threePartQuery,
            at: threePartQuery.count,
            tables: sampleTables,
            columns: sampleColumns,
            schemas: []
        )
        XCTAssertTrue(threePartItems.contains(where: { $0.insertText == "merchant.store.store_id" && $0.kind == .column }))
    }

    func testContextualChips() {
        let sampleTables: [String: [TableInfo]] = [
            "public": [
                TableInfo(schema: "public", name: "users", oid: 101, estimatedRowCount: 50, tableType: .table)
            ]
        ]

        // Start of query
        let startChips = SQLAutocompleteService.contextualChips(
            for: "",
            at: 0,
            tables: sampleTables,
            columns: [:]
        )
        XCTAssertTrue(startChips.contains(where: { $0.text.contains("SELECT") }))

        // After SELECT
        let selectChips = SQLAutocompleteService.contextualChips(
            for: "SELECT ",
            at: 7,
            tables: sampleTables,
            columns: [:]
        )
        XCTAssertTrue(selectChips.contains(where: { $0.text == "*" }))
        XCTAssertTrue(selectChips.contains(where: { $0.text == "COUNT(*)" }))

        // After FROM
        let fromChips = SQLAutocompleteService.contextualChips(
            for: "SELECT * FROM ",
            at: 14,
            tables: sampleTables,
            columns: [:]
        )
        XCTAssertTrue(fromChips.contains(where: { $0.text == "users" }))
    }
}
