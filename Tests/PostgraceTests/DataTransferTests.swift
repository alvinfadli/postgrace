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
}
