import XCTest
@testable import Postgrace

final class ImportViewModelTests: XCTestCase {

    var mockDriver: MockDatabaseDriver!
    var postgresService: PostgresService!
    var tempDirectory: URL!

    override func setUp() async throws {
        mockDriver = MockDatabaseDriver()
        postgresService = PostgresService()
        await postgresService.setActiveDriverForTesting(mockDriver)
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("import_vm_tests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func testSetupConfigurationAutoMapsColumns() throws {
        let vm = ImportViewModel(postgresService: postgresService)
        let csvURL = tempDirectory.appendingPathComponent("users.csv")
        let csvContent = """
        User_Name,EMAIL_ADDRESS,unknown_header
        alice,alice@example.com,foo
        bob,bob@example.com,bar
        """
        try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)

        // Set target table columns on view model via startTableImport setup
        vm.setupConfiguration(for: csvURL, scope: .table(schema: "public", table: "users"))

        guard let config = vm.configuration else {
            XCTFail("Configuration must be created")
            return
        }

        XCTAssertEqual(config.sourceType, .csv)
        XCTAssertEqual(config.columnMappings.count, 3)

        // Test with pre-existing target columns
        let vmWithColumns = ImportViewModel(postgresService: postgresService)
        vmWithColumns.setupConfiguration(for: csvURL, scope: .table(schema: "public", table: "users"), tableColumns: ["username", "email_address", "created_at"])

        let mappings = vmWithColumns.configuration?.columnMappings ?? []
        XCTAssertEqual(mappings.count, 3)

        // "User_Name" should map to "username" (case-insensitive + underscore stripped)
        let nameMapping = mappings.first { $0.sourceColumn == "User_Name" }
        XCTAssertEqual(nameMapping?.targetColumn, "username")

        // "EMAIL_ADDRESS" should map to "email_address"
        let emailMapping = mappings.first { $0.sourceColumn == "EMAIL_ADDRESS" }
        XCTAssertEqual(emailMapping?.targetColumn, "email_address")

        // "unknown_header" has no match
        let unknownMapping = mappings.first { $0.sourceColumn == "unknown_header" }
        XCTAssertNil(unknownMapping?.targetColumn)
    }

    func testSetupConfigurationWithJSON() throws {
        let vm = ImportViewModel(postgresService: postgresService)
        let jsonURL = tempDirectory.appendingPathComponent("products.json")
        let jsonContent = """
        [
          {"sku": "A100", "price": "9.99"},
          {"sku": "B200", "price": "14.99"}
        ]
        """
        try jsonContent.write(to: jsonURL, atomically: true, encoding: .utf8)

        vm.setupConfiguration(for: jsonURL, scope: .table(schema: "public", table: "products"), tableColumns: ["sku", "price"])

        XCTAssertEqual(vm.configuration?.sourceType, .json)
        let mappings = vm.configuration?.columnMappings ?? []
        XCTAssertEqual(mappings.count, 2)
        XCTAssertTrue(mappings.contains { $0.sourceColumn == "sku" && $0.targetColumn == "sku" })
        XCTAssertTrue(mappings.contains { $0.sourceColumn == "price" && $0.targetColumn == "price" })
    }

    func testPerformImportExecutesSuccessfully() async throws {
        let vm = ImportViewModel(postgresService: postgresService)
        let csvURL = tempDirectory.appendingPathComponent("quick.csv")
        try "name\nAlpha\nBeta".write(to: csvURL, atomically: true, encoding: .utf8)

        var config = ImportConfiguration(
            targetScope: .table(schema: "public", table: "tbl"),
            sourceURL: csvURL,
            sourceType: .csv
        )
        config.columnMappings = [ColumnMappingItem(sourceColumn: "name", targetColumn: "name")]
        vm.configuration = config

        vm.performImport()

        // Wait for async task to complete
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(vm.isImporting)
        XCTAssertNil(vm.errorMessage)
        let inserts = await mockDriver.executedBatchInserts
        XCTAssertEqual(inserts.count, 1)
        XCTAssertEqual(inserts.first?.rows.count, 2)
    }

    func testPerformImportErrorPopulatesErrorMessage() async throws {
        let vm = ImportViewModel(postgresService: postgresService)
        let csvURL = tempDirectory.appendingPathComponent("fail.csv")
        try "name\nAlpha".write(to: csvURL, atomically: true, encoding: .utf8)

        var config = ImportConfiguration(
            targetScope: .table(schema: "public", table: "tbl"),
            sourceURL: csvURL,
            sourceType: .csv
        )
        config.columnMappings = [ColumnMappingItem(sourceColumn: "name", targetColumn: "name")]
        vm.configuration = config

        await mockDriver.setShouldFailBatchInsert(true)

        vm.performImport()

        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(vm.isImporting)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testCancelImportAndCloseSheet() {
        let vm = ImportViewModel(postgresService: postgresService)
        vm.isShowingSheet = true
        vm.isImporting = true

        vm.cancelImport()
        XCTAssertFalse(vm.isImporting)
        XCTAssertEqual(vm.progress.status, .cancelled)

        vm.closeSheet()
        XCTAssertFalse(vm.isShowingSheet)
    }
}
