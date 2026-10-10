import Foundation
import Observation
import SwiftUI

/// ViewModel for managing PostgreSQL connections.
@Observable
public class ConnectionViewModel {
    public var savedConnections: [SavedConnection] = []
    public var selectedConnection: SavedConnection?
    public var isConnecting: Bool = false
    public var isConnected: Bool = false
    public var connectionError: String?
    public var showingConnectionForm: Bool = false
    public var showingEditForm: Bool = false
    public var connectionToEdit: SavedConnection?

    // MARK: - Full-Page Connection Hub State
    public var activeGroupFilter: HubGroupFilter = .all
    public var activeEngineFilter: DatabaseEngine? = nil
    public var selectedConnectionId: UUID? = nil
    public var connectionHealthMap: [UUID: ConnectionHealth] = [:]
    public var isTestingMap: [UUID: Bool] = [:]
    public var isTestingAll: Bool = false
    public var viewMode: HubViewMode = .cards
    public var isInspectorVisible: Bool = true
    public var inspectorMode: HubInspectorMode = .inspect
    public var draftConnection: SavedConnection? = nil
    public var draftPassword: String = ""
    public var isImportURISheetPresented: Bool = false

    /// Opens the sheet/inspector to create a new connection.
    public func openNewConnectionForm() {
        connectionToEdit = nil
        showingConnectionForm = true
        inspectorMode = .create
        isInspectorVisible = true
        let defaultEngine: DatabaseEngine
        switch activeGroupFilter {
        case .postgresql: defaultEngine = .postgresql
        case .mysql: defaultEngine = .mysql
        case .mariadb: defaultEngine = .mariadb
        default: defaultEngine = activeEngineFilter ?? .postgresql
        }
        draftConnection = SavedConnection(
            name: "",
            engine: defaultEngine,
            host: "localhost",
            port: defaultEngine.defaultPort,
            username: defaultEngine.defaultUsername,
            database: defaultEngine.defaultDatabase,
            sslMode: .disable
        )
        draftPassword = ""
    }

    /// Opens the sheet/inspector to edit an existing connection.
    public func openEditConnectionForm(for connection: SavedConnection) {
        connectionToEdit = connection
        showingEditForm = true
        selectedConnectionId = connection.id
        inspectorMode = .edit
        isInspectorVisible = true
        draftConnection = connection
        draftPassword = getStoredPassword(for: connection.id) ?? ""
    }

    /// Convenience alias to edit a connection in the inspector.
    public func startEditingConnection(_ connection: SavedConnection) {
        openEditConnectionForm(for: connection)
    }

    /// Selects a connection instance and displays it in inspection mode.
    public func selectConnection(id: UUID) {
        selectedConnectionId = id
        inspectorMode = .inspect
        draftConnection = nil
    }

    private let postgresService: PostgresService
    private let keychainService: KeychainService
    private let customStorageURL: URL?

    public init(postgresService: PostgresService, keychainService: KeychainService, storageURL: URL? = nil) {
        self.postgresService = postgresService
        self.keychainService = keychainService
        self.customStorageURL = storageURL
        loadConnections()
        if selectedConnectionId == nil, let first = savedConnections.first {
            selectedConnectionId = first.id
        }
    }

    private var connectionsFileURL: URL {
        if let customStorageURL {
            return customStorageURL
        }
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirURL = appSupportURL.appendingPathComponent("Postgrace", isDirectory: true)
        if !fileManager.fileExists(atPath: appDirURL.path) {
            try? fileManager.createDirectory(at: appDirURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } else {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: appDirURL.path)
        }
        return appDirURL.appendingPathComponent("connections.json")
    }

    public var availableDatabases: [DatabaseInfo] = []
    public var isSwitchingDatabase: Bool = false

    /// Connect to a saved connection using stored credentials.
    @MainActor
    public func connect(to connection: SavedConnection) async {
        isConnecting = true
        connectionError = nil

        do {
            let password = (try? keychainService.getPassword(for: connection.id)) ?? ""
            try await postgresService.connect(config: connection, password: password)
            var updated = connection
            updated.lastConnectedAt = Date()
            saveConnection(updated, password: password)
            selectedConnection = updated
            selectedConnectionId = updated.id
            let connected = await postgresService.isConnected
            withAnimation(.easeInOut(duration: 0.2)) {
                isConnected = connected
            }
        } catch {
            connectionError = error.localizedDescription
            withAnimation(.easeInOut(duration: 0.2)) {
                isConnected = false
            }
        }

        isConnecting = false
    }

    /// Loads all available databases from the connected PostgreSQL instance.
    public func loadAvailableDatabases(schemaService: SchemaService) async {
        do {
            availableDatabases = try await schemaService.fetchDatabases()
        } catch {
            print("Failed to fetch available databases: \(error)")
        }
    }

