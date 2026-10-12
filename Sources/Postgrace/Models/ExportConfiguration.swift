import Foundation

/// Represents a specific table to export.
public struct ExportTableItem: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { "\(schema).\(table)" }
    public var schema: String
    public var table: String

    public init(schema: String, table: String) {
        self.schema = schema
        self.table = table
    }
}

/// Advanced options specifically for PostgreSQL exports.
public struct PostgresExportOptions: Equatable, Sendable {
    public var includeSchemaCreate: Bool = true
    public var setPathHeader: Bool = true
    public var cleanBeforeRestore: Bool = true
    public var singleTransaction: Bool = true
    public var includeExternalForeignKeys: Bool = true
    public var customDumpCompressionLevel: Int = 6 // 1-9
    public var excludedSchemas: Set<String> = []

    public init() {}
}

/// Defines the scope of the export operation.
public enum ExportScope: Equatable, Hashable, Sendable {
    case table(schema: String, table: String)
    case multipleTables(items: [ExportTableItem])
    case schema(name: String, tables: [String] = [])
    case multipleSchemas(names: [String])
    case database(name: String)

    public var title: String {
        switch self {
        case .table(let schema, let table):
            return "\(schema).\(table)"
        case .multipleTables(let items):
            return items.count == 1 ? "\(items[0].schema).\(items[0].table)" : "Tables (\(items.count) selected)"
        case .schema(let name, _):
            return "Schema: \(name)"
        case .multipleSchemas(let names):
            return "Schemas (\(names.count) selected)"
        case .database(let name):
            return "Database: \(name)"
        }
    }
}

/// Supported export content modes (Structure, Data, or Both).
public enum ExportContentMode: String, CaseIterable, Identifiable, Sendable {
    case structureAndData = "Structure and Data"
    case structureOnly = "Structure Only (DDL)"
    case dataOnly = "Data Only"

    public var id: String { rawValue }

    public var description: String {
        switch self {
        case .structureAndData:
            return "Exports table definitions (CREATE TABLE DDL) and row records."
        case .structureOnly:
            return "Exports table schemas and constraints only (no data rows)."
        case .dataOnly:
            return "Exports row records only (no CREATE TABLE DDL)."
        }
    }
}

/// Supported export file formats.
public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
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
public enum JSONExportFlavor: String, CaseIterable, Identifiable, Sendable {
    case array = "Standard JSON Array"
    case ndjson = "Newline Delimited JSON (NDJSON)"

    public var id: String { rawValue }
}

/// Configuration parameters for an export task.
public struct ExportConfiguration: Equatable, Sendable {
    public var scope: ExportScope
    public var format: ExportFormat
    public var destinationURL: URL?

    // Content mode (Structure Only / Data Only / Both)
    public var contentMode: ExportContentMode = .structureAndData

    // Multi-table / multi-schema selection
    public var selectedTables: [ExportTableItem] = []
    public var selectedSchemas: [String] = []

    // Table export options
    public var whereClause: String = ""
    public var limit: Int? = nil
    public var csvDelimiter: String = ","
    public var csvIncludeHeaders: Bool = true
    public var csvIncludeBOM: Bool = false
    public var jsonFlavor: JSONExportFlavor = .array
    public var sqlBatchSize: Int = 200
    public var sqlIncludeDropTable: Bool = false

    // Advanced PostgreSQL options
    public var postgresOptions: PostgresExportOptions = PostgresExportOptions()

    // Schema/Database export options
    public var exportStructure: Bool {
        get { contentMode != .dataOnly }
        set {
            if newValue {
                contentMode = exportData ? .structureAndData : .structureOnly
            } else {
                contentMode = .dataOnly
            }
        }
    }

    public var exportData: Bool {
        get { contentMode != .structureOnly }
        set {
            if newValue {
                contentMode = exportStructure ? .structureAndData : .dataOnly
            } else {
                contentMode = .structureOnly
            }
        }
    }

    public var cleanBeforeRestore: Bool {
        get { postgresOptions.cleanBeforeRestore }
        set { postgresOptions.cleanBeforeRestore = newValue }
    }

    public init(scope: ExportScope, format: ExportFormat = .csv, destinationURL: URL? = nil) {
        self.scope = scope
        self.format = format
        self.destinationURL = destinationURL

        switch scope {
        case .table(let s, let t):
            self.selectedTables = [ExportTableItem(schema: s, table: t)]
        case .multipleTables(let items):
            self.selectedTables = items
        case .schema(let s, _):
            self.selectedSchemas = [s]
        case .multipleSchemas(let names):
            self.selectedSchemas = names
        case .database:
            break
        }
    }

    /// Default suggested filename based on scope, format, and content mode.
    public var suggestedFileName: String {
        let baseName: String
        switch scope {
        case .table(let schema, let table):
            baseName = "\(schema)_\(table)"
        case .multipleTables(let items):
            baseName = items.count == 1 ? "\(items[0].schema)_\(items[0].table)" : "tables_\(items.count)_items"
        case .schema(let name, _):
            baseName = "schema_\(name)"
        case .multipleSchemas(let names):
            baseName = "schemas_\(names.count)_items"
        case .database(let name):
            baseName = "db_\(name)"
        }

        let modeSuffix: String
        switch contentMode {
        case .structureOnly:
            modeSuffix = "_structure"
        case .dataOnly:
            modeSuffix = "_data"
        case .structureAndData:
            modeSuffix = ""
        }

        return "\(baseName)\(modeSuffix)_\(Self.timestampString).\(format.fileExtension)"
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private static var timestampString: String {
        timestampFormatter.string(from: Date())
    }
}
