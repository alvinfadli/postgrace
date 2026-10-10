import Foundation
import SwiftUI

/// Defines the SSL mode for a PostgreSQL or MySQL connection.
public enum SSLMode: String, Codable, CaseIterable, Hashable {
    case disable = "disable"
    case require = "require"
    case verifyCA = "verify-ca"
    case verifyFull = "verify-full"

    public var displayName: String {
        switch self {
        case .disable: return "Disable (No SSL)"
        case .require: return "Require (TLS Encrypted)"
        case .verifyCA: return "Verify CA (Trusted Cert)"
        case .verifyFull: return "Verify Full (Strict Hostname)"
        }
    }

    public var isTLSRequired: Bool {
        self != .disable
    }
}

/// Represents the connection health and latency diagnostics for a database instance.
public struct ConnectionHealth: Equatable, Hashable, Codable {
    public var isReachable: Bool
    public var latencyMs: Int?
    public var serverVersion: String?
    public var sslCipher: String?
    public var lastTestedAt: Date
    public var errorMessage: String?

    public init(
        isReachable: Bool,
        latencyMs: Int? = nil,
        serverVersion: String? = nil,
        sslCipher: String? = nil,
        lastTestedAt: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.isReachable = isReachable
        self.latencyMs = latencyMs
        self.serverVersion = serverVersion
        self.sslCipher = sslCipher
        self.lastTestedAt = lastTestedAt
        self.errorMessage = errorMessage
    }
}

/// Filter categories for the Connection Hub left sidebar.
public enum HubGroupFilter: String, CaseIterable, Identifiable {
    case all = "All Instances"
    case favorites = "Favorites"
    case recent = "Recent Connects"
    case remote = "Remote"
    case localhost = "Localhost"
    case postgresql = "PostgreSQL"
    case mysql = "MySQL"
    case mariadb = "MariaDB"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .all: return "server.rack"
        case .favorites: return "star.fill"
        case .recent: return "clock.arrow.circlepath"
        case .remote: return "network"
        case .localhost: return "laptopcomputer"
        case .postgresql: return "cylinder.split.1x2"
        case .mysql: return "shippingbox"
        case .mariadb: return "seal"
        }
    }
}

/// View presentation mode for Connection Hub center explorer.
public enum HubViewMode: String, CaseIterable {
    case cards
    case table
}

/// Right inspector pane mode.
public enum HubInspectorMode: String, CaseIterable {
    case inspect
    case edit
    case create
}

/// Represents a visual color tag for a connection in the sidebar.
public enum ConnectionColor: String, Codable, CaseIterable, Hashable {
    case red
    case blue
    case green
    case orange
    case purple
    case none

    public var color: Color {
        switch self {
        case .red: return PostgraceTheme.destructiveRed
        case .blue: return PostgraceTheme.accentSky
        case .green: return PostgraceTheme.emeraldRw
        case .orange: return PostgraceTheme.amberRo
        case .purple: return PostgraceTheme.purpleSuper
        case .none: return PostgraceTheme.emeraldRw
        }
    }
}

/// Supported relational database engines in Postgrace.
public enum DatabaseEngine: String, Codable, CaseIterable, Hashable, Identifiable {
    case postgresql = "PostgreSQL"
    case mysql = "MySQL"
    case mariadb = "MariaDB"

    public var id: String { rawValue }

    /// Standard default TCP port for the database engine.
    public var defaultPort: Int {
        switch self {
        case .postgresql: return 5432
        case .mysql, .mariadb: return 3306
        }
    }

    /// Default database/catalog name for new connections.
    public var defaultDatabase: String {
        switch self {
        case .postgresql: return "postgres"
        case .mysql, .mariadb: return "mysql"
        }
    }

    /// Default administrator username.
    public var defaultUsername: String {
        switch self {
        case .postgresql: return "postgres"
        case .mysql, .mariadb: return "root"
        }
    }

    /// Standard URL scheme identifier.
    public var defaultScheme: String {
        switch self {
        case .postgresql: return "postgresql"
        case .mysql: return "mysql"
        case .mariadb: return "mariadb"
        }
    }

    /// SF Symbol icon name representing the engine.
    public var iconName: String {
        switch self {
        case .postgresql: return "cylinder.split.1x2"
        case .mysql: return "shippingbox"
        case .mariadb: return "seal"
        }
    }

    /// Quotes an identifier for use in SQL queries based on engine dialect.
    public func quoteIdentifier(_ identifier: String) -> String {
        switch self {
        case .postgresql:
            return "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        case .mysql, .mariadb:
            return "`" + identifier.replacingOccurrences(of: "`", with: "``") + "`"
        }
    }
}

