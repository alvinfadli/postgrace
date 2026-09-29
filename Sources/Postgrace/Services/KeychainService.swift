import Foundation
import KeychainAccess

/// Service for storing and retrieving secure credentials in the macOS Keychain.
public struct KeychainService {
    private let keychain = Keychain(service: "com.postgrace.connections")
    
    public init() {}
    
    /// Saves a password to the keychain for a specific connection.
    /// - Parameters:
    ///   - password: The password to save.
    ///   - connectionId: The UUID of the connection.
    public func savePassword(_ password: String, for connectionId: UUID) throws {
        try keychain.set(password, key: connectionId.uuidString)
    }
    
    /// Retrieves a password from the keychain for a specific connection.
    /// - Parameter connectionId: The UUID of the connection.
    /// - Returns: The password if found, otherwise nil.
    public func getPassword(for connectionId: UUID) throws -> String? {
        return try keychain.get(connectionId.uuidString)
    }
    
    /// Deletes a password from the keychain for a specific connection.
    /// - Parameter connectionId: The UUID of the connection.
    public func deletePassword(for connectionId: UUID) throws {
        try keychain.remove(connectionId.uuidString)
    }
}
