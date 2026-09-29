import Foundation

/// Service for introspecting PostgreSQL database schemas.
public actor SchemaService {
    private let postgresService: PostgresService
    
    public init(postgresService: PostgresService) {
        self.postgresService = postgresService
    }
    
    /// Fetches all databases.
    public func fetchDatabases() async throws -> [DatabaseInfo] {
        let query = "SELECT datname, oid FROM pg_database WHERE datistemplate = false;"
        let result = try await postgresService.executeQuery(query)
        
        var databases: [DatabaseInfo] = []
        for row in result.rows {
            if row.count >= 2,
               case .string(let name) = row[0],
               case .int(let oid) = row[1] {
                databases.append(DatabaseInfo(name: name, oid: UInt32(oid)))
            }
        }
        return databases
    }
    
    /// Fetches all schemas in the current database, excluding internal ones.
    public func fetchSchemas() async throws -> [SchemaInfo] {
        let query = """
            SELECT nspname, oid
            FROM pg_namespace
            WHERE nspname NOT LIKE 'pg_%' AND nspname != 'information_schema';
        """
        let result = try await postgresService.executeQuery(query)
        
        var schemas: [SchemaInfo] = []
        for row in result.rows {
            if row.count >= 2,
               case .string(let name) = row[0],
               case .int(let oid) = row[1] {
                schemas.append(SchemaInfo(name: name, oid: UInt32(oid)))
            }
        }
        return schemas
    }
    
    /// Fetches all tables and views for a given schema.
    public func fetchTables(schema: String) async throws -> [TableInfo] {
        // Requires parameterization in a real application. 
        // Using string interpolation here for structural demonstration; beware of SQL injection.
        let query = """
            SELECT c.relname, c.oid, c.reltuples::bigint as estimated_row_count,
                   t.table_type
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN information_schema.tables t ON t.table_name = c.relname AND t.table_schema = n.nspname
            WHERE n.nspname = '\(schema)'
              AND c.relkind IN ('r', 'v', 'm', 'f');
        """
        let result = try await postgresService.executeQuery(query)
        
        var tables: [TableInfo] = []
        for row in result.rows {
            if row.count >= 4,
               case .string(let name) = row[0],
               case .int(let oid) = row[1],
               case .int(let rowCount) = row[2],
               case .string(let typeStr) = row[3] {
                
                let tableType = TableType(rawValue: typeStr) ?? .table
                tables.append(TableInfo(schema: schema, name: name, oid: UInt32(oid), estimatedRowCount: rowCount, tableType: tableType))
            }
        }
        return tables
    }
    
    /// Fetches all columns for a given table.
    public func fetchColumns(schema: String, table: String) async throws -> [ColumnInfo] {
        let query = """
            SELECT c.column_name, c.ordinal_position, c.data_type, c.is_nullable, 
                   c.column_default, c.character_maximum_length,
                   CASE WHEN kcu.column_name IS NOT NULL THEN true ELSE false END as is_primary_key
            FROM information_schema.columns c
            LEFT JOIN information_schema.table_constraints tc 
                   ON tc.table_schema = c.table_schema AND tc.table_name = c.table_name AND tc.constraint_type = 'PRIMARY KEY'
            LEFT JOIN information_schema.key_column_usage kcu 
                   ON kcu.constraint_name = tc.constraint_name AND kcu.column_name = c.column_name
            WHERE c.table_schema = '\(schema)' AND c.table_name = '\(table)'
            ORDER BY c.ordinal_position;
        """
        let result = try await postgresService.executeQuery(query)
        
        var columns: [ColumnInfo] = []
        for row in result.rows {
            if row.count >= 7,
               case .string(let name) = row[0],
               case .int(let ord) = row[1],
               case .string(let type) = row[2],
               case .string(let isNullStr) = row[3] {
                
                let isPrimary = row[6] == .bool(true)
                let isNullable = isNullStr.lowercased() == "yes"
                let defVal: String? = { if case .string(let s) = row[4] { return s } else { return nil } }()
                let maxLen: Int? = { if case .int(let i) = row[5] { return Int(i) } else { return nil } }()
                
                columns.append(ColumnInfo(name: name, ordinalPosition: Int(ord), dataType: type, isNullable: isNullable, defaultValue: defVal, isPrimaryKey: isPrimary, characterMaxLength: maxLen))
            }
        }
        return columns
    }
    
    /// Fetches all indexes for a given table.
    public func fetchIndexes(schema: String, table: String) async throws -> [IndexInfo] {
        let query = """
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE schemaname = '\(schema)' AND tablename = '\(table)';
        """
        let result = try await postgresService.executeQuery(query)
        
        var indexes: [IndexInfo] = []
        for row in result.rows {
            if row.count >= 2,
               case .string(let name) = row[0],
               case .string(let def) = row[1] {
                let isUnique = def.contains("UNIQUE")
                let isPrimary = def.contains("PRIMARY KEY")
                indexes.append(IndexInfo(name: name, tableName: table, isUnique: isUnique, isPrimary: isPrimary, columns: []))
            }
        }
        return indexes
    }
    
    /// Fetches all functions in a given schema.
    public func fetchFunctions(schema: String) async throws -> [FunctionInfo] {
        let query = """
            SELECT p.proname, p.oid, pg_catalog.pg_get_function_result(p.oid) as return_type, 
                   pg_catalog.pg_get_function_arguments(p.oid) as arg_types, l.lanname
            FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            JOIN pg_language l ON l.oid = p.prolang
            WHERE n.nspname = '\(schema)';
        """
        let result = try await postgresService.executeQuery(query)
        
        var functions: [FunctionInfo] = []
        for row in result.rows {
            if row.count >= 5,
               case .string(let name) = row[0],
               case .int(let oid) = row[1],
               case .string(let retType) = row[2],
               case .string(let args) = row[3],
               case .string(let lang) = row[4] {
                functions.append(FunctionInfo(schema: schema, name: name, oid: UInt32(oid), returnType: retType, argumentTypes: args, language: lang))
            }
        }
        return functions
    }

    // MARK: - User Privilege & Permission Introspection

    /// Introspects the current connected user's privileges, roles, and object permissions.
    public func fetchUserPrivileges() async throws -> UserPrivilegeInfo {
        // 1. Current user global capabilities
        let userQuery = """
            SELECT current_user,
                   COALESCE((SELECT usesuper FROM pg_user WHERE usename = current_user), false) AS is_superuser,
                   COALESCE((SELECT usecreatedb FROM pg_user WHERE usename = current_user), false) AS can_create_db,
                   has_database_privilege(current_user, current_database(), 'CREATE') AS can_create_schema_in_db;
        """
        let userRes = try await postgresService.executeQuery(userQuery)
        var username = "unknown"
        var isSuper = false
        var canCreateDb = false
        var canCreateSchemaInDb = false
        if let row = userRes.rows.first, row.count >= 4 {
            if case .string(let u) = row[0] { username = u }
            if case .bool(let s) = row[1] { isSuper = s }
            if case .bool(let c) = row[2] { canCreateDb = c }
            if case .bool(let cs) = row[3] { canCreateSchemaInDb = cs }
        }

        // 2. Schema-level permissions
        let schemaQuery = """
            SELECT nspname,
                   has_schema_privilege(current_user, nspname, 'CREATE') AS can_create,
                   has_schema_privilege(current_user, nspname, 'USAGE') AS can_usage
            FROM pg_namespace;
        """
        let schemaRes = try await postgresService.executeQuery(schemaQuery)
        var schemaPerms: [String: SchemaPrivilege] = [:]
        for row in schemaRes.rows {
            if row.count >= 3,
               case .string(let nsp) = row[0],
               case .bool(let canCreate) = row[1],
               case .bool(let canUsage) = row[2] {
                schemaPerms[nsp] = SchemaPrivilege(canCreate: canCreate, canUsage: canUsage)
            }
        }

        // 3. Table-level permissions
        let tableQuery = """
            SELECT n.nspname || '.' || c.relname AS full_name,
                   (pg_has_role(current_user, c.relowner, 'MEMBER') OR \(isSuper)) AS is_owner,
                   has_table_privilege(current_user, c.oid, 'SELECT') AS can_select,
                   has_table_privilege(current_user, c.oid, 'INSERT') AS can_insert,
                   has_table_privilege(current_user, c.oid, 'UPDATE') AS can_update,
                   has_table_privilege(current_user, c.oid, 'DELETE') AS can_delete
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relkind IN ('r', 'v', 'm');
        """
        let tableRes = try await postgresService.executeQuery(tableQuery)
        var tablePerms: [String: TablePrivilege] = [:]
        for row in tableRes.rows {
            if row.count >= 6,
               case .string(let name) = row[0],
               case .bool(let isOwner) = row[1],
               case .bool(let canSel) = row[2],
               case .bool(let canIns) = row[3],
               case .bool(let canUpd) = row[4],
               case .bool(let canDel) = row[5] {
                tablePerms[name] = TablePrivilege(
                    isOwner: isOwner,
                    canSelect: canSel,
                    canInsert: canIns,
                    canUpdate: canUpd,
                    canDelete: canDel
                )
            }
        }

        return UserPrivilegeInfo(
            username: username,
            isSuperuser: isSuper,
            canCreateDb: canCreateDb,
            canCreateSchemaInDb: canCreateSchemaInDb,
            schemaPrivileges: schemaPerms,
            tablePrivileges: tablePerms
        )
    }

    // MARK: - Detailed Schema & Table Queries

    /// Fetches all schemas with ownership, table count, and disk size.
    public func fetchSchemaDetails() async throws -> [SchemaDetail] {
        let query = """
            SELECT n.nspname,
                   n.oid,
                   pg_get_userbyid(n.nspowner) AS owner_name,
                   COUNT(c.oid)::int AS table_count,
                   pg_size_pretty(COALESCE(SUM(pg_total_relation_size(c.oid)), 0)) AS total_size,
                   (n.nspname LIKE 'pg_%' OR n.nspname = 'information_schema') AS is_system,
                   has_schema_privilege(current_user, n.nspname, 'CREATE') AS can_create
            FROM pg_namespace n
            LEFT JOIN pg_class c ON c.relnamespace = n.oid AND c.relkind IN ('r', 'v', 'm', 'f')
            GROUP BY n.nspname, n.oid, n.nspowner
            ORDER BY is_system ASC, n.nspname ASC;
        """
        let result = try await postgresService.executeQuery(query)
        var details: [SchemaDetail] = []
        for row in result.rows {
            if row.count >= 7,
               case .string(let name) = row[0],
               case .int(let oid) = row[1],
               case .string(let owner) = row[2],
               case .int(let count) = row[3],
               case .string(let size) = row[4],
               case .bool(let isSys) = row[5],
               case .bool(let canCreate) = row[6] {
                details.append(SchemaDetail(
                    name: name,
                    oid: UInt32(oid),
                    owner: owner,
                    tableCount: Int(count),
                    totalSize: size,
                    isSystem: isSys,
                    canCreateTables: canCreate
                ))
            }
        }
        return details
    }

    /// Fetches detailed table metadata for a specific schema.
    public func fetchTableDetails(schema: String) async throws -> [TableDetail] {
        let query = """
            SELECT c.relname,
                   c.oid,
                   t.table_type,
                   c.reltuples::bigint AS est_row_count,
                   pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
                   pg_size_pretty(pg_indexes_size(c.oid)) AS index_size,
                   (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = n.nspname AND table_name = c.relname)::int AS col_count,
                   (pg_has_role(current_user, c.relowner, 'MEMBER') OR (SELECT usesuper FROM pg_user WHERE usename = current_user)) AS is_owner,
                   has_table_privilege(current_user, c.oid, 'INSERT') AS can_insert
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            JOIN information_schema.tables t ON t.table_name = c.relname AND t.table_schema = n.nspname
            WHERE n.nspname = '\(schema)'
              AND c.relkind IN ('r', 'v', 'm', 'f')
            ORDER BY c.relname ASC;
        """
        let result = try await postgresService.executeQuery(query)
        var details: [TableDetail] = []
        for row in result.rows {
            if row.count >= 9,
               case .string(let name) = row[0],
               case .int(let oid) = row[1],
               case .string(let typeStr) = row[2],
               case .int(let rowCount) = row[3],
               case .string(let totalSize) = row[4],
               case .string(let indexSize) = row[5],
               case .int(let colCount) = row[6],
               case .bool(let isOwner) = row[7],
               case .bool(let canInsert) = row[8] {
                let tableType = TableType(rawValue: typeStr) ?? .table
                details.append(TableDetail(
                    schema: schema,
                    name: name,
                    oid: UInt32(oid),
                    tableType: tableType,
                    rowCount: rowCount,
                    totalSize: totalSize,
                    indexSize: indexSize,
                    columnCount: Int(colCount),
                    isOwner: isOwner,
                    canInsert: canInsert
                ))
            }
        }
        return details
    }

    // MARK: - Schema CRUD

    /// Creates a new schema.
    public func createSchema(name: String, authorization: String? = nil) async throws {
        var sql = "CREATE SCHEMA \"\(name)\""
        if let auth = authorization, !auth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sql += " AUTHORIZATION \"\(auth)\""
        }
        _ = try await postgresService.executeQuery(sql)
    }

    /// Renames an existing schema.
    public func renameSchema(from oldName: String, to newName: String) async throws {
        let sql = "ALTER SCHEMA \"\(oldName)\" RENAME TO \"\(newName)\";"
        _ = try await postgresService.executeQuery(sql)
    }

    /// Drops a schema with optional CASCADE.
    public func dropSchema(name: String, cascade: Bool = false) async throws {
        let mode = cascade ? "CASCADE" : "RESTRICT"
        let sql = "DROP SCHEMA \"\(name)\" \(mode);"
        _ = try await postgresService.executeQuery(sql)
    }

    // MARK: - Table CRUD

    /// Creates a table with the given column definitions.
    public func createTable(schema: String, name: String, columns: [NewColumnDefinition]) async throws {
        guard !columns.isEmpty else {
            throw PostgresServiceError.queryFailed("Cannot create a table with no columns.")
        }

        var colDefs: [String] = []
        for col in columns {
            var def = "\"\(col.name)\" \(col.dataType)"
            if col.isPrimaryKey {
                def += " PRIMARY KEY"
            }
            if !col.isNullable {
                def += " NOT NULL"
            }
            let defVal = col.defaultValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !defVal.isEmpty {
                def += " DEFAULT \(defVal)"
            }
            colDefs.append(def)
        }

        let sql = "CREATE TABLE \"\(schema)\".\"\(name)\" (\n  " + colDefs.joined(separator: ",\n  ") + "\n);"
        _ = try await postgresService.executeQuery(sql)
    }

    /// Renames a table.
    public func renameTable(schema: String, from oldName: String, to newName: String) async throws {
        let sql = "ALTER TABLE \"\(schema)\".\"\(oldName)\" RENAME TO \"\(newName)\";"
        _ = try await postgresService.executeQuery(sql)
    }

    /// Truncates a table.
    public func truncateTable(schema: String, name: String, restartIdentity: Bool = true, cascade: Bool = false) async throws {
        var sql = "TRUNCATE TABLE \"\(schema)\".\"\(name)\""
        if restartIdentity { sql += " RESTART IDENTITY" }
        if cascade { sql += " CASCADE" } else { sql += " RESTRICT" }
        _ = try await postgresService.executeQuery(sql)
    }

    /// Drops a table with optional CASCADE.
    public func dropTable(schema: String, name: String, cascade: Bool = false) async throws {
        let mode = cascade ? "CASCADE" : "RESTRICT"
        let sql = "DROP TABLE \"\(schema)\".\"\(name)\" \(mode);"
        _ = try await postgresService.executeQuery(sql)
    }
}
