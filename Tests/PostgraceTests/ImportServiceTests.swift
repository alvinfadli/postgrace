import XCTest
@testable import Postgrace

final class ImportServiceTests: XCTestCase {

    var mockDriver: MockDatabaseDriver!
    var postgresService: PostgresService!
    var importService: ImportService!
    var tempDirectory: URL!

    override func setUp() async throws {
        mockDriver = MockDatabaseDriver()
        postgresService = PostgresService()
        await postgresService.setActiveDriverForTesting(mockDriver)
        importService = ImportService(postgresService: postgresService)
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("import_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - CSV Import Tests

    func testImportTableFromCSVWithMapping() async throws {
        let csvURL = tempDirectory.appendingPathComponent("users.csv")
        let csvContent = """
        src_id,src_name,src_role
        101,Alice,Admin
        102,Bob,User
        """
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)

        var config = ImportConfiguration(
            targetScope: .table(schema: "public", table: "app_users"),
            sourceURL: csvURL,
            sourceType: .csv
        )
        config.columnMappings = [
            ColumnMappingItem(sourceColumn: "src_id", targetColumn: "id"),
            ColumnMappingItem(sourceColumn: "src_name", targetColumn: "username")
        ]
        config.batchSize = 10

        var receivedProgress: [DataTransferProgress] = []
        try await importService.importData(config: config) { progress in
            receivedProgress.append(progress)
        }

        let inserts = await mockDriver.executedBatchInserts
        XCTAssertEqual(inserts.count, 1)
        let batch = inserts.first!
        XCTAssertEqual(batch.schema, "public")
        XCTAssertEqual(batch.table, "app_users")
        XCTAssertEqual(batch.columns, ["id", "username"])
        XCTAssertEqual(batch.rows.count, 2)
        XCTAssertEqual(batch.rows[0], ["101", "Alice"])
        XCTAssertEqual(batch.rows[1], ["102", "Bob"])

        guard case .completed = receivedProgress.last?.status else {
            XCTFail("Expected import to complete successfully")
            return
        }
    }

    func testImportTableFailsWhenNoColumnsMapped() async throws {
        let csvURL = tempDirectory.appendingPathComponent("empty_map.csv")
        try "col1,col2\n1,2".write(to: csvURL, atomically: true, encoding: .utf8)

        var config = ImportConfiguration(
            targetScope: .table(schema: "public", table: "dest"),
            sourceURL: csvURL
        )
        config.columnMappings = [
            ColumnMappingItem(sourceColumn: "col1", targetColumn: nil),
            ColumnMappingItem(sourceColumn: "col2", targetColumn: "")
        ]

        do {
            try await importService.importData(config: config) { _ in }
            XCTFail("Should throw error when no columns are mapped")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("No columns were mapped"))
        }
    }

    // MARK: - JSON Import Tests

    func testImportTableFromJSONBatch() async throws {
        let jsonURL = tempDirectory.appendingPathComponent("records.json")
        let jsonContent = """
        [
          {"uid": "u1", "email": "alice@corp.com"},
          {"uid": "u2", "email": "bob@corp.com"}
        ]
        """
        try jsonContent.write(to: jsonURL, atomically: true, encoding: .utf8)

        var config = ImportConfiguration(
            targetScope: .table(schema: "public", table: "accounts"),
            sourceURL: jsonURL,
            sourceType: .json
        )
        config.columnMappings = [
            ColumnMappingItem(sourceColumn: "uid", targetColumn: "user_id"),
            ColumnMappingItem(sourceColumn: "email", targetColumn: "email_address")
        ]

        try await importService.importData(config: config) { _ in }

        let inserts = await mockDriver.executedBatchInserts
        XCTAssertEqual(inserts.count, 1)
        let batch = inserts.first!
        XCTAssertEqual(batch.columns, ["user_id", "email_address"])
        XCTAssertEqual(batch.rows.count, 2)
        XCTAssertEqual(batch.rows[0], ["u1", "alice@corp.com"])
        XCTAssertEqual(batch.rows[1], ["u2", "bob@corp.com"])
    }

    // MARK: - SQL Script Import Tests

    func testImportTableFromSQLScript() async throws {
        let sqlURL = tempDirectory.appendingPathComponent("script.sql")
        let sqlContent = """
        INSERT INTO test_tbl VALUES (1, 'val1');
        INSERT INTO test_tbl VALUES (2, 'val2');
        """
        try sqlContent.write(to: sqlURL, atomically: true, encoding: .utf8)

        var config = ImportConfiguration(
            targetScope: .table(schema: "public", table: "test_tbl"),
            sourceURL: sqlURL,
            sourceType: .sql
        )
        config.columnMappings = [ColumnMappingItem(sourceColumn: "dummy", targetColumn: "dummy")]

        try await importService.importData(config: config) { _ in }

        let rawStatements = await mockDriver.executedRawStatements
        XCTAssertEqual(rawStatements.count, 2)
        XCTAssertTrue(rawStatements[0].contains("INSERT INTO test_tbl VALUES (1"))
        XCTAssertTrue(rawStatements[1].contains("INSERT INTO test_tbl VALUES (2"))
    }

    // MARK: - Error Handling & Conflict Policies

    func testImportTableWithSkipErrorsPolicy() async throws {
        let csvURL = tempDirectory.appendingPathComponent("data.csv")
        try "col\nval1".write(to: csvURL, atomically: true, encoding: .utf8)

        var config = ImportConfiguration(
            targetScope: .table(schema: "public", table: "t"),
            sourceURL: csvURL,
            sourceType: .csv
        )
        config.columnMappings = [ColumnMappingItem(sourceColumn: "col", targetColumn: "col")]
        config.conflictPolicy = .skipErrors

        await mockDriver.setShouldFailBatchInsert(true)

        var lastProgress: DataTransferProgress?
        try await importService.importData(config: config) { progress in
            lastProgress = progress
        }

        XCTAssertFalse(lastProgress?.errorLog.isEmpty ?? true)
        XCTAssertTrue(lastProgress?.errorLog.first?.contains("Batch error:") ?? false)
    }

    func testImportTableCustomDumpThrowsInvalidScopeError() async throws {
        let dumpURL = tempDirectory.appendingPathComponent("backup.dump")
        try Data([0x50, 0x47, 0x44, 0x4D, 0x50]).write(to: dumpURL)

        var config = ImportConfiguration(
            targetScope: .table(schema: "public", table: "tbl"),
            sourceURL: dumpURL,
            sourceType: .customDump
        )
        config.columnMappings = [ColumnMappingItem(sourceColumn: "a", targetColumn: "a")]

        do {
            try await importService.importData(config: config) { _ in }
            XCTFail("Custom dump into table must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Binary .dump archives must be restored at the Database level"))
        }
    }

    func testImportDatabaseWithCSVThrowsError() async throws {
        let csvURL = tempDirectory.appendingPathComponent("db.csv")
        try "a,b\n1,2".write(to: csvURL, atomically: true, encoding: .utf8)

        let config = ImportConfiguration(
            targetScope: .database(name: "prod_db"),
            sourceURL: csvURL,
            sourceType: .csv
        )

        do {
            try await importService.importData(config: config) { _ in }
            XCTFail("CSV to database must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("CSV and JSON files must be imported into a specific table"))
        }
    }
}

// MARK: - Mock Driver Helper

extension MockDatabaseDriver {
    func setShouldFailBatchInsert(_ fail: Bool) {
        self.shouldFailBatchInsert = fail
    }
}
