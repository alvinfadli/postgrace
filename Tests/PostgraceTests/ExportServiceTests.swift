import XCTest
@testable import Postgrace

final class ExportServiceTests: XCTestCase {

    var mockDriver: MockDatabaseDriver!
    var postgresService: PostgresService!
    var exportService: ExportService!
    var tempDirectory: URL!

    override func setUp() async throws {
        mockDriver = MockDatabaseDriver()
        postgresService = PostgresService()
        await postgresService.setActiveDriverForTesting(mockDriver)
        exportService = ExportService(postgresService: postgresService)
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("export_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - CSV Export Tests

    func testExportTableToCSVWithHeadersAndBOM() async throws {
        let destURL = tempDirectory.appendingPathComponent("users.csv")
        var config = ExportConfiguration(
            scope: .table(schema: "public", table: "users"),
            format: .csv
        )
        config.csvIncludeHeaders = true
        config.csvIncludeBOM = true
        config.csvDelimiter = ","

        await mockDriver.setStreamedRows([
            (
                [ResultColumn(name: "id", dataTypeOID: 23, dataTypeName: "integer"), ResultColumn(name: "name", dataTypeOID: 25, dataTypeName: "text"), ResultColumn(name: "is_admin", dataTypeOID: 16, dataTypeName: "boolean")],
                [CellValue.int(1), CellValue.string("Alice"), CellValue.bool(true)]
            ),
            (
                [ResultColumn(name: "id", dataTypeOID: 23, dataTypeName: "integer"), ResultColumn(name: "name", dataTypeOID: 25, dataTypeName: "text"), ResultColumn(name: "is_admin", dataTypeOID: 16, dataTypeName: "boolean")],
                [CellValue.int(2), CellValue.string("Bob"), CellValue.bool(false)]
            )
        ])

        var receivedProgress: [DataTransferProgress] = []
        try await exportService.export(config: config, destinationURL: destURL) { progress in
            receivedProgress.append(progress)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
        let fileData = try Data(contentsOf: destURL)
        let fileString = String(data: fileData, encoding: .utf8)!

        // Verify BOM prefix bytes
        XCTAssertTrue(fileData.starts(with: [0xEF, 0xBB, 0xBF]))
        // Verify CSV header
        XCTAssertTrue(fileString.contains("id,name,is_admin\n"))
        // Verify rows
        XCTAssertTrue(fileString.contains("1,Alice,true\n"))
        XCTAssertTrue(fileString.contains("2,Bob,false\n"))

        // Verify progress status
        XCTAssertFalse(receivedProgress.isEmpty)
        guard case .completed = receivedProgress.last?.status else {
            XCTFail("Expected progress to complete successfully")
            return
        }
        XCTAssertEqual(receivedProgress.last?.rowsProcessed, 2)
    }

    func testExportTableToCSVWithoutHeaders() async throws {
        let destURL = tempDirectory.appendingPathComponent("no_headers.csv")
        var config = ExportConfiguration(
            scope: .table(schema: "public", table: "items"),
            format: .csv
        )
        config.csvIncludeHeaders = false
        config.csvIncludeBOM = false

        await mockDriver.setStreamedRows([
            ([ResultColumn(name: "code", dataTypeOID: 25, dataTypeName: "text")], [CellValue.string("XYZ")])
        ])

        try await exportService.export(config: config, destinationURL: destURL) { _ in }

        let content = try String(contentsOf: destURL, encoding: .utf8)
        XCTAssertFalse(content.contains("code\n"))
        XCTAssertEqual(content, "XYZ\n")
    }

    // MARK: - JSON Export Tests

    func testExportTableToJSONStandardArray() async throws {
        let destURL = tempDirectory.appendingPathComponent("data.json")
        var config = ExportConfiguration(
            scope: .table(schema: "public", table: "products"),
            format: .json
        )
        config.jsonFlavor = .array

        await mockDriver.setStreamedRows([
            (
                [ResultColumn(name: "id", dataTypeOID: 23, dataTypeName: "integer"), ResultColumn(name: "price", dataTypeOID: 1700, dataTypeName: "numeric"), ResultColumn(name: "data", dataTypeOID: 114, dataTypeName: "json")],
                [CellValue.int(101), CellValue.double(19.5), CellValue.json("{\"tag\":\"electronics\"}")]
            )
        ])

        try await exportService.export(config: config, destinationURL: destURL) { _ in }

        let content = try String(contentsOf: destURL, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("[\n"))
        XCTAssertTrue(content.hasSuffix("\n]\n"))
        XCTAssertTrue(content.contains("101"))
        XCTAssertTrue(content.contains("19.5"))
    }

    // MARK: - JSON Export Tests (NDJSON)

    func testExportTableToJSONNDJSON() async throws {
        let destURL = tempDirectory.appendingPathComponent("data.ndjson")
        var config = ExportConfiguration(
            scope: .table(schema: "public", table: "logs"),
            format: .json
        )
        config.jsonFlavor = .ndjson

        await mockDriver.setStreamedRows([
            ([ResultColumn(name: "msg", dataTypeOID: 25, dataTypeName: "text")], [CellValue.string("Log 1")]),
            ([ResultColumn(name: "msg", dataTypeOID: 25, dataTypeName: "text")], [CellValue.string("Log 2")])
        ])

        try await exportService.export(config: config, destinationURL: destURL) { _ in }

        let content = try String(contentsOf: destURL, encoding: .utf8)
        XCTAssertFalse(content.contains("["))
        let lines = content.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("Log 1"))
        XCTAssertTrue(lines[1].contains("Log 2"))
    }

    // MARK: - SQL Export Tests

    func testExportTableToSQLDataOnly() async throws {
        let destURL = tempDirectory.appendingPathComponent("export.sql")
        var config = ExportConfiguration(
            scope: .table(schema: "public", table: "members"),
            format: .sql
        )
        config.contentMode = .dataOnly
        config.sqlBatchSize = 1

        await mockDriver.setStreamedRows([
            (
                [ResultColumn(name: "id", dataTypeOID: 23, dataTypeName: "integer"), ResultColumn(name: "bio", dataTypeOID: 25, dataTypeName: "text")],
                [CellValue.int(1), CellValue.string("O'Connor")]
            )
        ])

        try await exportService.export(config: config, destinationURL: destURL) { _ in }

        let content = try String(contentsOf: destURL, encoding: .utf8)
        XCTAssertTrue(content.contains("INSERT INTO \"public\".\"members\""))
        XCTAssertTrue(content.contains("O''Connor"))
    }

    // MARK: - Multiple Tables Export

    func testExportMultipleTables() async throws {
        let destURL = tempDirectory.appendingPathComponent("multi_tables.sql")
        let config = ExportConfiguration(
            scope: .multipleTables(items: [
                ExportTableItem(schema: "public", table: "t1"),
                ExportTableItem(schema: "public", table: "t2")
            ]),
            format: .sql
        )

        try await exportService.export(config: config, destinationURL: destURL) { _ in }

        XCTAssertTrue(FileManager.default.fileExists(atPath: destURL.path))
        let queries = await mockDriver.executedQueries
        XCTAssertTrue(queries.contains { $0.contains("\"t1\"") })
        XCTAssertTrue(queries.contains { $0.contains("\"t2\"") })
    }

    // MARK: - Cancellation & Error Handling

    func testExportCancellationCleansUpFile() async throws {
        let destURL = tempDirectory.appendingPathComponent("cancelled.csv")
        let config = ExportConfiguration(
            scope: .table(schema: "public", table: "big_table"),
            format: .csv
        )

        // Make streamed rows huge so task can be cancelled mid-flight
        let rows = (1...1000).map { i in
            ([ResultColumn(name: "n", dataTypeOID: 23, dataTypeName: "integer")], [CellValue.int(Int64(i))])
        }
        await mockDriver.setStreamedRows(rows)

        let task = Task {
            try await exportService.export(config: config, destinationURL: destURL) { _ in }
        }

        task.cancel()

        do {
            try await task.value
        } catch is CancellationError {
            // Expected
        } catch {
            // CancellationError can be wrapped
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destURL.path), "Cancelled export must delete partial file")
    }

    func testExportFailureSetsFailedStatusAndRemovesFile() async throws {
        let destURL = tempDirectory.appendingPathComponent("failed.csv")
        let config = ExportConfiguration(
            scope: .table(schema: "public", table: "err_table"),
            format: .csv
        )

        await mockDriver.setShouldFailQuery(true)

        var finalProgress: DataTransferProgress?
        do {
            try await exportService.export(config: config, destinationURL: destURL) { progress in
                finalProgress = progress
            }
            XCTFail("Export was expected to fail")
        } catch {
            // Expected
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: destURL.path))
        guard case .failed = finalProgress?.status else {
            XCTFail("Expected progress status to be failed")
            return
        }
    }
}

// MARK: - Mock Driver Thread-Safe Helpers

extension MockDatabaseDriver {
    func setStreamedRows(_ rows: [([ResultColumn], [CellValue])]) {
        self.streamedRows = rows
    }

    func setShouldFailQuery(_ fail: Bool) {
        self.shouldFailQuery = fail
    }
}
