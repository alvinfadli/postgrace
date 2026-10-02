import Foundation

/// Defines the scope of the export operation.
public enum ExportScope: Equatable, Hashable {
    case table(schema: String, table: String)
    case schema(name: String, tables: [String] = [])
    case database(name: String)

    public var title: String {
        switch self {
        case .table(let schema, let table):
            return "\(schema).\(table)"
        case .schema(let name, _):
            return "Schema: \(name)"
        case .database(let name):
            return "Database: \(name)"
        }
    }
}

/// Supported export file formats.
public enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    case sql = "SQL Script"
    case customDump = "PostgreSQL Dump (.dump)"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        case .sql: return "sql"
        case .customDump: return "dump"
        }
    }

    public var description: String {
        switch self {
        case .csv:
            return "Comma-separated values (RFC 4180)"
        case .json:
            return "Structured JSON array or NDJSON"
        case .sql:
            return "SQL INSERT / CREATE DDL statements"
        case .customDump:
            return "Binary compressed archive (pg_dump -Fc)"
        }
    }
}

/// JSON export flavor.
public enum JSONExportFlavor: String, CaseIterable, Identifiable {
    case array = "Standard JSON Array"
    case ndjson = "Newline Delimited JSON (NDJSON)"

    public var id: String { rawValue }
}

/// Configuration parameters for an export task.
public struct ExportConfiguration: Equatable {
    public var scope: ExportScope
    public var format: ExportFormat
    public var destinationURL: URL?

    // Table export options
    public var whereClause: String = ""
    public var limit: Int? = nil
    public var csvDelimiter: String = ","
    public var csvIncludeHeaders: Bool = true
    public var csvIncludeBOM: Bool = false
    public var jsonFlavor: JSONExportFlavor = .array
    public var sqlBatchSize: Int = 200
    public var sqlIncludeDropTable: Bool = false

    // Schema/Database export options
    public var exportStructure: Bool = true
    public var exportData: Bool = true
    public var cleanBeforeRestore: Bool = true

    public init(scope: ExportScope, format: ExportFormat = .csv, destinationURL: URL? = nil) {
        self.scope = scope
        self.format = format
        self.destinationURL = destinationURL
    }

    /// Default suggested filename based on scope and format.
    public var suggestedFileName: String {
        let baseName: String
        switch scope {
        case .table(let schema, let table):
            baseName = "\(schema)_\(table)"
        case .schema(let name, _):
            baseName = "schema_\(name)"
        case .database(let name):
            baseName = "db_\(name)"
        }
        return "\(baseName)_\(Self.timestampString).\(format.fileExtension)"
    }

    private static var timestampString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: Date())
    }
}
