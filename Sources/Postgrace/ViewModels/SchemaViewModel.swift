import Foundation
import Observation

/// ViewModel for browsing database schemas, tables, columns, and managing full CRUD operations with permissions.
@Observable
public class SchemaViewModel {
    public var schemas: [SchemaInfo] = []
    public var tables: [String: [TableInfo]] = [:]
    public var columns: [String: [ColumnInfo]] = [:]
    public var schemaDetails: [SchemaDetail] = []
    public var tableDetails: [String: [TableDetail]] = [:]
    public var userPrivileges: UserPrivilegeInfo?
    public var selectedSchema: SchemaInfo?
    public var selectedTable: TableInfo?
    public var isLoading: Bool = false
    public var crudError: String?

    private let schemaService: SchemaService

    public init(schemaService: SchemaService) {
        self.schemaService = schemaService
    }

    // MARK: - User Privilege Inspection

    /// Loads the current logged-in user's roles and permissions.
    public func loadUserPrivileges() async {
        do {
            userPrivileges = try await schemaService.fetchUserPrivileges()
        } catch {
            print("Error loading user privileges: \(error)")
        }
    }

    // MARK: - Schema Browsing & Introspection

    /// Fetches all available databases on the connected server instance.
    public func loadAvailableDatabases() async -> [DatabaseInfo] {
        do {
            return try await schemaService.fetchDatabases()
        } catch {
            print("Error fetching databases: \(error)")
            return []
        }
    }

    /// Load all schemas from the connected database and prefetch public schema tables.
    public func loadSchemas() async {
        isLoading = true
        do {
            schemas = try await schemaService.fetchSchemas()
            if schemas.contains(where: { $0.name == "public" }) {
                await loadTables(for: "public")
            }
        } catch {
            print("Error loading schemas: \(error)")
        }
        isLoading = false
    }

    /// Load detailed schema metadata (tables count, sizes, ownership, permissions).
    public func loadSchemaDetails() async {
        isLoading = true
        do {
            schemaDetails = try await schemaService.fetchSchemaDetails()
        } catch {
            print("Error loading schema details: \(error)")
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
            tables[schema] = []
        }
        isLoading = false
    }

    /// Load detailed table metadata for a specific schema.
    public func loadTableDetails(for schema: String) async {
        isLoading = true
        do {
            tableDetails[schema] = try await schemaService.fetchTableDetails(schema: schema)
        } catch {
            print("Error loading table details for \(schema): \(error)")
            tableDetails[schema] = []
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

    /// Refresh all schema data and user privileges.
    public func refresh() async {
        tables.removeAll()
        columns.removeAll()
        tableDetails.removeAll()
        selectedSchema = nil
        selectedTable = nil
        crudError = nil

        await loadUserPrivileges()
        await loadSchemas()
        await loadSchemaDetails()

        // Auto-prefetch public schema tables so the expanded sidebar tree is populated immediately
        if schemas.contains(where: { $0.name == "public" }) {
            await loadTables(for: "public")
        }
    }

    // MARK: - Schema CRUD Operations

    /// Creates a new schema in the active database.
    public func createSchema(name: String, owner: String? = nil) async throws {
        crudError = nil
        do {
            try await schemaService.createSchema(name: name, authorization: owner)
            await loadSchemas()
            await loadSchemaDetails()
        } catch {
            crudError = error.localizedDescription
            throw error
        }
    }

    /// Renames an existing schema.
    public func renameSchema(oldName: String, newName: String) async throws {
        crudError = nil
        do {
            try await schemaService.renameSchema(from: oldName, to: newName)
            await loadSchemas()
            await loadSchemaDetails()
        } catch {
            crudError = error.localizedDescription
            throw error
        }
    }

    /// Drops a schema.
    public func dropSchema(name: String, cascade: Bool = false) async throws {
        crudError = nil
        do {
            try await schemaService.dropSchema(name: name, cascade: cascade)
            tables.removeValue(forKey: name)
            tableDetails.removeValue(forKey: name)
            await loadSchemas()
            await loadSchemaDetails()
        } catch {
            crudError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Table CRUD Operations

    /// Creates a new table in the specified schema.
    public func createTable(schema: String, name: String, columns: [NewColumnDefinition]) async throws {
        crudError = nil
        do {
            try await schemaService.createTable(schema: schema, name: name, columns: columns)
            await loadTables(for: schema)
            await loadTableDetails(for: schema)
            await loadSchemaDetails()
        } catch {
            crudError = error.localizedDescription
            throw error
        }
    }

    /// Renames an existing table.
    public func renameTable(schema: String, oldName: String, newName: String) async throws {
        crudError = nil
        do {
            try await schemaService.renameTable(schema: schema, from: oldName, to: newName)
            await loadTables(for: schema)
            await loadTableDetails(for: schema)
        } catch {
            crudError = error.localizedDescription
            throw error
        }
    }

    /// Truncates all data in a table.
    public func truncateTable(schema: String, name: String) async throws {
        crudError = nil
        do {
            try await schemaService.truncateTable(schema: schema, name: name)
            await loadTableDetails(for: schema)
        } catch {
            crudError = error.localizedDescription
            throw error
        }
    }

    /// Drops an existing table.
    public func dropTable(schema: String, name: String, cascade: Bool = false) async throws {
        crudError = nil
        do {
            try await schemaService.dropTable(schema: schema, name: name, cascade: cascade)
            await loadTables(for: schema)
            await loadTableDetails(for: schema)
            await loadSchemaDetails()
        } catch {
            crudError = error.localizedDescription
            throw error
        }
    }
}
