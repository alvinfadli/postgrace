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

    private let postgresService: PostgresService
    private let keychainService: KeychainService

    public init(postgresService: PostgresService, keychainService: KeychainService) {
        self.postgresService = postgresService
        self.keychainService = keychainService
        loadConnections()
    }

    private var connectionsFileURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirURL = appSupportURL.appendingPathComponent("Postgrace", isDirectory: true)
        if !fileManager.fileExists(atPath: appDirURL.path) {
            try? fileManager.createDirectory(at: appDirURL, withIntermediateDirectories: true, attributes: nil)
        }
        return appDirURL.appendingPathComponent("connections.json")
    }

    public var availableDatabases: [DatabaseInfo] = []
    public var isSwitchingDatabase: Bool = false

    /// Connect to a saved connection using stored credentials.
    public func connect(to connection: SavedConnection) async {
        isConnecting = true
        connectionError = nil

        do {
            let password = (try? keychainService.getPassword(for: connection.id)) ?? ""
            try await postgresService.connect(config: connection, password: password)
            selectedConnection = connection
            isConnected = await postgresService.isConnected
        } catch {
            connectionError = error.localizedDescription
            isConnected = false
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

    /// Disconnect from the current connection.
    public func disconnect() async {
        try? await postgresService.disconnect()
        isConnected = false
        selectedConnection = nil
        availableDatabases = []
    }

    /// Test a connection with the given password (does not persist).
    public func testConnection(_ connection: SavedConnection, password: String) async -> Bool {
        do {
            return try await postgresService.testConnection(config: connection, password: password)
        } catch {
            connectionError = error.localizedDescription
            return false
        }
    }

    /// Save a connection config to disk and its password to the Keychain.
    public func saveConnection(_ connection: SavedConnection, password: String) {
        if let index = savedConnections.firstIndex(where: { $0.id == connection.id }) {
            savedConnections[index] = connection
        } else {
            savedConnections.append(connection)
        }

        try? keychainService.savePassword(password, for: connection.id)
        persistConnections()
    }

    /// Delete a connection and its stored password.
    public func deleteConnection(_ connection: SavedConnection) {
        savedConnections.removeAll(where: { $0.id == connection.id })
        try? keychainService.deletePassword(for: connection.id)
        persistConnections()
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
        } catch {
            print("Failed to save connections: \(error)")
        }
    }
}
