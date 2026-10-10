import XCTest
@testable import Postgrace

final class ConnectionHubTests: XCTestCase {

    // MARK: - 1. URI Parsing & Connection String Generation Tests

    func testPostgresURIParser() {
        let uri = "postgresql://myuser:supersecret@db.supabase.co:5432/production?sslmode=require"
        guard let (conn, pwd) = SavedConnection.parse(uriString: uri) else {
            XCTFail("Failed to parse standard postgresql URI")
            return
        }

        XCTAssertEqual(conn.engine, .postgresql)
        XCTAssertEqual(conn.username, "myuser")
        XCTAssertEqual(pwd, "supersecret")
        XCTAssertEqual(conn.host, "db.supabase.co")
        XCTAssertEqual(conn.port, 5432)
        XCTAssertEqual(conn.database, "production")
        XCTAssertEqual(conn.sslMode, .require)
        XCTAssertTrue(conn.isSafeModeLocked) // Remote host locked ON
        XCTAssertTrue(conn.isSafeModeEffective)
    }

    func testPostgresShortSchemeAndDefaultPort() {
        let uri = "postgres://app:vaultpass@localhost/dev_db"
        guard let (conn, pwd) = SavedConnection.parse(uriString: uri) else {
            XCTFail("Failed to parse short postgres:// scheme")
            return
        }

        XCTAssertEqual(conn.engine, .postgresql)
        XCTAssertEqual(conn.username, "app")
        XCTAssertEqual(pwd, "vaultpass")
        XCTAssertEqual(conn.host, "localhost")
        XCTAssertEqual(conn.port, 5432) // default postgres port
        XCTAssertEqual(conn.database, "dev_db")
        XCTAssertFalse(conn.isSafeModeLocked) // Localhost
    }

    func testMySQLAndMariaDBURIParser() {
        let mysqlURI = "mysql://root:secret@127.0.0.1:3306/store"
        guard let (mysqlConn, mysqlPwd) = SavedConnection.parse(uriString: mysqlURI) else {
            XCTFail("Failed to parse MySQL URI")
            return
        }

        XCTAssertEqual(mysqlConn.engine, .mysql)
        XCTAssertEqual(mysqlConn.username, "root")
        XCTAssertEqual(mysqlPwd, "secret")
        XCTAssertEqual(mysqlConn.host, "127.0.0.1")
        XCTAssertEqual(mysqlConn.port, 3306)
        XCTAssertEqual(mysqlConn.database, "store")

        let mariaURI = "mariadb://admin:mypass@db.internal:3307/analytics"
        guard let (mariaConn, mariaPwd) = SavedConnection.parse(uriString: mariaURI) else {
            XCTFail("Failed to parse MariaDB URI")
            return
        }

        XCTAssertEqual(mariaConn.engine, .mariadb)
        XCTAssertEqual(mariaConn.username, "admin")
        XCTAssertEqual(mariaPwd, "mypass")
        XCTAssertEqual(mariaConn.host, "db.internal")
        XCTAssertEqual(mariaConn.port, 3307)
        XCTAssertEqual(mariaConn.database, "analytics")
    }

    func testInvalidURIReturnsNil() {
        XCTAssertNil(SavedConnection.parse(uriString: ""))
        XCTAssertNil(SavedConnection.parse(uriString: "http://example.com"))
        XCTAssertNil(SavedConnection.parse(uriString: "not a uri"))
    }

    func testConnectionStringMaskedAndFull() {
        let conn = SavedConnection(
            name: "Cloud Instance",
            engine: .postgresql,
            host: "aws.postgres.com",
            port: 5432,
            username: "dbadmin",
            database: "metrics",
            sslMode: .require
        )

        let sanitized = conn.connectionString(includePassword: false)
        XCTAssertTrue(sanitized.contains("dbadmin:••••••••@aws.postgres.com:5432/metrics?sslmode=require"))
        XCTAssertFalse(sanitized.contains("realpassword"))

        let full = conn.connectionString(includePassword: true, password: "realpassword")
        XCTAssertTrue(full.contains("dbadmin:realpassword@aws.postgres.com:5432/metrics?sslmode=require"))
    }

    // MARK: - 2. Filter & Navigation Tests

    func testHubGroupFilters() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_hub_filters_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let vm = ConnectionViewModel(postgresService: PostgresService(), keychainService: KeychainService(), storageURL: tempURL)

