import Foundation

/// Represents a PostgreSQL database.
public struct DatabaseInfo: Identifiable, Hashable {
    public var id: UInt32 { oid }
    public let name: String
    public let oid: UInt32
    
    public init(name: String, oid: UInt32) {
        self.name = name
        self.oid = oid
    }
}

/// Represents a PostgreSQL schema within a database.
public struct SchemaInfo: Identifiable, Hashable {
    public var id: UInt32 { oid }
    public let name: String
    public let oid: UInt32
    
    public init(name: String, oid: UInt32) {
        self.name = name
        self.oid = oid
    }
}

/// Defines the type of a table-like relation.
public enum TableType: String, Codable, Hashable {
    case table = "BASE TABLE"
    case view = "VIEW"
    case materializedView = "MATERIALIZED VIEW"
    case foreignTable = "FOREIGN TABLE"
}

/// Represents a PostgreSQL table, view, or similar relation.
public struct TableInfo: Identifiable, Hashable {
    public var id: UInt32 { oid }
    public let schema: String
    public let name: String
    public let oid: UInt32
    public let estimatedRowCount: Int64
    public let tableType: TableType
    
    public init(schema: String, name: String, oid: UInt32, estimatedRowCount: Int64, tableType: TableType) {
        self.schema = schema
        self.name = name
        self.oid = oid
        self.estimatedRowCount = estimatedRowCount
        self.tableType = tableType
    }
}

/// Represents a column in a PostgreSQL table or view.
public struct ColumnInfo: Identifiable, Hashable {
    public var id: String { "\(name)_\(ordinalPosition)" }
    public let name: String
    public let ordinalPosition: Int
    public let dataType: String
    public let isNullable: Bool
    public let defaultValue: String?
    public let isPrimaryKey: Bool
    public let characterMaxLength: Int?
    
    public init(name: String, ordinalPosition: Int, dataType: String, isNullable: Bool, defaultValue: String?, isPrimaryKey: Bool, characterMaxLength: Int?) {
        self.name = name
        self.ordinalPosition = ordinalPosition
        self.dataType = dataType
        self.isNullable = isNullable
        self.defaultValue = defaultValue
        self.isPrimaryKey = isPrimaryKey
        self.characterMaxLength = characterMaxLength
    }
}

/// Represents an index on a PostgreSQL table.
public struct IndexInfo: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let tableName: String
    public let isUnique: Bool
    public let isPrimary: Bool
    public let columns: [String]
    
    public init(name: String, tableName: String, isUnique: Bool, isPrimary: Bool, columns: [String]) {
        self.name = name
        self.tableName = tableName
        self.isUnique = isUnique
        self.isPrimary = isPrimary
        self.columns = columns
    }
}

/// Represents a PostgreSQL function or stored procedure.
public struct FunctionInfo: Identifiable, Hashable {
    public var id: UInt32 { oid }
    public let schema: String
    public let name: String
    public let oid: UInt32
    public let returnType: String
    public let argumentTypes: String
    public let language: String
    
    public init(schema: String, name: String, oid: UInt32, returnType: String, argumentTypes: String, language: String) {
        self.schema = schema
        self.name = name
        self.oid = oid
        self.returnType = returnType
        self.argumentTypes = argumentTypes
        self.language = language
    }
}

// MARK: - User Privilege & Permission Models

/// Represents the connected user's overall PostgreSQL permissions.
public struct UserPrivilegeInfo: Hashable {
    public let username: String
    public let isSuperuser: Bool
    public let canCreateDb: Bool
    public let canCreateSchemaInDb: Bool
    public var schemaPrivileges: [String: SchemaPrivilege]
    public var tablePrivileges: [String: TablePrivilege]

