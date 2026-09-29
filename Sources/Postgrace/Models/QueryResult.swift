import Foundation

/// Represents a single value from a database cell.
public enum CellValue: Hashable {
    case null
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case date(String)
    case json(String)
    case data(Data)
    case array(String) // Simplified array representation
    
    /// A displayable string representation of the cell value.
    public var displayString: String {
        switch self {
        case .null:
            return "NULL"
        case .string(let s):
            return s
        case .int(let i):
            return String(i)
        case .double(let d):
            return String(d)
        case .bool(let b):
            return b ? "true" : "false"
        case .date(let d):
            return d
        case .json(let j):
            return j
        case .data(let d):
            return "[\(d.count) bytes]"
        case .array(let a):
            return a
        }
    }
}

/// Metadata about a column in a query result.
public struct ResultColumn: Hashable {
    public let name: String
    public let dataTypeOID: UInt32
    public let dataTypeName: String
    
    public init(name: String, dataTypeOID: UInt32, dataTypeName: String) {
        self.name = name
        self.dataTypeOID = dataTypeOID
        self.dataTypeName = dataTypeName
    }
}

/// Contains the result of a SQL query execution.
public struct QueryResult: Hashable {
    /// The columns returned by the query.
    public let columns: [ResultColumn]
    /// The row data returned by the query.
    public let rows: [[CellValue]]
    /// The time taken to execute the query in seconds.
    public let executionTime: TimeInterval
    /// The number of rows affected by the query (e.g., for INSERT/UPDATE/DELETE).
    public let rowsAffected: Int
    /// A status message returned by the database.
    public let statusMessage: String
    
    public init(columns: [ResultColumn], rows: [[CellValue]], executionTime: TimeInterval, rowsAffected: Int, statusMessage: String) {
        self.columns = columns
        self.rows = rows
        self.executionTime = executionTime
        self.rowsAffected = rowsAffected
        self.statusMessage = statusMessage
    }
}
