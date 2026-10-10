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

    func testQueryViewModelMultipleQueries() {
        let postgres = PostgresService()
        let vm = QueryViewModel(postgresService: postgres)

        XCTAssertEqual(vm.statementCount, 0)
        XCTAssertNil(vm.statementAtCursor)

        vm.queryText = "SELECT 1;\nSELECT 2;\nSELECT 3;"
        XCTAssertEqual(vm.statementCount, 3)
        XCTAssertEqual(vm.statementSpans.count, 3)

        // Statement at cursor at location 12 (in "SELECT 2")
        vm.selectedRange = NSRange(location: 12, length: 0)
        XCTAssertEqual(vm.statementAtCursor?.statement, "SELECT 2")

        // Multi-result state
        let res1 = QueryResult(columns: [ResultColumn(name: "num", dataTypeOID: 23, dataTypeName: "int4")], rows: [[.int(1)]], executionTime: 0.005, rowsAffected: 1, statusMessage: "OK")
        let item1 = StatementResult(index: 0, statement: "SELECT 1", result: res1, error: nil, duration: 0.005)
        let item2 = StatementResult(index: 1, statement: "SELECT 2", result: nil, error: "Syntax error", duration: 0.002)

        vm.statementResults = [item1, item2]
        vm.selectedStatementIndex = 0
        XCTAssertEqual(vm.activeStatementResult?.statement, "SELECT 1")
        XCTAssertTrue(vm.activeStatementResult?.isSuccess ?? false)
        XCTAssertEqual(vm.result?.rows.count, 1)

        // Switch to result 2
        vm.selectedStatementIndex = 1
        XCTAssertEqual(vm.activeStatementResult?.statement, "SELECT 2")
        XCTAssertFalse(vm.activeStatementResult?.isSuccess ?? true)
        XCTAssertEqual(vm.activeStatementResult?.error, "Syntax error")

        // Clear results
        vm.clearResult()
        XCTAssertTrue(vm.statementResults.isEmpty)
        XCTAssertEqual(vm.selectedStatementIndex, 0)
        XCTAssertNil(vm.result)
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
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_conn_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let postgres = PostgresService()
        let keychain = KeychainService()
        let vm = ConnectionViewModel(postgresService: postgres, keychainService: keychain, storageURL: tempURL)
        
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
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_conn_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let postgres = PostgresService()
        let keychain = KeychainService()
        let vm = ConnectionViewModel(postgresService: postgres, keychainService: keychain, storageURL: tempURL)

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

    func testColumnFilterHelpers() {
        let postgres = PostgresService()
        let vm = DataGridViewModel(postgresService: postgres)
        vm.availableColumns = ["id", "email", "role"]

        XCTAssertFalse(vm.hasFilter(for: "email"))
        XCTAssertNil(vm.filterRule(for: "email"))

        // Add filter
        vm.filterRules.append(FilterRule(column: "email", op: .contains, value: "@example.com"))
        XCTAssertTrue(vm.hasFilter(for: "email"))
        XCTAssertEqual(vm.filterRule(for: "email")?.value, "@example.com")
        XCTAssertEqual(vm.filterRule(for: "email")?.op, .contains)

        // Remove filter for column
        vm.filterRules.removeAll(where: { $0.column == "email" })
        XCTAssertFalse(vm.hasFilter(for: "email"))
        XCTAssertNil(vm.filterRule(for: "email"))
    }

    func testColumnVisibilityHelpers() {
        let postgres = PostgresService()
        let vm = DataGridViewModel(postgresService: postgres)
        vm.availableColumns = ["id", "name", "email", "created_at"]

        XCTAssertTrue(vm.hiddenColumns.isEmpty)
        XCTAssertTrue(vm.isColumnVisible("name"))
        XCTAssertTrue(vm.isColumnVisible("email"))

        // Hide email
        vm.toggleColumnVisibility("email")
        XCTAssertFalse(vm.isColumnVisible("email"))
        XCTAssertTrue(vm.hiddenColumns.contains("email"))
        XCTAssertTrue(vm.isColumnVisible("name"))

        // Unhide email
        vm.toggleColumnVisibility("email")
        XCTAssertTrue(vm.isColumnVisible("email"))
        XCTAssertFalse(vm.hiddenColumns.contains("email"))

        // Hide all except keep column
        vm.hideAllColumns(except: "id")
        XCTAssertTrue(vm.isColumnVisible("id"))
        XCTAssertFalse(vm.isColumnVisible("name"))
        XCTAssertFalse(vm.isColumnVisible("email"))
        XCTAssertFalse(vm.isColumnVisible("created_at"))

        // Restore all
        vm.showAllColumns()
        XCTAssertTrue(vm.hiddenColumns.isEmpty)
        XCTAssertTrue(vm.isColumnVisible("name"))
        XCTAssertTrue(vm.isColumnVisible("email"))
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

    func testConnectionViewModelToggleSafeMode() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_conn_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let postgres = PostgresService()
        let keychain = KeychainService()
        let vm = ConnectionViewModel(postgresService: postgres, keychainService: keychain, storageURL: tempURL)

        // Localhost connection: toggleable
        let localConn = SavedConnection(name: "Local", host: "localhost", username: "pg", database: "test")
        vm.selectedConnection = localConn
        XCTAssertFalse(vm.selectedConnection!.isSafeModeEffective)

        vm.toggleSafeMode()
        XCTAssertTrue(vm.selectedConnection!.isSafeModeEffective)

        vm.toggleSafeMode()
        XCTAssertFalse(vm.selectedConnection!.isSafeModeEffective)

        // Remote connection: cannot toggle, permanently locked
        let remoteConn = SavedConnection(name: "Remote Prod", host: "db.production.aws.com", username: "pg", database: "prod")
        vm.selectedConnection = remoteConn
        XCTAssertTrue(vm.selectedConnection!.isSafeModeEffective)

        vm.toggleSafeMode()
        XCTAssertTrue(vm.selectedConnection!.isSafeModeEffective, "Toggle must have no effect on remote connections")
    }

    func testQueryViewModelEvaluateSafety() {
        let postgres = PostgresService()
        let vm = QueryViewModel(postgresService: postgres)

        vm.queryText = "SELECT * FROM users;"
        let res1 = vm.evaluateSafety()
        XCTAssertFalse(res1.isDangerous)

        vm.queryText = "DELETE FROM users;"
        let res2 = vm.evaluateSafety()
        XCTAssertTrue(res2.isDangerous)
        XCTAssertTrue(res2.isUnbounded)

        vm.queryText = "DROP TABLE audit_trail;"
        let res3 = vm.evaluateSafety()
        XCTAssertTrue(res3.isDangerous)
        XCTAssertEqual(res3.statementType, "DROP")
    }

    func testPostgresErrorFormatting() {
        // Test generic Cocoa error with "error 1"
        let cocoaErr = NSError(domain: "PostgresNIO.PSQLError", code: 1, userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed. (PostgresNIO.PSQLError error 1.)"])
        let formatted = PostgresService.formatError(cocoaErr, host: "localhost", port: 5432)
        XCTAssertFalse(formatted.contains("The operation couldn’t be completed"), "Formatted error must strip generic Cocoa wrapper")

        // Test custom PostgresServiceError
        let customErr = PostgresServiceError.connectionFailed("Connection refused (localhost:5432).")
        let formattedCustom = PostgresService.formatError(customErr)
        XCTAssertEqual(formattedCustom, "Connection failed: Connection refused (localhost:5432).")
    }

    // MARK: - Fast Table Switching & Query Cancellation Tests

    func testDataGridViewModelSuppressesQueryCancelledError() async {
        let postgres = PostgresService()
        let mockDriver = MockCancellableDriver()
        await mockDriver.setError(for: "cancelled_table", error: DatabaseServiceError.queryFailed("Query cancelled by user."))
        await postgres.setActiveDriverForTesting(mockDriver)

        let vm = DataGridViewModel(postgresService: postgres)
        await vm.loadTableData(schema: "public", table: "cancelled_table")

        XCTAssertNil(vm.error, "Cancelled queries must not set an error banner")
        XCTAssertFalse(vm.isLoading, "Loading state must reset cleanly")
        XCTAssertNil(vm.result)
    }

    func testDataGridViewModelRapidSwitchingDiscardsStaleResponse() async {
        let postgres = PostgresService()
        let mockDriver = MockCancellableDriver()
        await mockDriver.setDelay(for: "table_slow", delay: .milliseconds(150))
        await mockDriver.setRowCount(for: "table_slow", count: 999)
        await mockDriver.setDelay(for: "table_fast", delay: .milliseconds(20))
        await mockDriver.setRowCount(for: "table_fast", count: 42)
        await postgres.setActiveDriverForTesting(mockDriver)

        let vm = DataGridViewModel(postgresService: postgres)

        // Launch slow table load first
        let task1 = Task {
            await vm.loadTableData(schema: "public", table: "table_slow")
        }
        // Rapid switch to fast table (short delay to ensure task 1 started)
        try? await Task.sleep(for: .milliseconds(10))
        let task2 = Task {
            await vm.loadTableData(schema: "public", table: "table_fast")
        }

        _ = await (task1.value, task2.value)

        XCTAssertEqual(vm.currentTable, "table_fast")
        XCTAssertEqual(vm.totalRows, 42, "Total rows must reflect the latest selected table, not the stale slow table")
        XCTAssertNil(vm.error)
        XCTAssertFalse(vm.isLoading)
    }

    func testDataGridViewModelStaleCancellationDoesNotOverwriteNewTable() async {
        let postgres = PostgresService()
        let mockDriver = MockCancellableDriver()
        await mockDriver.setDelay(for: "table_slow", delay: .milliseconds(100))
        await mockDriver.setError(for: "table_slow", error: DatabaseServiceError.queryFailed("Query cancelled by user."))
        await mockDriver.setDelay(for: "table_fast", delay: .milliseconds(10))
        await mockDriver.setRowCount(for: "table_fast", count: 100)
        await postgres.setActiveDriverForTesting(mockDriver)

        let vm = DataGridViewModel(postgresService: postgres)

        let task1 = Task {
            await vm.loadTableData(schema: "public", table: "table_slow")
        }
        try? await Task.sleep(for: .milliseconds(10))
        let task2 = Task {
            await vm.loadTableData(schema: "public", table: "table_fast")
        }

        _ = await (task1.value, task2.value)

        XCTAssertEqual(vm.currentTable, "table_fast")
        XCTAssertEqual(vm.totalRows, 100)
        XCTAssertNil(vm.error, "Stale cancellation from prior table must not overwrite successful newer table")
        XCTAssertFalse(vm.isLoading)
    }

    func testConnectionStorageFilePermissions() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("postgrace_perm_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("connections.json")
        let postgres = PostgresService()
        let keychain = KeychainService()
        let vm = ConnectionViewModel(postgresService: postgres, keychainService: keychain, storageURL: fileURL)

        let conn = SavedConnection(name: "SecurityTest", username: "postgres", database: "testdb")
        vm.saveConnection(conn, password: "test")

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertNotNil(perms)
        XCTAssertEqual(perms?.intValue, 0o600, "connections.json must have 0600 POSIX permissions")
    }

    func testExportViewModelLifecycles() async {
        let mock = MockDatabaseDriver()
        let postgres = PostgresService()
        await postgres.setActiveDriverForTesting(mock)
        let vm = ExportViewModel(postgresService: postgres)

        // Single table export setup
        vm.startTableExport(schema: "analytics", table: "clicks", filterClause: "id > 10")
        XCTAssertTrue(vm.isShowingSheet)
        XCTAssertEqual(vm.configuration.whereClause, "id > 10")
        XCTAssertEqual(vm.availableTables.count, 1)

        // Multiple tables export setup
        let items = [ExportTableItem(schema: "s1", table: "t1"), ExportTableItem(schema: "s2", table: "t2")]
        vm.startMultipleTablesExport(tables: items)
        XCTAssertEqual(vm.availableTables.count, 2)
        XCTAssertEqual(vm.configuration.selectedTables.count, 2)

        // Mock response for schema tables
        await mock.setQueryResultProvider { query in
            QueryResult(
                columns: [ResultColumn(name: "table_schema", dataTypeOID: 25, dataTypeName: "text"), ResultColumn(name: "table_name", dataTypeOID: 25, dataTypeName: "text")],
                rows: [
                    [CellValue.string("reporting"), CellValue.string("summary_daily")],
                    [CellValue.string("reporting"), CellValue.string("summary_monthly")]
                ],
                executionTime: 0.001,
                rowsAffected: 2,
                statusMessage: "SELECT 2"
            )
        }

        // Schema tables loading
        await vm.loadTablesForSchema("reporting")
        XCTAssertEqual(vm.availableTables.count, 2)
        XCTAssertEqual(vm.configuration.selectedTables.count, 2)
        XCTAssertEqual(vm.availableSchemas, ["reporting"])

        // Multiple schema tables loading
        await vm.loadTablesForMultipleSchemas(["reporting", "archive"])
        XCTAssertEqual(vm.availableSchemas.count, 2)

        // Database tables loading
        await vm.loadTablesForDatabase()
        XCTAssertFalse(vm.isLoadingTables)

        // Schema selection toggling
        vm.availableSchemas = ["s1", "s2"]
        vm.availableTables = [
            ExportTableItem(schema: "s1", table: "t1"),
            ExportTableItem(schema: "s2", table: "t2")
        ]
        vm.selectAllSchemas()
        XCTAssertTrue(vm.isSchemaSelected("s1"))
        XCTAssertTrue(vm.isSchemaSelected("s2"))
        XCTAssertTrue(vm.isTableSelected(ExportTableItem(schema: "s1", table: "t1")))

        vm.toggleSchemaSelection("s1")
        XCTAssertFalse(vm.isSchemaSelected("s1"))
        XCTAssertFalse(vm.isTableSelected(ExportTableItem(schema: "s1", table: "t1")))

        vm.deselectAllSchemas()
        XCTAssertFalse(vm.isSchemaSelected("s2"))
        XCTAssertTrue(vm.configuration.selectedTables.isEmpty)

        // Cancellation and sheet closure
        vm.isExporting = true
        vm.cancelExport()
        XCTAssertFalse(vm.isExporting)
        XCTAssertEqual(vm.progress.status, .cancelled)

        vm.closeSheet()
        XCTAssertFalse(vm.isShowingSheet)
    }

    func testQueryViewModelStatementSpansAndExecution() async {
        let mock = MockDatabaseDriver()
        let postgres = PostgresService()
        await postgres.setActiveDriverForTesting(mock)
        let vm = QueryViewModel(postgresService: postgres)

        vm.queryText = """
        SELECT * FROM users;
        SELECT * FROM orders WHERE total > 100;
        UPDATE settings SET value = 'dark';
        """

        // Statement analysis
        XCTAssertEqual(vm.statementCount, 3)
        XCTAssertEqual(vm.statementSpans.count, 3)

        // Cursor statement detection
        vm.selectedRange = NSRange(location: 5, length: 0)
        XCTAssertEqual(vm.statementAtCursor?.statement.trimmingCharacters(in: .whitespacesAndNewlines), "SELECT * FROM users")

        vm.selectedRange = NSRange(location: 30, length: 0)
        XCTAssertTrue(vm.statementAtCursor?.statement.contains("orders") ?? false)

        // Statement execution
        await vm.executeStatements([
            "SELECT 1;",
            "SELECT 2;"
        ])

        XCTAssertEqual(vm.statementResults.count, 2)
        XCTAssertEqual(vm.queryHistory.count, 2)
        XCTAssertNotNil(vm.activeStatementResult)
        XCTAssertTrue(vm.activeStatementResult?.isSuccess ?? false)
        XCTAssertEqual(vm.activeStatementResult?.rowCount, 2)
        XCTAssertEqual(vm.activeStatementResult?.columnCount, 2)

        // Legacy result compatibility
        XCTAssertNotNil(vm.result)

        // Cancel running query
        vm.isExecuting = true
        vm.cancelQuery()
        XCTAssertFalse(vm.isExecuting)
    }
}


// MARK: - Mock Driver for Cancellation & Concurrency Tests

private actor MockCancellableDriver: DatabaseDriverProtocol {
    nonisolated var engine: DatabaseEngine { .postgresql }
    var isConnected: Bool = true
    var currentDatabase: String? = "test_db"
    var activeConfig: SavedConnection? = nil
    var activePassword: String? = nil
    var lastConnectionError: String? = nil

    private var delayForTable: [String: Duration] = [:]
    private var errorForTable: [String: Error] = [:]
    private var rowCountForTable: [String: Int64] = [:]

    func setDelay(for table: String, delay: Duration) {
        delayForTable[table] = delay
    }

    func setError(for table: String, error: Error) {
        errorForTable[table] = error
    }

    func setRowCount(for table: String, count: Int64) {
        rowCountForTable[table] = count
    }

    func connect(config: SavedConnection, password: String) async throws {}
    func disconnect() async throws {}
    func switchDatabase(to newDatabase: String) async throws {}
    func testConnection(config: SavedConnection, password: String) async throws -> Bool { true }
    func executeQuery(_ sql: String) async throws -> QueryResult {
        QueryResult(columns: [], rows: [], executionTime: 0, rowsAffected: 0, statusMessage: "OK")
    }

    func fetchTableData(
        schema: String,
        table: String,
        filterClause: String,
        orderBy: String?,
        limit: Int,
        offset: Int
    ) async throws -> QueryResult {
        if let delay = delayForTable[table] {
            try await Task.sleep(for: delay)
        }
        if let err = errorForTable[table] {
            throw err
        }
        let count = Int(rowCountForTable[table] ?? 1)
        return QueryResult(
            columns: [ResultColumn(name: "id", dataTypeOID: 23, dataTypeName: "int4")],
            rows: (0..<count).map { [.int(Int64($0))] },
            executionTime: 0.01,
            rowsAffected: count,
            statusMessage: "SELECT \(count)"
        )
    }

    func fetchTableRowCount(schema: String, table: String, filterClause: String) async throws -> Int64 {
        if let delay = delayForTable[table] {
            try await Task.sleep(for: delay)
        }
        if let err = errorForTable[table] {
            throw err
        }
        return rowCountForTable[table] ?? 1
    }

    func executeRawStatement(_ sql: String) async throws {}
    func streamQuery(
        _ sql: String,
        onRow: @escaping ([ResultColumn], [CellValue]) async throws -> Void
    ) async throws -> (columns: [ResultColumn], rowCount: Int64, executionTime: Double) {
        ([], 0, 0)
    }

    func executeBatchInsert(
        schema: String,
        table: String,
        columns: [String],
        rows: [[String]],
        treatEmptyAsNull: Bool
    ) async throws -> Int {
        0
    }

    func cancelRunningQuery() async {}
}