        let local = SavedConnection(name: "Local Dev", host: "localhost", port: 5432, username: "postgres", database: "dev", isFavorite: true)
        let remote = SavedConnection(name: "Prod Replica", host: "10.0.0.5", port: 5432, username: "admin", database: "prod", isFavorite: false)
        var recent = SavedConnection(name: "Staging", host: "10.0.0.6", port: 5432, username: "dev", database: "staging", isFavorite: true)
        recent.lastConnectedAt = Date()

        vm.saveConnection(local, password: "")
        vm.saveConnection(remote, password: "")
        vm.saveConnection(recent, password: "")

        // All
        vm.activeGroupFilter = .all
        XCTAssertEqual(vm.filteredConnections(searchText: "").count, 3)

        // Favorites
        vm.activeGroupFilter = .favorites
        let favs = vm.filteredConnections(searchText: "")
        XCTAssertEqual(favs.count, 2)
        XCTAssertTrue(favs.contains(where: { $0.id == local.id }))
        XCTAssertTrue(favs.contains(where: { $0.id == recent.id }))

        // Recent
        vm.activeGroupFilter = .recent
        let recents = vm.filteredConnections(searchText: "")
        XCTAssertEqual(recents.count, 1)
        XCTAssertEqual(recents.first?.id, recent.id)

        // Remote
        vm.activeGroupFilter = .remote
        let remotes = vm.filteredConnections(searchText: "")
        XCTAssertEqual(remotes.count, 2)
        XCTAssertTrue(remotes.allSatisfy { !$0.isLocalhost })