/// A saved database connection configuration.
public struct SavedConnection: Identifiable, Codable, Hashable {
    /// Unique identifier for the connection.
    public let id: UUID
    /// Display name of the connection.
    public var name: String
    /// The database engine (PostgreSQL, MySQL, MariaDB).
    public var engine: DatabaseEngine
    /// Host address (e.g., "localhost").
    public var host: String
    /// Port number (e.g., 5432 or 3306).
    public var port: Int
    /// Username for authentication.
    public var username: String
    /// Default database to connect to.
    public var database: String
    /// SSL mode configuration.
    public var sslMode: SSLMode
    /// Visual color tag.
    public var colorTag: ConnectionColor
    /// User preference for Safe Mode on localhost. For remote hosts, safe mode is permanently locked ON.
    public var isSafeModeEnabled: Bool?
    /// Starred / favorite connection indicator.
    public var isFavorite: Bool
    /// Timestamp when the connection was last successfully connected.
    public var lastConnectedAt: Date?
    /// SSH Bastion jump-host address (optional).
    public var sshHost: String?
    /// SSH Bastion jump-host port (default 22).
    public var sshPort: Int?
    /// SSH Bastion username.
    public var sshUser: String?
    /// SSH Bastion private key path.
    public var sshKeyPath: String?
    /// Custom CA certificate file path.
    public var caCertPath: String?
    /// Whether SSH tunneling is enabled.
    public var sshEnabled: Bool?
    /// Timestamp when the connection was created.
    public let createdAt: Date
    /// Timestamp when the connection was last updated.
    public var updatedAt: Date
    
    public init(id: UUID = UUID(),
                name: String,
                engine: DatabaseEngine = .postgresql,
                host: String = "localhost",
                port: Int? = nil,
                username: String,
                database: String,
                sslMode: SSLMode = .disable,
                colorTag: ConnectionColor = .none,
                isSafeModeEnabled: Bool? = nil,
                isFavorite: Bool = false,
                lastConnectedAt: Date? = nil,
                sshHost: String? = nil,
                sshPort: Int? = nil,
                sshUser: String? = nil,
                sshKeyPath: String? = nil,
                caCertPath: String? = nil,
                sshEnabled: Bool? = nil,
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.engine = engine
        self.host = host
        self.port = port ?? engine.defaultPort
        self.username = username
        self.database = database
        self.sslMode = sslMode
        self.colorTag = colorTag
        self.isSafeModeEnabled = isSafeModeEnabled
        self.isFavorite = isFavorite
        self.lastConnectedAt = lastConnectedAt
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.sshKeyPath = sshKeyPath
        self.caCertPath = caCertPath
        self.sshEnabled = sshEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, engine, host, port, username, database, sslMode, colorTag
        case isSafeModeEnabled, isFavorite, lastConnectedAt
        case sshHost, sshPort, sshUser, sshKeyPath, caCertPath, sshEnabled
        case createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.engine = try container.decodeIfPresent(DatabaseEngine.self, forKey: .engine) ?? .postgresql
        self.host = try container.decode(String.self, forKey: .host)
        self.port = try container.decode(Int.self, forKey: .port)
        self.username = try container.decode(String.self, forKey: .username)
        self.database = try container.decode(String.self, forKey: .database)
        self.sslMode = try container.decodeIfPresent(SSLMode.self, forKey: .sslMode) ?? .disable
        self.colorTag = try container.decodeIfPresent(ConnectionColor.self, forKey: .colorTag) ?? .none
        self.isSafeModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .isSafeModeEnabled)
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        self.sshHost = try container.decodeIfPresent(String.self, forKey: .sshHost)
        self.sshPort = try container.decodeIfPresent(Int.self, forKey: .sshPort)
        self.sshUser = try container.decodeIfPresent(String.self, forKey: .sshUser)
        self.sshKeyPath = try container.decodeIfPresent(String.self, forKey: .sshKeyPath)
        self.caCertPath = try container.decodeIfPresent(String.self, forKey: .caCertPath)
        self.sshEnabled = try container.decodeIfPresent(Bool.self, forKey: .sshEnabled)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(engine, forKey: .engine)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(database, forKey: .database)
        try container.encode(sslMode, forKey: .sslMode)
        try container.encode(colorTag, forKey: .colorTag)
        try container.encodeIfPresent(isSafeModeEnabled, forKey: .isSafeModeEnabled)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encodeIfPresent(lastConnectedAt, forKey: .lastConnectedAt)
        try container.encodeIfPresent(sshHost, forKey: .sshHost)
        try container.encodeIfPresent(sshPort, forKey: .sshPort)
        try container.encodeIfPresent(sshUser, forKey: .sshUser)
        try container.encodeIfPresent(sshKeyPath, forKey: .sshKeyPath)
        try container.encodeIfPresent(caCertPath, forKey: .caCertPath)
        try container.encodeIfPresent(sshEnabled, forKey: .sshEnabled)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

extension SavedConnection {
    /// Detects if the connection host is local (localhost, 127.0.0.1, ::1, or *.local).
    public var isLocalhost: Bool {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return h == "localhost" || h == "127.0.0.1" || h == "::1" || h.hasSuffix(".local")
    }
    
    /// Remote hosts are permanently locked to Safe Mode ON.
    public var isSafeModeLocked: Bool {
        return !isLocalhost
    }

