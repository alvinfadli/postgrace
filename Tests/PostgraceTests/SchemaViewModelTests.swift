import XCTest
@testable import Postgrace

final class SchemaViewModelTests: XCTestCase {

    var mockDriver: MockDatabaseDriver!
    var postgresService: PostgresService!
    var schemaService: SchemaService!
    var vm: SchemaViewModel!

    override func setUp() async throws {
        mockDriver = MockDatabaseDriver()
        postgresService = PostgresService()
        await postgresService.setActiveDriverForTesting(mockDriver)
        schemaService = SchemaService(postgresService: postgresService)
        vm = SchemaViewModel(schemaService: schemaService)
    }

    // MARK: - Privilege & Eligibility Tests

    func testUserPrivilegeEvaluationAndCanCreateDatabase() async {
        // Default nil privileges allows creation
        XCTAssertTrue(vm.canCreateDatabase)

        // Read-only user without CREATEDB or SUPERUSER
        vm.userPrivileges = UserPrivilegeInfo(
            username: "readonly_user",
            isSuperuser: false,
            canCreateDb: false
        )
        XCTAssertFalse(vm.canCreateDatabase)

        // User with CREATEDB role
        vm.userPrivileges = UserPrivilegeInfo(
            username: "dev_user",
            isSuperuser: false,
            canCreateDb: true
        )
        XCTAssertTrue(vm.canCreateDatabase)

        // Superuser
        vm.userPrivileges = UserPrivilegeInfo(
            username: "postgres",
            isSuperuser: true,
            canCreateDb: false
        )
        XCTAssertTrue(vm.canCreateDatabase)
    }

    func testCanDropDatabaseRules() {
        let activeDb = DatabaseInfo(name: "app_prod", oid: 100, owner: "postgres", isOwner: true)
        let otherDb = DatabaseInfo(name: "app_dev", oid: 101, owner: "developer", isOwner: false)
        let myOwnedDb = DatabaseInfo(name: "app_scratch", oid: 102, owner: "alice", isOwner: true)

        // Cannot drop the currently active database
        let activeCheck = vm.canDropDatabase(activeDb, currentDatabase: "app_prod")
        XCTAssertFalse(activeCheck.allowed)
        XCTAssertTrue(activeCheck.reason?.contains("Cannot drop active database") ?? false)

        // Non-owner, non-superuser cannot drop
        vm.userPrivileges = UserPrivilegeInfo(username: "alice", isSuperuser: false, canCreateDb: true)
        let nonOwnerCheck = vm.canDropDatabase(otherDb, currentDatabase: "postgres")
        XCTAssertFalse(nonOwnerCheck.allowed)
        XCTAssertTrue(nonOwnerCheck.reason?.contains("Only the database owner") ?? false)

        // Owner can drop
        let ownerCheck = vm.canDropDatabase(myOwnedDb, currentDatabase: "postgres")
        XCTAssertTrue(ownerCheck.allowed)
        XCTAssertNil(ownerCheck.reason)

        // Superuser can drop any non-active database
        vm.userPrivileges = UserPrivilegeInfo(username: "superadmin", isSuperuser: true, canCreateDb: true)
        let superCheck = vm.canDropDatabase(otherDb, currentDatabase: "postgres")
        XCTAssertTrue(superCheck.allowed)
    }

    // MARK: - Row Count Management

    func testAccurateRowCountManagement() async {
        let table = TableInfo(schema: "public", name: "users", oid: 50, estimatedRowCount: 1000, tableType: .table)

        // Initially returns estimated row count
        XCTAssertEqual(vm.accurateRowCount(for: table), 1000)

        // Set row count in tableDetails
        vm.tableDetails["public"] = [
            TableDetail(
                schema: "public",
                name: "users",
                oid: 50,
                tableType: .table,
                rowCount: 1250,
                totalSize: "1 MB",
                indexSize: "100 KB",
                columnCount: 5,
                isOwner: true
            )
        ]
        XCTAssertEqual(vm.accurateRowCount(for: table), 1250)

        // Manually override with exact count
        vm.setAccurateRowCount(schema: "public", table: "users", count: 1284)
        XCTAssertEqual(vm.accurateRowCount(for: table), 1284)
        XCTAssertEqual(vm.tableDetails["public"]?.first?.rowCount, 1284)

        // Load accurate count using service
        await mockDriver.setRowCountForTable(["public.users": 1500])
        let loaded = await vm.loadAccurateRowCount(schema: "public", table: "users", forceRefresh: true)
        XCTAssertEqual(loaded, 1500)
        XCTAssertEqual(vm.accurateRowCount(for: table), 1500)
    }