    public init(
        username: String,
        isSuperuser: Bool,
        canCreateDb: Bool,
        canCreateSchemaInDb: Bool = false,
        schemaPrivileges: [String: SchemaPrivilege] = [:],
        tablePrivileges: [String: TablePrivilege] = [:]
    ) {
        self.username = username
        self.isSuperuser = isSuperuser
        self.canCreateDb = canCreateDb
        self.canCreateSchemaInDb = canCreateSchemaInDb
        self.schemaPrivileges = schemaPrivileges
        self.tablePrivileges = tablePrivileges
    }

    /// User-friendly privilege level label.
    public var privilegeLevelDescription: String {
        if isSuperuser {
            return "Superuser"
        }
        let canCreateAny = schemaPrivileges.values.contains { $0.canCreate } || canCreateSchemaInDb
        if canCreateAny {
            return "Read-Write"
        }
        return "Read-Only"
    }
}

/// Helper wrapper for presenting sheets with identifiable strings.
public struct IdentifiableString: Identifiable, Hashable {
    public var id: String { value }
    public let value: String

    public init(value: String) {
        self.value = value
    }
}

/// Represents permissions on a specific schema.
public struct SchemaPrivilege: Hashable {
    public let canCreate: Bool
    public let canUsage: Bool

    public init(canCreate: Bool, canUsage: Bool) {
        self.canCreate = canCreate
        self.canUsage = canUsage
    }
}

/// Represents permissions on a specific table.
public struct TablePrivilege: Hashable {
    public let isOwner: Bool
    public let canSelect: Bool
    public let canInsert: Bool
    public let canUpdate: Bool
    public let canDelete: Bool

    public init(isOwner: Bool, canSelect: Bool, canInsert: Bool, canUpdate: Bool, canDelete: Bool) {
        self.isOwner = isOwner
        self.canSelect = canSelect
        self.canInsert = canInsert
        self.canUpdate = canUpdate
        self.canDelete = canDelete
    }
}

// MARK: - Detailed Schema & Table Models for Overview Lists

/// Detailed schema metadata including ownership, relation count, size, and user permissions.
public struct SchemaDetail: Identifiable, Hashable {
    public var id: String { name }
    public let name: String
    public let oid: UInt32
    public let owner: String
    public let tableCount: Int
    public let totalSize: String
    public let isSystem: Bool
    public let canCreateTables: Bool

    public init(name: String, oid: UInt32, owner: String, tableCount: Int, totalSize: String, isSystem: Bool, canCreateTables: Bool) {
        self.name = name
        self.oid = oid
        self.owner = owner
        self.tableCount = tableCount
        self.totalSize = totalSize
        self.isSystem = isSystem
        self.canCreateTables = canCreateTables
    }
}

/// Detailed table metadata including row counts, storage sizes, and ownership.
public struct TableDetail: Identifiable, Hashable {
    public var id: String { "\(schema).\(name)" }
    public let schema: String
    public let name: String
    public let oid: UInt32
    public let tableType: TableType
    public let rowCount: Int64
    public let totalSize: String
    public let indexSize: String
    public let columnCount: Int
    public let isOwner: Bool
    public let canInsert: Bool

    public init(schema: String, name: String, oid: UInt32, tableType: TableType, rowCount: Int64, totalSize: String, indexSize: String, columnCount: Int, isOwner: Bool, canInsert: Bool = false) {
        self.schema = schema
        self.name = name
        self.oid = oid
        self.tableType = tableType
        self.rowCount = rowCount
        self.totalSize = totalSize
        self.indexSize = indexSize
        self.columnCount = columnCount
        self.isOwner = isOwner
        self.canInsert = canInsert
    }
}

// MARK: - Table Creation Model

/// Defines a new column in the visual table designer.
public struct NewColumnDefinition: Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var dataType: String
    public var isPrimaryKey: Bool
    public var isNullable: Bool
    public var defaultValue: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        dataType: String = "varchar(255)",
        isPrimaryKey: Bool = false,
        isNullable: Bool = true,
        defaultValue: String = ""
    ) {
        self.id = id
        self.name = name
        self.dataType = dataType
        self.isPrimaryKey = isPrimaryKey
        self.isNullable = isNullable
        self.defaultValue = defaultValue
    }
}