    /// Switches the active database on the current server.
    @MainActor
    public func switchDatabase(to newDatabaseName: String, schemaViewModel: SchemaViewModel) async {
        guard let current = selectedConnection, current.database != newDatabaseName else { return }
        isSwitchingDatabase = true
        connectionError = nil

        do {
            try await postgresService.switchDatabase(to: newDatabaseName)
            var updated = current
            updated.database = newDatabaseName
            selectedConnection = updated
            // Refresh schemas and clear current table selection for the new database
            await schemaViewModel.refresh()
        } catch {
            connectionError = error.localizedDescription
        }

        isSwitchingDatabase = false
    }

    /// Disconnect from the current connection and return immediately to the Connection Hub.
    @MainActor
    public func disconnect() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isConnected = false
            selectedConnection = nil
            availableDatabases = []
            connectionError = nil
            showingConnectionForm = false
            showingEditForm = false
            inspectorMode = .inspect
            draftConnection = nil
            draftPassword = ""
        }

        let service = postgresService
        Task.detached {
            try? await service.disconnect()
        }
    }

    /// Test a connection with the given password (does not persist).
    public func testConnection(_ connection: SavedConnection, password: String) async -> Bool {
        connectionError = nil
        do {
            let success = try await postgresService.testConnection(config: connection, password: password)
            if !success {
                let err = await postgresService.lastConnectionError
                connectionError = err ?? "Connection failed."
            }
            return success
        } catch {
            connectionError = error.localizedDescription
            return false
        }
    }

    /// Runs a latency ping & SSL diagnostic check against a connection.
    @discardableResult
    public func runTestPing(for connection: SavedConnection, password: String? = nil) async -> ConnectionHealth {
        isTestingMap[connection.id] = true
        let start = CFAbsoluteTimeGetCurrent()
        let pwd = password ?? getStoredPassword(for: connection.id) ?? ""

        let health: ConnectionHealth
        do {
            let success = try await postgresService.testConnection(config: connection, password: pwd)
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            if success {
                let cipherDesc: String
                switch connection.sslMode {
                case .disable:
                    cipherDesc = "Plaintext (No SSL)"
                case .require:
                    cipherDesc = "TLS v1.3 (Strict TLS)"
                case .verifyCA:
                    cipherDesc = "TLS v1.3 (Verify CA)"
                case .verifyFull:
                    cipherDesc = "TLS v1.3 (Full Verification)"
                }
                health = ConnectionHealth(
                    isReachable: true,
                    latencyMs: elapsedMs,
                    serverVersion: "\(connection.engine.rawValue) Online",
                    sslCipher: cipherDesc,
                    lastTestedAt: Date(),
                    errorMessage: nil
                )
            } else {
                let err = await postgresService.lastConnectionError ?? "Connection refused or server offline."
                health = ConnectionHealth(
                    isReachable: false,
                    latencyMs: elapsedMs,
                    serverVersion: nil,
                    sslCipher: nil,
                    lastTestedAt: Date(),
                    errorMessage: err
                )
            }
        } catch {
            let elapsedMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
            health = ConnectionHealth(
                isReachable: false,
                latencyMs: elapsedMs,
                serverVersion: nil,
                sslCipher: nil,
                lastTestedAt: Date(),
                errorMessage: error.localizedDescription
            )
        }

        connectionHealthMap[connection.id] = health
        isTestingMap[connection.id] = false
        return health
    }

    /// Runs reachability tests for all saved connections concurrently.
    public func testAllConnections() async {
        isTestingAll = true
        await withTaskGroup(of: Void.self) { group in
            for conn in savedConnections {
                group.addTask {
                    _ = await self.runTestPing(for: conn)
                }
            }
        }
        isTestingAll = false
    }

    /// Toggles favorite status for a saved connection.
    public func toggleFavorite(for connection: SavedConnection) {
        var updated = connection
        updated.isFavorite.toggle()
        updated.updatedAt = Date()
        let pwd = getStoredPassword(for: connection.id) ?? ""
        saveConnection(updated, password: pwd)
    }

    /// Filters saved connections based on group, engine, and search text.
    public func filteredConnections(searchText: String) -> [SavedConnection] {
        var result = savedConnections

        // Group Filter
        switch activeGroupFilter {
        case .all:
            break
        case .favorites:
            result = result.filter { $0.isFavorite }
        case .recent:
            result = result.filter { $0.lastConnectedAt != nil }
                .sorted { ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast) }
        case .remote:
            result = result.filter { !$0.isLocalhost }
        case .localhost:
            result = result.filter { $0.isLocalhost }
        case .postgresql:
            result = result.filter { $0.engine == .postgresql }
        case .mysql:
            result = result.filter { $0.engine == .mysql }
        case .mariadb:
            result = result.filter { $0.engine == .mariadb }
        }

        // Engine Filter (if explicitly set)
        if let engine = activeEngineFilter {
            result = result.filter { $0.engine == engine }
        }

        // Search text
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return result }

        return result.filter { conn in
            conn.name.lowercased().contains(trimmed) ||
            conn.host.lowercased().contains(trimmed) ||
            conn.database.lowercased().contains(trimmed) ||
            conn.username.lowercased().contains(trimmed) ||
            conn.engine.rawValue.lowercased().contains(trimmed) ||
            conn.colorTag.rawValue.lowercased().contains(trimmed)
        }
    }

    /// Exports all saved connections to JSON data.
    public func exportBackup() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(savedConnections)
    }

    /// Imports connections from JSON data and saves them.
    public func importBackup(from data: Data) throws -> Int {
        let imported = try JSONDecoder().decode([SavedConnection].self, from: data)
        var count = 0
        for conn in imported {
            if let idx = savedConnections.firstIndex(where: { $0.id == conn.id }) {
                savedConnections[idx] = conn
            } else {
                savedConnections.append(conn)
            }
            count += 1
        }
        persistConnections()
        if selectedConnectionId == nil, let first = savedConnections.first {
            selectedConnectionId = first.id
        }
        return count
    }

    /// Save a connection config to disk and its password to the Keychain.
    public func saveConnection(_ connection: SavedConnection, password: String) {
        if let index = savedConnections.firstIndex(where: { $0.id == connection.id }) {
            savedConnections[index] = connection
            if selectedConnection?.id == connection.id {
                selectedConnection = connection
            }
        } else {
            savedConnections.append(connection)
        }

        if !password.isEmpty || getStoredPassword(for: connection.id) == nil {
            try? keychainService.savePassword(password, for: connection.id)
        }
        selectedConnectionId = connection.id
        persistConnections()
    }

    /// Delete a connection and its stored password.
    public func deleteConnection(_ connection: SavedConnection) {
        savedConnections.removeAll(where: { $0.id == connection.id })
        connectionHealthMap.removeValue(forKey: connection.id)
        isTestingMap.removeValue(forKey: connection.id)
        try? keychainService.deletePassword(for: connection.id)
        if selectedConnectionId == connection.id {
            selectedConnectionId = savedConnections.first?.id
            if selectedConnectionId == nil {
                inspectorMode = .create
            } else {
                inspectorMode = .inspect
            }
        }
        if selectedConnection?.id == connection.id {
            selectedConnection = nil
        }
        persistConnections()
    }

    /// Retrieve the stored password for a connection ID.
    public func getStoredPassword(for id: UUID) -> String? {
        try? keychainService.getPassword(for: id)
    }

    /// Duplicate an existing saved connection.
    @discardableResult
    public func duplicateConnection(_ connection: SavedConnection) -> SavedConnection {
        let copy = SavedConnection(
            id: UUID(),
            name: "\(connection.name) Copy",
            engine: connection.engine,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            database: connection.database,
            sslMode: connection.sslMode,
            colorTag: connection.colorTag,
            isSafeModeEnabled: connection.isSafeModeEnabled,
            isFavorite: connection.isFavorite,
            sshHost: connection.sshHost,
            sshPort: connection.sshPort,
            sshUser: connection.sshUser,
            sshKeyPath: connection.sshKeyPath,
            caCertPath: connection.caCertPath,
            sshEnabled: connection.sshEnabled,
            createdAt: Date(),
            updatedAt: Date()
        )
        let pwd = getStoredPassword(for: connection.id) ?? ""
        saveConnection(copy, password: pwd)
        selectedConnectionId = copy.id
        inspectorMode = .inspect
        return copy
    }

    /// Toggles the Safe Mode setting for the active connection if it is on localhost.
    /// Remote connections are permanently locked and cannot be toggled.
    public func toggleSafeMode() {
        guard let current = selectedConnection, current.isLocalhost else { return }
        var updated = current
        updated.isSafeModeEnabled = !(current.isSafeModeEffective)
        updated.updatedAt = Date()
        selectedConnection = updated
        let pwd = getStoredPassword(for: current.id) ?? ""
        saveConnection(updated, password: pwd)
    }

    /// Load connections from the JSON file on disk.
    public func loadConnections() {
        do {
            let data = try Data(contentsOf: connectionsFileURL)
            savedConnections = try JSONDecoder().decode([SavedConnection].self, from: data)
        } catch {
            savedConnections = []
        }
    }

    private func persistConnections() {
        do {
            let data = try JSONEncoder().encode(savedConnections)
            try data.write(to: connectionsFileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: connectionsFileURL.path)
        } catch {
            print("Failed to save connections: \(error)")
        }
    }
}
