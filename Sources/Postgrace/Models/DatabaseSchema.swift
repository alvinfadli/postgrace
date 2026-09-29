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