        // Localhost
        vm.activeGroupFilter = .localhost
        let locals = vm.filteredConnections(searchText: "")
        XCTAssertEqual(locals.count, 1)
        XCTAssertEqual(locals.first?.id, local.id)
    }

    func testEngineAndSearchFilters() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_engine_search_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let vm = ConnectionViewModel(postgresService: PostgresService(), keychainService: KeychainService(), storageURL: tempURL)

        let pgConn = SavedConnection(name: "Postgres Warehouse", engine: .postgresql, host: "localhost", port: 5432, username: "postgres", database: "wh")
        let myConn = SavedConnection(name: "MySQL Storefront", engine: .mysql, host: "127.0.0.1", port: 3306, username: "root", database: "shop")
        let mariaConn = SavedConnection(name: "Maria Analytics", engine: .mariadb, host: "remote.maria.com", port: 3306, username: "maria", database: "stats")

        vm.saveConnection(pgConn, password: "")
        vm.saveConnection(myConn, password: "")
        vm.saveConnection(mariaConn, password: "")

        // Filter by Engine
        vm.activeGroupFilter = .all
        vm.activeEngineFilter = .mysql
        let mysqlMatches = vm.filteredConnections(searchText: "")
        XCTAssertEqual(mysqlMatches.count, 1)
        XCTAssertEqual(mysqlMatches.first?.engine, .mysql)

        vm.activeEngineFilter = .mariadb
        let mariaMatches = vm.filteredConnections(searchText: "")
        XCTAssertEqual(mariaMatches.count, 1)
        XCTAssertEqual(mariaMatches.first?.engine, .mariadb)

        vm.activeEngineFilter = nil

        // Direct Group Engine Filters
        vm.activeGroupFilter = .postgresql
        let pgMatches = vm.filteredConnections(searchText: "")
        XCTAssertEqual(pgMatches.count, 1)
        XCTAssertEqual(pgMatches.first?.engine, .postgresql)

        vm.activeGroupFilter = .mysql
        let myGroupMatches = vm.filteredConnections(searchText: "")
        XCTAssertEqual(myGroupMatches.count, 1)
        XCTAssertEqual(myGroupMatches.first?.engine, .mysql)

        vm.activeGroupFilter = .mariadb
        let mariaGroupMatches = vm.filteredConnections(searchText: "")
        XCTAssertEqual(mariaGroupMatches.count, 1)
        XCTAssertEqual(mariaGroupMatches.first?.engine, .mariadb)

        vm.activeGroupFilter = .all

        // Text Search
        let searchResults = vm.filteredConnections(searchText: "Storefront")
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.name, "MySQL Storefront")

        let searchHost = vm.filteredConnections(searchText: "remote.maria.com")
        XCTAssertEqual(searchHost.count, 1)
        XCTAssertEqual(searchHost.first?.database, "stats")
    }

    // MARK: - 3. Favorite Toggle & Selection Tests

    func testToggleFavorite() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_fav_toggle_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let vm = ConnectionViewModel(postgresService: PostgresService(), keychainService: KeychainService(), storageURL: tempURL)
        let conn = SavedConnection(name: "Test Server", host: "localhost", port: 5432, username: "postgres", database: "test", isFavorite: false)
        vm.saveConnection(conn, password: "")

        XCTAssertFalse(vm.savedConnections.first!.isFavorite)
        vm.toggleFavorite(for: conn)
        XCTAssertTrue(vm.savedConnections.first!.isFavorite)
        vm.toggleFavorite(for: vm.savedConnections.first!)
        XCTAssertFalse(vm.savedConnections.first!.isFavorite)
    }

    // MARK: - 4. Backup Export & Import Tests

    func testBackupExportAndImport() throws {
        let tempURL1 = FileManager.default.temporaryDirectory.appendingPathComponent("test_backup_1_\(UUID().uuidString).json")
        let tempURL2 = FileManager.default.temporaryDirectory.appendingPathComponent("test_backup_2_\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: tempURL1)
            try? FileManager.default.removeItem(at: tempURL2)
        }

        let vm1 = ConnectionViewModel(postgresService: PostgresService(), keychainService: KeychainService(), storageURL: tempURL1)
        let c1 = SavedConnection(name: "Server A", engine: .postgresql, host: "a.com", port: 5432, username: "userA", database: "dbA")
        let c2 = SavedConnection(name: "Server B", engine: .mysql, host: "b.com", port: 3306, username: "userB", database: "dbB")
        vm1.saveConnection(c1, password: "")
        vm1.saveConnection(c2, password: "")

        guard let backupData = vm1.exportBackup() else {
            XCTFail("Failed to export backup")
            return
        }

        let vm2 = ConnectionViewModel(postgresService: PostgresService(), keychainService: KeychainService(), storageURL: tempURL2)
        XCTAssertTrue(vm2.savedConnections.isEmpty)

        let importedCount = try vm2.importBackup(from: backupData)
        XCTAssertEqual(importedCount, 2)
        XCTAssertEqual(vm2.savedConnections.count, 2)
        XCTAssertTrue(vm2.savedConnections.contains(where: { $0.name == "Server A" }))
        XCTAssertTrue(vm2.savedConnections.contains(where: { $0.name == "Server B" }))
    }

    // MARK: - 5. Diagnostics Health Model Tests

    func testConnectionHealthModel() {
        let health = ConnectionHealth(
            isReachable: true,
            latencyMs: 14,
            serverVersion: "PostgreSQL 16.3",
            sslCipher: "TLS v1.3",
            lastTestedAt: Date(),
            errorMessage: nil
        )

        XCTAssertTrue(health.isReachable)
        XCTAssertEqual(health.latencyMs, 14)
        XCTAssertEqual(health.serverVersion, "PostgreSQL 16.3")
        XCTAssertNil(health.errorMessage)
    }

    // MARK: - 6. Disconnect State Transition Tests

    @MainActor
    func testDisconnectResetsStateAndReturnsToHub() async {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_disconnect_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let vm = ConnectionViewModel(postgresService: PostgresService(), keychainService: KeychainService(), storageURL: tempURL)
        let conn = SavedConnection(name: "Live DB", host: "localhost", port: 5432, username: "postgres", database: "prod")
        vm.saveConnection(conn, password: "")

        // Simulate connected state
        vm.isConnected = true
        vm.selectedConnection = conn
        vm.availableDatabases = [DatabaseInfo(name: "prod", oid: 16384)]
        vm.connectionError = "Old error"
        vm.showingConnectionForm = true
        vm.showingEditForm = true

        XCTAssertTrue(vm.isConnected)
        XCTAssertNotNil(vm.selectedConnection)

        // Call synchronous disconnect
        vm.disconnect()

        // Immediate reset check
        XCTAssertFalse(vm.isConnected, "isConnected must immediately be false to return to Connection Hub")
        XCTAssertNil(vm.selectedConnection, "selectedConnection must be nil")
        XCTAssertTrue(vm.availableDatabases.isEmpty, "availableDatabases must be cleared")
        XCTAssertNil(vm.connectionError, "connectionError must be reset")
        XCTAssertFalse(vm.showingConnectionForm, "modal forms must be dismissed")
        XCTAssertFalse(vm.showingEditForm, "edit form must be dismissed")
        XCTAssertEqual(vm.inspectorMode, .inspect, "inspector mode must return to inspect")

        // Saved connections must remain intact for the Hub page to render
        XCTAssertEqual(vm.savedConnections.count, 1)
        XCTAssertEqual(vm.savedConnections.first?.name, "Live DB")
    }
}