    /// Evaluates whether Safe Mode is currently in effect:
    /// - Remote hosts: always true (permanently enforced).
    /// - Localhost: evaluates user preference (defaulting to false / OFF).
    public var isSafeModeEffective: Bool {
        if isSafeModeLocked {
            return true
        }
        return isSafeModeEnabled ?? false
    }

    /// Generates standard URI connection string with masked or unmasked password.
    public func connectionString(includePassword: Bool, password: String? = nil) -> String {
        let scheme = engine.defaultScheme
        let passPart = includePassword ? (password ?? "") : "••••••••"
        let authPart = username.isEmpty ? "" : "\(username):\(passPart)@"
        var queryParts: [String] = []
        if sslMode != .disable {
            queryParts.append("sslmode=\(sslMode.rawValue)")
        }
        let queryString = queryParts.isEmpty ? "" : "?\(queryParts.joined(separator: "&"))"
        return "\(scheme)://\(authPart)\(host):\(port)/\(database)\(queryString)"
    }

    /// Parses a database connection URI (Supabase, Neon, RDS, PlanetScale, Local Docker)
    /// into a SavedConnection and password pair.
    public static func parse(uriString: String) -> (connection: SavedConnection, password: String)? {
        let trimmed = uriString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let schemeSeparatorRange = trimmed.range(of: "://") else { return nil }

        let scheme = String(trimmed[..<schemeSeparatorRange.lowerBound]).lowercased()
        let remainder = String(trimmed[schemeSeparatorRange.upperBound...])

        let engine: DatabaseEngine
        switch scheme {
        case "postgres", "postgresql":
            engine = .postgresql
        case "mysql":
            engine = .mysql
        case "mariadb":
            engine = .mariadb
        default:
            return nil
        }

        // Try standard URLComponents first
        if let components = URLComponents(string: trimmed), let host = components.host, !host.isEmpty {
            let user = components.user ?? engine.defaultUsername
            let password = components.password ?? ""
            let port = components.port ?? engine.defaultPort
            let rawPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let database = rawPath.isEmpty ? engine.defaultDatabase : rawPath

            var sslMode: SSLMode = .disable
            if let items = components.queryItems {
                for item in items {
                    if item.name.lowercased() == "sslmode", let val = item.value?.lowercased() {
                        if val == "require" { sslMode = .require }
                        else if val == "verify-ca" { sslMode = .verifyCA }
                        else if val == "verify-full" { sslMode = .verifyFull }
                        else if val == "disable" { sslMode = .disable }
                    }
                }
            } else if host.contains("supabase.co") || host.contains("neon.tech") || host.contains("aws.com") {
                sslMode = .require
            }

            let name = "\(database) on \(host)"
            let conn = SavedConnection(
                name: name,
                engine: engine,
                host: host,
                port: port,
                username: user,
                database: database,
                sslMode: sslMode
            )
            return (conn, password)
        }

        // Fallback custom tokenizer if URLComponents failed due to unescaped special characters
        // Format: [user[:password]@]host[:port][/database][?query]
        var authHostPart = remainder
        var queryString = ""
        if let questionIndex = authHostPart.firstIndex(of: "?") {
            queryString = String(authHostPart[authHostPart.index(after: questionIndex)...])
            authHostPart = String(authHostPart[..<questionIndex])
        }

        var pathString = ""
        if let slashIndex = authHostPart.firstIndex(of: "/") {
            pathString = String(authHostPart[authHostPart.index(after: slashIndex)...])
            authHostPart = String(authHostPart[..<slashIndex])
        }

        var username = engine.defaultUsername
        var password = ""
        var hostPortPart = authHostPart

        if let atIndex = authHostPart.lastIndex(of: "@") {
            let auth = String(authHostPart[..<atIndex])
            hostPortPart = String(authHostPart[authHostPart.index(after: atIndex)...])

            if let colonIndex = auth.firstIndex(of: ":") {
                username = String(auth[..<colonIndex])
                password = String(auth[auth.index(after: colonIndex)...])
            } else {
                username = auth
            }
        }

        var host = hostPortPart
        var port = engine.defaultPort
        if let colonIndex = hostPortPart.lastIndex(of: ":") {
            let portStr = String(hostPortPart[hostPortPart.index(after: colonIndex)...])
            if let p = Int(portStr) {
                port = p
                host = String(hostPortPart[..<colonIndex])
            }
        }

        guard !host.isEmpty else { return nil }
        let database = pathString.isEmpty ? engine.defaultDatabase : pathString

        var sslMode: SSLMode = .disable
        if queryString.lowercased().contains("sslmode=require") {
            sslMode = .require
        } else if queryString.lowercased().contains("sslmode=verify-full") {
            sslMode = .verifyFull
        } else if queryString.lowercased().contains("sslmode=verify-ca") {
            sslMode = .verifyCA
        } else if host.contains("supabase.co") || host.contains("neon.tech") {
            sslMode = .require
        }

        let name = "\(database) on \(host)"
        let conn = SavedConnection(
            name: name,
            engine: engine,
            host: host,
            port: port,
            username: username,
            database: database,
            sslMode: sslMode
        )
        return (conn, password)
    }
}
