import Foundation
import Observation

/// ViewModel for browsing database schemas, tables, and columns.
@Observable
public class SchemaViewModel {
    public var schemas: [SchemaInfo] = []
    public var tables: [String: [TableInfo]] = [:]
    public var columns: [String: [ColumnInfo]] = [:]
    public var selectedSchema: SchemaInfo?
    public var selectedTable: TableInfo?
    public var isLoading: Bool = false

    private let schemaService: SchemaService

    public init(schemaService: SchemaService) {
        self.schemaService = schemaService
    }

    /// Load all schemas from the connected database.
    public func loadSchemas() async {
        isLoading = true
        do {
            schemas = try await schemaService.fetchSchemas()
        } catch {
            print("Error loading schemas: \(error)")
        }
        isLoading = false
    }

    /// Load tables for a specific schema.
    public func loadTables(for schema: String) async {
        isLoading = true
        do {
            tables[schema] = try await schemaService.fetchTables(schema: schema)
        } catch {
            print("Error loading tables for \(schema): \(error)")
        }
        isLoading = false
    }

    /// Load columns for a specific table.
    public func loadColumns(for schema: String, table: String) async {
        let key = "\(schema).\(table)"
        isLoading = true
        do {
            columns[key] = try await schemaService.fetchColumns(schema: schema, table: table)
        } catch {
            print("Error loading columns for \(key): \(error)")
        }
        isLoading = false
    }

    /// Refresh all schema data.
    public func refresh() async {
        tables.removeAll()
        columns.removeAll()
        selectedSchema = nil
        selectedTable = nil
        await loadSchemas()
    }
}
