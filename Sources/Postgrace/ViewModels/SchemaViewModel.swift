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
    public var databases: [DatabaseInfo] = []
    public var accurateRowCounts: [String: Int64] = [:]
    public var isLoadingRowCount: [String: Bool] = [:]
    public var userPrivileges: UserPrivilegeInfo?
    public var selectedSchema: SchemaInfo?
    public var selectedTable: TableInfo?
    public var isLoading: Bool = false
    public var isDatabaseActionInProgress: Bool = false
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

    // MARK: - Database Eligibility & Roles

    /// Whether the connected user has permission to create databases (Superuser or CREATEDB role).
    public var canCreateDatabase: Bool {
        guard let privs = userPrivileges else { return true }
        return privs.isSuperuser || privs.canCreateDb
    }

    /// Checks whether the user can drop a specified database.
    public func canDropDatabase(_ db: DatabaseInfo, currentDatabase: String?) -> (allowed: Bool, reason: String?) {
        if let current = currentDatabase, db.name == current {
            return (false, "Cannot drop active database '\(db.name)' while connected to it. Switch to another database (such as 'postgres') first.")
        }
        guard let privs = userPrivileges else { return (true, nil) }
        if privs.isSuperuser || db.isOwner { return (true, nil) }
        return (false, "Only the database owner ('\(db.owner)') or a superuser can drop this database.")
    }

    // MARK: - Schema Browsing & Introspection

    /// Fetches all available databases on the connected server instance.
    public func loadAvailableDatabases() async -> [DatabaseInfo] {
        do {
            let dbs = try await schemaService.fetchDatabases()
            self.databases = dbs
            return dbs
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
            let details = try await schemaService.fetchTableDetails(schema: schema)
            tableDetails[schema] = details
            for d in details {
                accurateRowCounts["\(schema).\(d.name)"] = d.rowCount
            }
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

    // MARK: - Live Accurate Row Counts

    /// Returns the most accurate row count available for a table (exact count if loaded, fallback to detail/estimate).
    public func accurateRowCount(for table: TableInfo) -> Int64 {
        let key = "\(table.schema).\(table.name)"
        if let exact = accurateRowCounts[key] {
            return exact
        }
        if let detail = tableDetails[table.schema]?.first(where: { $0.name == table.name }) {
            return detail.rowCount
        }
        return table.estimatedRowCount
    }

    /// Fetches the accurate live row count for a specific table on demand.
    @discardableResult
    public func loadAccurateRowCount(schema: String, table: String, forceRefresh: Bool = false) async -> Int64? {
        let key = "\(schema).\(table)"
        if !forceRefresh, let existing = accurateRowCounts[key] {
            return existing
        }

        isLoadingRowCount[key] = true
        defer { isLoadingRowCount[key] = false }

        do {
            let count = try await schemaService.fetchTableRowCount(schema: schema, table: table)
            setAccurateRowCount(schema: schema, table: table, count: count)
            return count
        } catch {
            return nil
        }
    }

    /// Manually sets or syncs the accurate row count (e.g. from DataGridViewModel or after DDL/DML).
    public func setAccurateRowCount(schema: String, table: String, count: Int64) {
        let key = "\(schema).\(table)"
        accurateRowCounts[key] = count

        // Update in tableDetails
        if let idx = tableDetails[schema]?.firstIndex(where: { $0.name == table }) {
            tableDetails[schema]?[idx].rowCount = count
        }

        // Update in tables
        if let idx = tables[schema]?.firstIndex(where: { $0.name == table }) {
            tables[schema]?[idx].estimatedRowCount = count
        }
    }

    /// Refresh all schema data and user privileges.
    public func refresh() async {
        tables.removeAll()
        columns.removeAll()
        tableDetails.removeAll()
        accurateRowCounts.removeAll()
        isLoadingRowCount.removeAll()
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

    // MARK: - Database CRUD Lifecycle

    /// Creates a new PostgreSQL database with role eligibility check.
    public func createDatabase(
        name: String,
        owner: String? = nil,
        encoding: String? = nil,
        template: String? = nil,
        connectionLimit: Int? = nil
    ) async throws {
        crudError = nil
        guard canCreateDatabase else {
            let msg = "User '\(userPrivileges?.username ?? "")' lacks CREATEDB or SUPERUSER privileges to create databases."
            crudError = msg
            throw PostgresServiceError.queryFailed(msg)
        }

        isDatabaseActionInProgress = true
        defer { isDatabaseActionInProgress = false }

        do {
            try await schemaService.createDatabase(
                name: name,
                owner: owner,
                encoding: encoding,
                template: template,
                connectionLimit: connectionLimit
            )
            _ = await loadAvailableDatabases()
        } catch {
            crudError = error.localizedDescription
            throw error
        }
    }

    /// Drops a database with permission check and active database protection.
    public func dropDatabase(name: String, force: Bool = false, currentDatabase: String? = nil) async throws {
        crudError = nil
        if let current = currentDatabase, name == current {
            let msg = "Cannot drop active database '\(name)' while connected to it. Switch to another database first."
            crudError = msg
            throw PostgresServiceError.queryFailed(msg)
        }

        isDatabaseActionInProgress = true
        defer { isDatabaseActionInProgress = false }

        do {
            try await schemaService.dropDatabase(name: name, force: force)
            _ = await loadAvailableDatabases()
        } catch {
            crudError = error.localizedDescription
            throw error
        }
    }
}
