import XCTest
@testable import Postgrace

final class ViewModelTests: XCTestCase {
    
    // MARK: - DataGridViewModel Pagination Tests
    
    func testPaginationCalculations() {
        let postgres = PostgresService()
        let vm = DataGridViewModel(postgresService: postgres)
        vm.pageSize = 50
        
        // 0 rows
        vm.totalRows = 0
        vm.currentPage = 0
        XCTAssertEqual(vm.totalPages, 0)
        XCTAssertFalse(vm.hasNextPage)
        XCTAssertFalse(vm.hasPreviousPage)
        
        // 50 rows (exact 1 page)
        vm.totalRows = 50
        XCTAssertEqual(vm.totalPages, 1)
        XCTAssertFalse(vm.hasNextPage)
        XCTAssertFalse(vm.hasPreviousPage)
        
        // 51 rows (2 pages)
        vm.totalRows = 51
        XCTAssertEqual(vm.totalPages, 2)
        XCTAssertTrue(vm.hasNextPage)
        XCTAssertFalse(vm.hasPreviousPage)
        
        // Advance to page 1
        vm.currentPage = 1
        XCTAssertFalse(vm.hasNextPage)
        XCTAssertTrue(vm.hasPreviousPage)
        
        // 125 rows, page size 50 (3 pages: 50, 50, 25)
        vm.totalRows = 125
        XCTAssertEqual(vm.totalPages, 3)
    }
    
    // MARK: - QueryViewModel Tests
    
    func testQueryViewModelState() {
        let postgres = PostgresService()
        let vm = QueryViewModel(postgresService: postgres)
        
        XCTAssertEqual(vm.queryText, "")
        XCTAssertNil(vm.result)
        XCTAssertFalse(vm.isExecuting)
        XCTAssertNil(vm.executionError)
        XCTAssertTrue(vm.queryHistory.isEmpty)
        
        // Test loading history item
        let historyItem = QueryHistoryItem(
            query: "SELECT * FROM users;",
            duration: 0.042,
            rowCount: 10
        )
        vm.queryHistory.append(historyItem)
        XCTAssertEqual(vm.queryHistory.count, 1)
        
        vm.loadHistoryItem(historyItem)
        XCTAssertEqual(vm.queryText, "SELECT * FROM users;")
        
        // Test clearing result
        vm.result = QueryResult(columns: [], rows: [], executionTime: 0.1, rowsAffected: 0, statusMessage: "OK")
        XCTAssertNotNil(vm.result)
        vm.clearResult()
        XCTAssertNil(vm.result)

        // Test cancelQuery
        vm.queryText = "SELECT pg_sleep(10);"
        vm.isExecuting = true
        XCTAssertTrue(vm.isExecuting)
        vm.cancelQuery()
        XCTAssertFalse(vm.isExecuting)
        XCTAssertEqual(vm.executionError, "Query cancelled by user.")
    }
    
    // MARK: - DatabaseSchema Model Tests
    
    func testTableTypeRawValues() {
        XCTAssertEqual(TableType(rawValue: "BASE TABLE"), .table)
        XCTAssertEqual(TableType(rawValue: "VIEW"), .view)
        XCTAssertEqual(TableType(rawValue: "MATERIALIZED VIEW"), .materializedView)
        XCTAssertEqual(TableType(rawValue: "FOREIGN TABLE"), .foreignTable)
        XCTAssertNil(TableType(rawValue: "UNKNOWN"))
    }
    
    func testColumnInfoIdentifier() {
        let col = ColumnInfo(
            name: "email",
            ordinalPosition: 2,
            dataType: "varchar",
            isNullable: false,
            defaultValue: nil,
            isPrimaryKey: false,
            characterMaxLength: 255
        )
        XCTAssertEqual(col.id, "email_2")
        XCTAssertEqual(col.name, "email")
        XCTAssertFalse(col.isNullable)
        XCTAssertEqual(col.characterMaxLength, 255)
    }
    
    // MARK: - ConnectionViewModel Tests
    
