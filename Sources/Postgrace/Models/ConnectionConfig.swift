import Foundation

/// Defines the SSL mode for a PostgreSQL connection.
public enum SSLMode: String, Codable, CaseIterable, Hashable {
    case disable
    case require
}

/// Represents a visual color tag for a connection in the sidebar.
public enum ConnectionColor: String, Codable, CaseIterable, Hashable {
    case red
    case blue
    case green
    case orange
    case purple
    case none
}

/// A saved PostgreSQL connection configuration.
public struct SavedConnection: Identifiable, Codable, Hashable {
    /// Unique identifier for the connection.
    public let id: UUID
    /// Display name of the connection.
    public var name: String
    /// Host address (e.g., "localhost").
    public var host: String
    /// Port number (e.g., 5432).
    public var port: Int
    /// Username for authentication.
    public var username: String
    /// Default database to connect to.
    public var database: String
    /// SSL mode configuration.
    public var sslMode: SSLMode
    /// Visual color tag.
    public var colorTag: ConnectionColor
    /// Timestamp when the connection was created.
    public let createdAt: Date
    /// Timestamp when the connection was last updated.
    public var updatedAt: Date
    
    public init(id: UUID = UUID(),
                name: String,
                host: String = "localhost",
                port: Int = 5432,
                username: String,
                database: String,
                sslMode: SSLMode = .disable,
                colorTag: ConnectionColor = .none,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.database = database
        self.sslMode = sslMode
        self.colorTag = colorTag
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
