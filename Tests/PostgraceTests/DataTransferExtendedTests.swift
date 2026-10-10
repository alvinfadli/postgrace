import XCTest
@testable import Postgrace

final class DataTransferExtendedTests: XCTestCase {

    var tempDirectory: URL!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("dt_ext_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - NDJSON Tests

    func testNDJSONInspectAndBatchStreaming() async throws {
        let ndjsonURL = tempDirectory.appendingPathComponent("sample.ndjson")
        let content = """
        {"id": "1", "name": "Alpha", "active": "true"}
        {"id": "2", "name": "Beta", "active": "false"}
        {"id": "3", "name": "Gamma", "active": "true"}
        """
        try content.write(to: ndjsonURL, atomically: true, encoding: .utf8)

        // Test inspect
        let (headers, previews) = try JSONHandler.inspect(url: ndjsonURL, maxPreviewRows: 2)
        XCTAssertEqual(headers.count, 3)
        XCTAssertTrue(headers.contains("id"))
        XCTAssertTrue(headers.contains("name"))
        XCTAssertEqual(previews.count, 2)
        XCTAssertEqual(previews[0]["id"], "1")
        XCTAssertEqual(previews[1]["id"], "2")

        // Test parse in batches
        var collected: [[[String: String]]] = []
        let count = try await JSONHandler.parseInBatches(url: ndjsonURL, batchSize: 2) { batch in
            collected.append(batch)
        }

        XCTAssertEqual(count, 3)
        XCTAssertEqual(collected.count, 2)
        XCTAssertEqual(collected[0].count, 2)
        XCTAssertEqual(collected[1].count, 1)
        XCTAssertEqual(collected[0][0]["name"], "Alpha")
        XCTAssertEqual(collected[1][0]["name"], "Gamma")
    }

    // MARK: - FilterRule Comprehensive SQL Expression Tests

    func testFilterRuleAllOperators() {
        // isNull and isNotNull
        let nullRule = FilterRule(column: "deleted_at", op: .isNull)
        XCTAssertEqual(nullRule.toSQLExpression(), "\"deleted_at\" IS NULL")

        let notNullRule = FilterRule(column: "email", op: .isNotNull)
        XCTAssertEqual(notNullRule.toSQLExpression(), "\"email\" IS NOT NULL")

        // contains, startsWith, endsWith
        let containsRule = FilterRule(column: "description", op: .contains, value: "100%_deal")
        XCTAssertEqual(containsRule.toSQLExpression(), "\"description\"::text ILIKE '%100\\%\\_deal%'")

        let startsRule = FilterRule(column: "code", op: .startsWith, value: "PROMO")
        XCTAssertEqual(startsRule.toSQLExpression(), "\"code\"::text ILIKE 'PROMO%'")

        let endsRule = FilterRule(column: "domain", op: .endsWith, value: ".org")
        XCTAssertEqual(endsRule.toSQLExpression(), "\"domain\"::text ILIKE '%.org'")

        // Boolean values
        let boolTrueRule = FilterRule(column: "is_active", op: .equals, value: "true")
        XCTAssertEqual(boolTrueRule.toSQLExpression(), "\"is_active\" = true")

        let boolFalseRule = FilterRule(column: "is_archived", op: .notEquals, value: "FALSE")
        XCTAssertEqual(boolFalseRule.toSQLExpression(), "\"is_archived\" != false")

        // Numeric values
        let numEqRule = FilterRule(column: "score", op: .greaterThan, value: "42.5")
        XCTAssertEqual(numEqRule.toSQLExpression(), "\"score\" > 42.5")

        let numZeroRule = FilterRule(column: "count", op: .equals, value: "0")
        XCTAssertEqual(numZeroRule.toSQLExpression(), "\"count\" = 0")

        let numGteRule = FilterRule(column: "age", op: .greaterThanOrEqual, value: "18")
        XCTAssertEqual(numGteRule.toSQLExpression(), "\"age\" >= 18")

        let numLteRule = FilterRule(column: "stock", op: .lessThanOrEqual, value: "5")
        XCTAssertEqual(numLteRule.toSQLExpression(), "\"stock\" <= 5")

        // String literals with SQL quotes
        let strRule = FilterRule(column: "company", op: .equals, value: "O'Reilly & Sons")
        XCTAssertEqual(strRule.toSQLExpression(), "\"company\" = 'O''Reilly & Sons'")

        // Empty column or value handling
        let emptyCol = FilterRule(column: "", op: .equals, value: "test")
        XCTAssertNil(emptyCol.toSQLExpression())

        let emptyVal = FilterRule(column: "name", op: .equals, value: "   ")
        XCTAssertNil(emptyVal.toSQLExpression())
    }

    func testFilterOperatorAndConjunctionMetadata() {
        for op in FilterOperator.allCases {
            XCTAssertFalse(op.id.isEmpty)
            XCTAssertFalse(op.label.isEmpty)
            if op == .isNull || op == .isNotNull {
                XCTAssertFalse(op.requiresValue)
            } else {
                XCTAssertTrue(op.requiresValue)
            }
        }

        XCTAssertEqual(FilterConjunction.and.label, "Match ALL (AND)")
        XCTAssertEqual(FilterConjunction.or.label, "Match ANY (OR)")
    }

    // MARK: - Import Configuration Detection Tests

    func testImportSourceTypeDetection() {
        XCTAssertEqual(ImportSourceType.detect(from: URL(fileURLWithPath: "/tmp/data.csv")), .csv)
        XCTAssertEqual(ImportSourceType.detect(from: URL(fileURLWithPath: "/tmp/data.tsv")), .csv)
        XCTAssertEqual(ImportSourceType.detect(from: URL(fileURLWithPath: "/tmp/data.txt")), .csv)
        XCTAssertEqual(ImportSourceType.detect(from: URL(fileURLWithPath: "/tmp/data.json")), .json)
        XCTAssertEqual(ImportSourceType.detect(from: URL(fileURLWithPath: "/tmp/data.ndjson")), .json)
        XCTAssertEqual(ImportSourceType.detect(from: URL(fileURLWithPath: "/tmp/data.jsonl")), .json)
        XCTAssertEqual(ImportSourceType.detect(from: URL(fileURLWithPath: "/tmp/data.sql")), .sql)
        XCTAssertEqual(ImportSourceType.detect(from: URL(fileURLWithPath: "/tmp/data.dump")), .customDump)
        XCTAssertEqual(ImportSourceType.detect(from: URL(fileURLWithPath: "/tmp/data.tar")), .customDump)
        XCTAssertEqual(ImportSourceType.detect(from: URL(fileURLWithPath: "/tmp/data.pgdump")), .customDump)
        XCTAssertEqual(ImportSourceType.detect(from: URL(fileURLWithPath: "/tmp/data.unknown")), .csv)

        for type in ImportSourceType.allCases {
            XCTAssertFalse(type.id.isEmpty)
        }
        for policy in ImportConflictPolicy.allCases {
            XCTAssertFalse(policy.id.isEmpty)
        }
    }

    // MARK: - DatabaseSchema Models Properties Tests

    func testDatabaseSchemaModels() {
        let db = DatabaseInfo(name: "testdb", oid: 1, owner: "admin", encoding: "UTF8", size: "10 MB", isOwner: true)
        XCTAssertEqual(db.id, 1)
        XCTAssertEqual(db.name, "testdb")
        XCTAssertTrue(db.isOwner)

        let schema = SchemaInfo(name: "custom_schema", oid: 2)
        XCTAssertEqual(schema.id, 2)
        XCTAssertEqual(schema.name, "custom_schema")

        let table = TableInfo(schema: "custom_schema", name: "orders", oid: 3, estimatedRowCount: 500, tableType: .table)
        XCTAssertEqual(table.id, 3)
        XCTAssertEqual(table.tableType, .table)

        let col = ColumnInfo(name: "created_at", ordinalPosition: 3, dataType: "timestamp", isNullable: false, defaultValue: "NOW()", isPrimaryKey: false, characterMaxLength: nil)
        XCTAssertEqual(col.id, "created_at_3")

        let idx = IndexInfo(name: "idx_orders_id", tableName: "orders", isUnique: true, isPrimary: true, columns: ["id"])
        XCTAssertEqual(idx.id, "idx_orders_id")

        let fn = FunctionInfo(schema: "public", name: "calc_tax", oid: 4, returnType: "numeric", argumentTypes: "numeric", language: "plpgsql")
        XCTAssertEqual(fn.id, 4)

        let ident = IdentifiableString(value: "schema_selection")
        XCTAssertEqual(ident.id, "schema_selection")

        let colDef = NewColumnDefinition(name: "price", dataType: "numeric(10,2)", isPrimaryKey: false, isNullable: true, defaultValue: "0.00")
        XCTAssertEqual(colDef.name, "price")

        // User Privilege descriptions
        let superuser = UserPrivilegeInfo(username: "root", isSuperuser: true, canCreateDb: true)
        XCTAssertEqual(superuser.privilegeLevelDescription, "Superuser")

        let rwUser = UserPrivilegeInfo(
            username: "writer",
            isSuperuser: false,
            canCreateDb: false,
            schemaPrivileges: ["public": SchemaPrivilege(canCreate: true, canUsage: true)]
        )
        XCTAssertEqual(rwUser.privilegeLevelDescription, "Read-Write")

        let roUser = UserPrivilegeInfo(
            username: "reader",
            isSuperuser: false,
            canCreateDb: false,
            schemaPrivileges: ["public": SchemaPrivilege(canCreate: false, canUsage: true)]
        )
        XCTAssertEqual(roUser.privilegeLevelDescription, "Read-Only")
    }
}