    func testConnectionViewModelManagement() {
        let postgres = PostgresService()
        let keychain = KeychainService()
        let vm = ConnectionViewModel(postgresService: postgres, keychainService: keychain)
        
        let initialCount = vm.savedConnections.count
        let newConn = SavedConnection(
            name: "QA Test Server",
            host: "10.0.0.1",
            port: 5432,
            username: "qa_user",
            database: "qa_db",
            colorTag: .green
        )
        
        // Save new
        vm.saveConnection(newConn, password: "secret_password")
        XCTAssertTrue(vm.savedConnections.contains { $0.id == newConn.id })
        XCTAssertEqual(vm.savedConnections.count, initialCount + 1)
        
        // Update existing
        var updatedConn = newConn
        updatedConn.name = "QA Test Server (Updated)"
        vm.saveConnection(updatedConn, password: "new_password")
        XCTAssertEqual(vm.savedConnections.count, initialCount + 1)
        let found = vm.savedConnections.first { $0.id == newConn.id }
        XCTAssertEqual(found?.name, "QA Test Server (Updated)")
        
        // Test duplicate connection
        let duplicated = vm.duplicateConnection(updatedConn)
        XCTAssertEqual(duplicated.name, "\(updatedConn.name) Copy")
        XCTAssertNotEqual(duplicated.id, updatedConn.id)
        XCTAssertTrue(vm.savedConnections.contains { $0.id == duplicated.id })
        vm.deleteConnection(duplicated)

        // Delete
        vm.deleteConnection(updatedConn)
        XCTAssertFalse(vm.savedConnections.contains { $0.id == newConn.id })
        XCTAssertEqual(vm.savedConnections.count, initialCount)
    }

    func testEditConnectionFormAndSafePasswordRetention() {
        let postgres = PostgresService()
        let keychain = KeychainService()
        let vm = ConnectionViewModel(postgresService: postgres, keychainService: keychain)

        let conn = SavedConnection(
            name: "Production Replica",
            host: "192.168.1.100",
            port: 5433,
            username: "postgres_admin",
            database: "analytics",
            colorTag: .red
        )

        // 1. Initial Save
        vm.saveConnection(conn, password: "super_secure_vault_pass")
        XCTAssertEqual(vm.getStoredPassword(for: conn.id), "super_secure_vault_pass")

        // 2. Open Edit Form
        vm.openEditConnectionForm(for: conn)
        XCTAssertTrue(vm.showingEditForm)
        XCTAssertEqual(vm.connectionToEdit?.id, conn.id)

        // 3. Edit Connection attributes without changing password (empty string passed)
        var edited = conn
        edited.name = "Production Analytics (Renamed)"
        edited.port = 5434
        vm.selectedConnection = conn // Simulate active connection

        vm.saveConnection(edited, password: "")

        // Verify in-place update in savedConnections list
        let found = vm.savedConnections.first { $0.id == conn.id }
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.name, "Production Analytics (Renamed)")
        XCTAssertEqual(found?.port, 5434)

        // Verify active selectedConnection was updated in-place
        XCTAssertEqual(vm.selectedConnection?.name, "Production Analytics (Renamed)")
        XCTAssertEqual(vm.selectedConnection?.port, 5434)

        // Verify password was NOT wiped by empty save
        XCTAssertEqual(vm.getStoredPassword(for: conn.id), "super_secure_vault_pass")

        // 4. Open New Form resets connectionToEdit
        vm.openNewConnectionForm()
        XCTAssertTrue(vm.showingConnectionForm)
        XCTAssertNil(vm.connectionToEdit)