    // MARK: - Schema & Table CRUD Method Coverage

    func testSchemaCRUDLifecycle() async throws {
        // Create Schema
        try await vm.createSchema(name: "reporting", owner: "analytics_role")
        let queries = await mockDriver.executedQueries
        XCTAssertTrue(queries.contains { $0.contains("CREATE SCHEMA \"reporting\"") })

        // Rename Schema
        try await vm.renameSchema(oldName: "reporting", newName: "bi_reports")
        let renameQueries = await mockDriver.executedQueries
        XCTAssertTrue(renameQueries.contains { $0.contains("ALTER SCHEMA \"reporting\" RENAME TO \"bi_reports\"") })

        // Drop Schema
        try await vm.dropSchema(name: "bi_reports", cascade: true)
        let dropQueries = await mockDriver.executedQueries
        XCTAssertTrue(dropQueries.contains { $0.contains("DROP SCHEMA \"bi_reports\" CASCADE") })
    }

    func testTableCRUDLifecycle() async throws {
        // Create Table
        let cols = [
            NewColumnDefinition(name: "id", dataType: "serial", isPrimaryKey: true, isNullable: false),
            NewColumnDefinition(name: "name", dataType: "text", isPrimaryKey: false, isNullable: true)
        ]
        try await vm.createTable(schema: "public", name: "widgets", columns: cols)
        let createQueries = await mockDriver.executedQueries
        XCTAssertTrue(createQueries.contains { $0.contains("CREATE TABLE \"public\".\"widgets\"") })

        // Rename Table
        try await vm.renameTable(schema: "public", oldName: "widgets", newName: "gadgets")
        let renameQueries = await mockDriver.executedQueries
        XCTAssertTrue(renameQueries.contains { $0.contains("RENAME TO \"gadgets\"") })

        // Truncate Table
        try await vm.truncateTable(schema: "public", name: "gadgets")
        let truncQueries = await mockDriver.executedQueries
        XCTAssertTrue(truncQueries.contains { $0.contains("TRUNCATE TABLE \"public\".\"gadgets\"") })

        // Drop Table
        try await vm.dropTable(schema: "public", name: "gadgets", cascade: false)
        let dropQueries = await mockDriver.executedQueries
        XCTAssertTrue(dropQueries.contains { $0.contains("DROP TABLE \"public\".\"gadgets\"") })
    }

    func testCreateAndDropDatabaseGuards() async throws {
        // Prevent creation if lacks privilege
        vm.userPrivileges = UserPrivilegeInfo(username: "guest", isSuperuser: false, canCreateDb: false)
        do {
            try await vm.createDatabase(name: "forbidden_db")
            XCTFail("Should fail without privileges")
        } catch {
            XCTAssertNotNil(vm.crudError)
        }

        // Prevent dropping active database
        do {
            try await vm.dropDatabase(name: "testdb", currentDatabase: "testdb")
            XCTFail("Should fail dropping active database")
        } catch {
            XCTAssertNotNil(vm.crudError)
            XCTAssertTrue(vm.crudError?.contains("Cannot drop active database") ?? false)
        }
    }

    func testClearResetsAllState() {
        vm.schemas = [SchemaInfo(name: "public", oid: 1)]
        vm.tables["public"] = [TableInfo(schema: "public", name: "t", oid: 2, estimatedRowCount: 0, tableType: .table)]
        vm.columns["public.t"] = [ColumnInfo(name: "id", ordinalPosition: 1, dataType: "int", isNullable: false, defaultValue: nil, isPrimaryKey: true, characterMaxLength: nil)]
        vm.accurateRowCounts["public.t"] = 42
        vm.userPrivileges = UserPrivilegeInfo(username: "admin", isSuperuser: true, canCreateDb: true)
        vm.crudError = "Some error"

        vm.clear()

        XCTAssertTrue(vm.schemas.isEmpty)
        XCTAssertTrue(vm.tables.isEmpty)
        XCTAssertTrue(vm.columns.isEmpty)
        XCTAssertTrue(vm.accurateRowCounts.isEmpty)
        XCTAssertNil(vm.userPrivileges)
        XCTAssertNil(vm.crudError)
    }
}

// MARK: - Mock Driver Helper

extension MockDatabaseDriver {
    func setRowCountForTable(_ dict: [String: Int64]) {
        self.rowCountForTable = dict
    }
}
