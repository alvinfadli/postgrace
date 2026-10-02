import XCTest
@testable import Postgrace

final class DataTransferTests: XCTestCase {

    // MARK: - CSVHandler Tests

    func testCSVEncodingSimpleRow() {
        let row = ["101", "Alice", "Developer"]
        let csv = CSVHandler.encodeRow(row)
        XCTAssertEqual(csv, "101,Alice,Developer")
    }

    func testCSVEncodingWithSpecialCharacters() {
        let row = ["102", "Bob, Jr.", "Software \"Lead\"", "Line 1\nLine 2"]
        let csv = CSVHandler.encodeRow(row)
        XCTAssertEqual(csv, "102,\"Bob, Jr.\",\"Software \"\"Lead\"\"\",\"Line 1\nLine 2\"")
    }

    func testCSVParsingLineWithQuotesAndCommas() {
        let line = "102,\"Bob, Jr.\",\"Software \"\"Lead\"\"\",\"Line 1\nLine 2\""
        let parsed = CSVHandler.parseLine(line)
        XCTAssertEqual(parsed.count, 4)
        XCTAssertEqual(parsed[0], "102")
        XCTAssertEqual(parsed[1], "Bob, Jr.")
        XCTAssertEqual(parsed[2], "Software \"Lead\"")
        XCTAssertEqual(parsed[3], "Line 1\nLine 2")
    }

    func testCSVBatchStreamingParser() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_import_\(UUID().uuidString).csv")
        let csvContent = """
        id,name,role
        1,Alice,Engineer
        2,Bob,Designer
        3,Charlie,Product
        """
        try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var collectedBatches: [[[String]]] = []
        let total = try await CSVHandler.parseInBatches(url: tempURL, delimiter: ",", hasHeaders: true, batchSize: 2) { batch in
            collectedBatches.append(batch)
        }