        // Cleanup
        vm.deleteConnection(edited)
    }
    
    // MARK: - WorkspaceTabViewModel Tests
    
    func testWorkspaceTabManagement() {
        let tabVM = WorkspaceTabViewModel()
        
        // Starts with default Query #1 tab
        XCTAssertEqual(tabVM.tabs.count, 1)
        XCTAssertEqual(tabVM.tabs[0].title, "Query #1")
        XCTAssertEqual(tabVM.activeTabId, tabVM.tabs[0].id)
        
        // Open table tab
        tabVM.openTableTab(schema: "public", table: "users")
        XCTAssertEqual(tabVM.tabs.count, 2)
        XCTAssertEqual(tabVM.activeTab?.title, "users")
        
        // Open same table again (should not duplicate, but select it)
        tabVM.openTableTab(schema: "public", table: "users")
        XCTAssertEqual(tabVM.tabs.count, 2)
        
        // Open second table
        tabVM.openTableTab(schema: "public", table: "orders")
        XCTAssertEqual(tabVM.tabs.count, 3)
        XCTAssertEqual(tabVM.activeTab?.title, "orders")
        
        // Open new query tab
        tabVM.openQueryTab()
        XCTAssertEqual(tabVM.tabs.count, 4)
        XCTAssertEqual(tabVM.activeTab?.title, "Query #2")
        
        // Close a tab
        let query2Id = tabVM.activeTabId!
        tabVM.closeTab(id: query2Id)
        XCTAssertEqual(tabVM.tabs.count, 3)
        XCTAssertEqual(tabVM.activeTab?.title, "orders")
        
        // Close other tabs
        let ordersId = tabVM.activeTabId!
        tabVM.closeOtherTabs(id: ordersId)
        XCTAssertEqual(tabVM.tabs.count, 1)
        XCTAssertEqual(tabVM.activeTab?.title, "orders")
    }

    func testWorkspaceTabQueryIsolation() {
        let postgres = PostgresService()
        let tabVM = WorkspaceTabViewModel(postgresService: postgres)

        // Initial default tab: Query #1
        XCTAssertEqual(tabVM.tabs.count, 1)
        let tab1Id = tabVM.tabs[0].id
        let vm1 = tabVM.queryViewModel(for: tab1Id)
        vm1.queryText = "SELECT * FROM tab_one;"

        // Open Query #2
        tabVM.openQueryTab()
        XCTAssertEqual(tabVM.tabs.count, 2)
        let tab2Id = tabVM.tabs[1].id
        let vm2 = tabVM.queryViewModel(for: tab2Id)

        // Verify independent state
        XCTAssertNotEqual(tab1Id, tab2Id)
        XCTAssertTrue(vm1 !== vm2, "Each query tab must have an independent QueryViewModel instance")
        XCTAssertEqual(vm2.queryText, "", "Query #2 buffer must start empty and isolated")

        vm2.queryText = "SELECT * FROM tab_two;"
        XCTAssertEqual(vm1.queryText, "SELECT * FROM tab_one;")
        XCTAssertEqual(vm2.queryText, "SELECT * FROM tab_two;")

        // Close Tab 2 and verify cleanup
        tabVM.closeTab(id: tab2Id)
        XCTAssertEqual(tabVM.tabs.count, 1)
    }

    func testConcurrentQueryExecutionGuard() async {
        let postgres = PostgresService()
        let vm = QueryViewModel(postgresService: postgres)

        vm.queryText = "SELECT 1;"
        vm.isExecuting = true

        // Calling executeQuery while already executing should guard-exit immediately
        await vm.executeQuery()
        XCTAssertTrue(vm.isExecuting)
        XCTAssertNil(vm.result, "Should not overwrite results when locked out by isExecuting")
    }

    func testQuotedIdentifierAndLiteralEscaping() {
        let simpleName = "users"
        XCTAssertEqual(simpleName.pgQuotedIdentifier, "\"users\"")
        XCTAssertEqual(simpleName.pgEscapedLiteral, "users")

        let complexName = "my\"table"
        XCTAssertEqual(complexName.pgQuotedIdentifier, "\"my\"\"table\"")

        let stringLiteral = "it's dangerous; --"
        XCTAssertEqual(stringLiteral.pgEscapedLiteral, "it''s dangerous; --")
    }

    func testDataGridViewModelMultipleFilterRules() {
        let postgres = PostgresService()
        let vm = DataGridViewModel(postgresService: postgres)
        vm.availableColumns = ["id", "username", "status", "created_at"]

        // Initially no filters
        XCTAssertEqual(vm.buildFilterClause(), "")

        // Add first rule (dropdown column & operator & input)
        vm.addFilterRule(defaultColumn: "status")
        XCTAssertEqual(vm.filterRules.count, 1)
        vm.filterRules[0].column = "status"
        vm.filterRules[0].op = .equals
        vm.filterRules[0].value = "active"

        XCTAssertEqual(vm.buildFilterClause(), "\"status\" = 'active'")

        // Add second rule (multiple query conditions)
        vm.addFilterRule(defaultColumn: "username")
        XCTAssertEqual(vm.filterRules.count, 2)
        vm.filterRules[1].column = "username"
        vm.filterRules[1].op = .contains
        vm.filterRules[1].value = "admin"

        // Default conjunction is AND
        XCTAssertEqual(vm.buildFilterClause(), "\"status\" = 'active' AND \"username\"::text ILIKE '%admin%'")

        // Switch conjunction to OR
        vm.filterConjunction = .or
        XCTAssertEqual(vm.buildFilterClause(), "\"status\" = 'active' OR \"username\"::text ILIKE '%admin%'")

        // Add IS NULL rule
        vm.addFilterRule(defaultColumn: "created_at")
        XCTAssertEqual(vm.filterRules.count, 3)
        vm.filterRules[2].column = "created_at"
        vm.filterRules[2].op = .isNotNull

        XCTAssertEqual(vm.buildFilterClause(), "\"status\" = 'active' OR \"username\"::text ILIKE '%admin%' OR \"created_at\" IS NOT NULL")

        // Remove a rule
        let secondId = vm.filterRules[1].id
        vm.removeFilterRule(id: secondId)
        XCTAssertEqual(vm.filterRules.count, 2)
        XCTAssertEqual(vm.buildFilterClause(), "\"status\" = 'active' OR \"created_at\" IS NOT NULL")

        // Clear all filters
        vm.filterRules.removeAll()
        XCTAssertEqual(vm.buildFilterClause(), "")
    }

    // MARK: - Database Role Eligibility & Drop Guard Tests

    func testDatabaseRoleEligibility() {
        let postgres = PostgresService()
        let schemaService = SchemaService(postgresService: postgres)
        let vm = SchemaViewModel(schemaService: schemaService)

        // 1. Superuser privileges
        vm.userPrivileges = UserPrivilegeInfo(username: "postgres", isSuperuser: true, canCreateDb: true)
        XCTAssertTrue(vm.canCreateDatabase)

        let targetDb = DatabaseInfo(name: "analytics", oid: 16384, owner: "app_user", encoding: "UTF8", size: "12 MB", isOwner: false)
        let (superCanDrop, superReason) = vm.canDropDatabase(targetDb, currentDatabase: "postgres")
        XCTAssertTrue(superCanDrop)
        XCTAssertNil(superReason)

        // 2. Active database protection (cannot drop connected db even as superuser)
        let (activeDropAllowed, activeReason) = vm.canDropDatabase(targetDb, currentDatabase: "analytics")
        XCTAssertFalse(activeDropAllowed)
        XCTAssertNotNil(activeReason)
        XCTAssertTrue(activeReason?.contains("Cannot drop active database") == true)

        // 3. User with CREATEDB role but not superuser
        vm.userPrivileges = UserPrivilegeInfo(username: "developer", isSuperuser: false, canCreateDb: true)
        XCTAssertTrue(vm.canCreateDatabase)

        // Drop db they DO own
        let ownedDb = DatabaseInfo(name: "dev_sandbox", oid: 16385, owner: "developer", encoding: "UTF8", size: "4 MB", isOwner: true)
        let (ownerCanDrop, ownerReason) = vm.canDropDatabase(ownedDb, currentDatabase: "postgres")
        XCTAssertTrue(ownerCanDrop)
        XCTAssertNil(ownerReason)

        // Drop db they DO NOT own
        let (nonOwnerCanDrop, nonOwnerReason) = vm.canDropDatabase(targetDb, currentDatabase: "postgres")
        XCTAssertFalse(nonOwnerCanDrop)
        XCTAssertNotNil(nonOwnerReason)
        XCTAssertTrue(nonOwnerReason?.contains("Only the database owner") == true)

        // 4. Read-only user without CREATEDB
        vm.userPrivileges = UserPrivilegeInfo(username: "readonly_user", isSuperuser: false, canCreateDb: false)
        XCTAssertFalse(vm.canCreateDatabase)
    }

    func testWorkspaceTabViewModelDatabasesTab() {
        let vm = WorkspaceTabViewModel()
        vm.openDatabasesTab()

        guard let activeTab = vm.activeTab else {
            XCTFail("Expected active tab")
            return
        }

        XCTAssertEqual(activeTab.title, "Databases")
        if case .databases = activeTab.type {
            // Success
        } else {
            XCTFail("Expected .databases tab type, got \(activeTab.type)")
        }

        // Calling openDatabasesTab again should not duplicate
        let initialCount = vm.tabs.count
        vm.openDatabasesTab()
        XCTAssertEqual(vm.tabs.count, initialCount)
    }

    // MARK: - Table Accurate Row Count Tests

    func testAccurateRowCountManagement() {
        let postgres = PostgresService()
        let schemaService = SchemaService(postgresService: postgres)
        let vm = SchemaViewModel(schemaService: schemaService)

        let table = TableInfo(
            schema: "public",
            name: "customers",
            oid: 12345,
            estimatedRowCount: 0,
            tableType: .table
        )

        // 1. Initial fallback: estimatedRowCount from TableInfo
        XCTAssertEqual(vm.accurateRowCount(for: table), 0)

        // 2. Fallback to TableDetail if present
        let detail = TableDetail(
            schema: "public",
            name: "customers",
            oid: 12345,
            tableType: .table,
            rowCount: 42,
            totalSize: "16 kB",
            indexSize: "8 kB",
            columnCount: 3,
            isOwner: true
        )
        vm.tableDetails["public"] = [detail]
        XCTAssertEqual(vm.accurateRowCount(for: table), 42)

        // 3. Highest priority: live accurate row count override
        vm.setAccurateRowCount(schema: "public", table: "customers", count: 999)
        XCTAssertEqual(vm.accurateRowCount(for: table), 999)
        XCTAssertEqual(vm.accurateRowCounts["public.customers"], 999)
        XCTAssertEqual(vm.tableDetails["public"]?.first?.rowCount, 999)
    }
}

