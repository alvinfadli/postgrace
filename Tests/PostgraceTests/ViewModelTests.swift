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
        
        // Delete
        vm.deleteConnection(updatedConn)
        XCTAssertFalse(vm.savedConnections.contains { $0.id == newConn.id })
        XCTAssertEqual(vm.savedConnections.count, initialCount)
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
}