        XCTAssertEqual(total, 3)
        XCTAssertEqual(collectedBatches.count, 2)
        XCTAssertEqual(collectedBatches[0].count, 2)
        XCTAssertEqual(collectedBatches[1].count, 1)
        XCTAssertEqual(collectedBatches[0][0], ["1", "Alice", "Engineer"])
        XCTAssertEqual(collectedBatches[1][0], ["3", "Charlie", "Product"])
    }

    // MARK: - JSONHandler Tests

    func testJSONRecordEncoding() {
        let record: [String: Any] = ["id": 42, "name": "Deepmind", "active": true]
        let encoded = JSONHandler.encodeRecord(record)
        XCTAssertNotNil(encoded)
        XCTAssertTrue(encoded!.contains("\"name\":\"Deepmind\"") || encoded!.contains("\"name\": \"Deepmind\""))
        XCTAssertTrue(encoded!.contains("42"))
    }

    func testJSONBatchStreamingParser() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_import_\(UUID().uuidString).json")
        let jsonContent = """
        [
          {"id": "1", "name": "Apple"},
          {"id": "2", "name": "Banana"},
          {"id": "3", "name": "Cherry"}
        ]
        """
        try jsonContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var totalRecords = 0
        let total = try await JSONHandler.parseInBatches(url: tempURL, batchSize: 2) { batch in
            totalRecords += batch.count
        }

        XCTAssertEqual(total, 3)
        XCTAssertEqual(totalRecords, 3)
    }

    // MARK: - Configuration Models Tests

    func testExportConfigurationSuggestedFilenames() {
        let tableConfig = ExportConfiguration(scope: .table(schema: "public", table: "orders"), format: .csv)
        XCTAssertTrue(tableConfig.suggestedFileName.hasPrefix("public_orders_"))
        XCTAssertTrue(tableConfig.suggestedFileName.hasSuffix(".csv"))

        let schemaConfig = ExportConfiguration(scope: .schema(name: "auth"), format: .sql)
        XCTAssertTrue(schemaConfig.suggestedFileName.hasPrefix("schema_auth_"))
        XCTAssertTrue(schemaConfig.suggestedFileName.hasSuffix(".sql"))

        let dbConfig = ExportConfiguration(scope: .database(name: "production"), format: .customDump)
        XCTAssertTrue(dbConfig.suggestedFileName.hasPrefix("db_production_"))
        XCTAssertTrue(dbConfig.suggestedFileName.hasSuffix(".dump"))
    }

    func testImportConfigurationDetection() {
        let csvURL = URL(fileURLWithPath: "/tmp/data.csv")
        XCTAssertEqual(ImportSourceType.detect(from: csvURL), .csv)

        let jsonURL = URL(fileURLWithPath: "/tmp/export.ndjson")
        XCTAssertEqual(ImportSourceType.detect(from: jsonURL), .json)

        let sqlURL = URL(fileURLWithPath: "/tmp/backup.sql")
        XCTAssertEqual(ImportSourceType.detect(from: sqlURL), .sql)

        let dumpURL = URL(fileURLWithPath: "/tmp/mydb.dump")
        XCTAssertEqual(ImportSourceType.detect(from: dumpURL), .customDump)
    }

    // MARK: - Toolchain Detection Tests

    func testPostgresToolchainDiscovery() {
        let toolchain = PostgresToolchainService.shared
        // On macOS with Homebrew or Postgres installed, verify discovery does not crash
        _ = toolchain.isPgDumpAvailable
        _ = toolchain.isPgRestoreAvailable
        _ = toolchain.isPsqlAvailable
    }

    // MARK: - Progress Metrics Tests

    func testDataTransferProgressMetrics() {
        var progress = DataTransferProgress()
        progress.totalRows = 1000
        progress.rowsProcessed = 250
        progress.bytesTransferred = 1048576 // 1 MB
        progress.startTime = Date().addingTimeInterval(-2.0)

        XCTAssertEqual(progress.fractionCompleted, 0.25)
        XCTAssertEqual(progress.formattedBytes, "1.0 MB")
        XCTAssertGreaterThan(progress.throughputRowsPerSecond, 0)
    }

    // MARK: - SQLScriptSplitter Tests

    func testSQLScriptSplitterSimpleStatements() {
        let sql = "SELECT 1; SELECT 2; SELECT 3;"
        let statements = SQLScriptSplitter.split(sql)
        XCTAssertEqual(statements.count, 3)
        XCTAssertEqual(statements[0], "SELECT 1")
        XCTAssertEqual(statements[1], "SELECT 2")
        XCTAssertEqual(statements[2], "SELECT 3")
    }

    func testSQLScriptSplitterPreservesSemicolonsInStrings() {
        let sql = "INSERT INTO users (name) VALUES ('Smith; John'); SELECT 'a;b;c' AS letters;"
        let statements = SQLScriptSplitter.split(sql)
        XCTAssertEqual(statements.count, 2)
        XCTAssertEqual(statements[0], "INSERT INTO users (name) VALUES ('Smith; John')")
        XCTAssertEqual(statements[1], "SELECT 'a;b;c' AS letters")
    }

    func testSQLScriptSplitterHandlesEscapedQuotes() {
        let sql = "INSERT INTO notes (body) VALUES ('It''s a note; with semicolon'); SELECT 1;"
        let statements = SQLScriptSplitter.split(sql)
        XCTAssertEqual(statements.count, 2)
        XCTAssertEqual(statements[0], "INSERT INTO notes (body) VALUES ('It''s a note; with semicolon')")
        XCTAssertEqual(statements[1], "SELECT 1")
    }

    func testSQLScriptSplitterIgnoresComments() {
        let sql = """
        -- First query with semicolon;
        SELECT 1;
        /* Block comment with
           semicolon; in between */
        SELECT 2;
        """
        let statements = SQLScriptSplitter.split(sql)
        XCTAssertEqual(statements.count, 2)
        XCTAssertTrue(statements[0].contains("SELECT 1"))
        XCTAssertTrue(statements[1].contains("SELECT 2"))
    }

    func testSQLScriptSplitterHandlesDollarQuotes() {
        let sql = """
        CREATE OR REPLACE FUNCTION add_item(val text) RETURNS void AS $$
        BEGIN
            INSERT INTO items (name) VALUES (val);
            RETURN;
        END;
        $$ LANGUAGE plpgsql;

        SELECT add_item('test');
        """
        let statements = SQLScriptSplitter.split(sql)
        XCTAssertEqual(statements.count, 2)
        XCTAssertTrue(statements[0].hasPrefix("CREATE OR REPLACE FUNCTION"))
        XCTAssertTrue(statements[0].contains("INSERT INTO items (name) VALUES (val);"))
        XCTAssertEqual(statements[1], "SELECT add_item('test')")
    }

    func testSQLScriptSplitterHandlesTaggedDollarQuotes() {
        let sql = """
        CREATE FUNCTION do_work() RETURNS void AS $body$
        BEGIN
            SELECT ';';
        END;
        $body$ LANGUAGE plpgsql;
        """
        let statements = SQLScriptSplitter.split(sql)
        XCTAssertEqual(statements.count, 1)
        XCTAssertTrue(statements[0].contains("$body$"))
    }

    func testImportConfigurationTreatEmptyAsNull() {
        var config = ImportConfiguration(
            targetScope: .table(schema: "public", table: "users"),
            sourceURL: URL(fileURLWithPath: "/tmp/data.csv"),
            sourceType: .csv
        )
        XCTAssertTrue(config.treatEmptyAsNull)

        config.treatEmptyAsNull = false
        XCTAssertFalse(config.treatEmptyAsNull)
    }
}

