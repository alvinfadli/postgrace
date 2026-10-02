import Foundation

/// Service for introspecting PostgreSQL database schemas.
public actor SchemaService {
    private let postgresService: PostgresService
    
    public init(postgresService: PostgresService) {
        self.postgresService = postgresService
    }
    
    /// Fetches all databases with owners, encodings, sizes, and ownership status.
    public func fetchDatabases() async throws -> [DatabaseInfo] {
        let query = """
            SELECT d.datname,
                   d.oid,
                   pg_catalog.pg_get_userbyid(d.datdba) AS owner,
                   pg_catalog.pg_encoding_to_char(d.encoding) AS encoding,
                   pg_catalog.pg_size_pretty(pg_catalog.pg_database_size(d.oid)) AS size,
                   (pg_has_role(current_user, d.datdba, 'MEMBER') OR (SELECT COALESCE(rolsuper, false) FROM pg_roles WHERE rolname = current_user)) AS is_owner
            FROM pg_database d
            WHERE d.datistemplate = false
            ORDER BY d.datname ASC;
        """
        let result = try await postgresService.executeQuery(query)
        
        var databases: [DatabaseInfo] = []
        for row in result.rows {
            guard row.count >= 2,
                  case .string(let name) = row[0],
                  case .int(let oid) = row[1] else { continue }
            
            let owner: String = {
                if row.count >= 3, case .string(let o) = row[2] { return o }
                return "postgres"
            }()
            let encoding: String = {
                if row.count >= 4, case .string(let e) = row[3] { return e }
                return "UTF8"
            }()
            let size: String = {
                if row.count >= 5, case .string(let s) = row[4] { return s }
                return "0 bytes"
            }()
            let isOwner: Bool = {
                if row.count >= 6, case .bool(let b) = row[5] { return b }
                return false
            }()

            databases.append(DatabaseInfo(
                name: name,
                oid: UInt32(oid),
                owner: owner,
                encoding: encoding,
                size: size,
                isOwner: isOwner
            ))
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
    
    /// Fetches all tables, views, and relation kinds for a given schema.
    public func fetchTables(schema: String) async throws -> [TableInfo] {
        let query = """
            SELECT c.relname,
                   c.oid,
                   GREATEST(
                       0,
                       COALESCE(
                           NULLIF(c.reltuples::bigint, -1),
                           s.n_live_tup,
                           0
                       )
                   ) AS estimated_row_count,
                   CASE c.relkind
                       WHEN 'r' THEN 'BASE TABLE'
                       WHEN 'p' THEN 'BASE TABLE'
                       WHEN 'v' THEN 'VIEW'
                       WHEN 'm' THEN 'MATERIALIZED VIEW'
                       WHEN 'f' THEN 'FOREIGN TABLE'
                       ELSE 'BASE TABLE'
                   END AS table_type
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
            WHERE n.nspname = '\(schema.pgEscapedLiteral)'
              AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
            ORDER BY c.relname ASC;
        """
        let result = try await postgresService.executeQuery(query)
        
        var tables: [TableInfo] = []
        for row in result.rows {
            guard row.count >= 4,
                  case .string(let name) = row[0] else { continue }
            
            let oid: UInt32 = {
                if case .int(let o) = row[1] { return UInt32(o) }
                return 0
            }()
            
            let rowCount: Int64 = {
                if case .int(let rc) = row[2] { return max(0, rc) }
                if case .double(let d) = row[2] { return max(0, Int64(d)) }
                return 0
            }()
            
            let typeStr: String = {
                if case .string(let t) = row[3] { return t }
                return "BASE TABLE"
            }()
            
            let tableType = TableType(rawValue: typeStr) ?? .table
            tables.append(TableInfo(
                schema: schema,
                name: name,
                oid: oid,
                estimatedRowCount: rowCount,
                tableType: tableType
            ))
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
            WHERE c.table_schema = '\(schema.pgEscapedLiteral)' AND c.table_name = '\(table.pgEscapedLiteral)'
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
            WHERE schemaname = '\(schema.pgEscapedLiteral)' AND tablename = '\(table.pgEscapedLiteral)';
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
            WHERE n.nspname = '\(schema.pgEscapedLiteral)';
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
            LEFT JOIN pg_class c ON c.relnamespace = n.oid AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
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

    /// Fetches detailed table metadata for a specific schema with accurate row counts.
    public func fetchTableDetails(schema: String) async throws -> [TableDetail] {
        let query = """
            SELECT c.relname,
                   c.oid,
                   CASE c.relkind
                       WHEN 'r' THEN 'BASE TABLE'
                       WHEN 'p' THEN 'BASE TABLE'
                       WHEN 'v' THEN 'VIEW'
                       WHEN 'm' THEN 'MATERIALIZED VIEW'
                       WHEN 'f' THEN 'FOREIGN TABLE'
                       ELSE 'BASE TABLE'
                   END AS table_type,
                   GREATEST(
                       0,
                       COALESCE(
                           NULLIF(c.reltuples::bigint, -1),
                           s.n_live_tup,
                           0
                       )
                   ) AS est_row_count,
                   pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
                   pg_size_pretty(pg_indexes_size(c.oid)) AS index_size,
                   (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = n.nspname AND table_name = c.relname)::int AS col_count,
                   (pg_has_role(current_user, c.relowner, 'MEMBER') OR (SELECT usesuper FROM pg_user WHERE usename = current_user)) AS is_owner,
                   has_table_privilege(current_user, c.oid, 'INSERT') AS can_insert,
                   c.relkind,
                   has_table_privilege(current_user, c.oid, 'SELECT') AS can_select,
                   c.relpages
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            LEFT JOIN pg_stat_user_tables s ON s.relid = c.oid
            WHERE n.nspname = '\(schema.pgEscapedLiteral)'
              AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
            ORDER BY c.relname ASC;
        """
        let result = try await postgresService.executeQuery(query)
        var details: [TableDetail] = []
        var eligibleForExactCount: [String] = []

        for row in result.rows {
            guard row.count >= 9,
                  case .string(let name) = row[0] else { continue }

            let oid: UInt32 = {
                if case .int(let o) = row[1] { return UInt32(o) }
                return 0
            }()

            let typeStr: String = {
                if case .string(let t) = row[2] { return t }
                return "BASE TABLE"
            }()

            let rowCount: Int64 = {
                if case .int(let rc) = row[3] { return max(0, rc) }
                if case .double(let d) = row[3] { return max(0, Int64(d)) }
                return 0
            }()

            let totalSize: String = {
                if case .string(let s) = row[4] { return s }
                return "0 bytes"
            }()

            let indexSize: String = {
                if case .string(let s) = row[5] { return s }
                return "0 bytes"
            }()

            let colCount: Int = {
                if case .int(let c) = row[6] { return Int(c) }
                return 0
            }()

            let isOwner: Bool = {
                if case .bool(let b) = row[7] { return b }
                return false
            }()

            let canInsert: Bool = {
                if case .bool(let b) = row[8] { return b }
                return false
            }()

            let relkind: String = {
                if row.count >= 10, case .string(let k) = row[9] { return k }
                return "r"
            }()

            let canSelect: Bool = {
                if row.count >= 11, case .bool(let b) = row[10] { return b }
                return true
            }()

            let relpages: Int64 = {
                if row.count >= 12, case .int(let p) = row[11] { return p }
                return 0
            }()

            // Base tables or partitioned tables under ~100MB disk size are eligible for live exact COUNT(*)
            if (relkind == "r" || relkind == "p" || relkind == "m") && canSelect && relpages <= 12500 {
                eligibleForExactCount.append(name)
            }

            let tableType = TableType(rawValue: typeStr) ?? .table
            details.append(TableDetail(
                schema: schema,
                name: name,
                oid: oid,
                tableType: tableType,
                rowCount: rowCount,
                totalSize: totalSize,
                indexSize: indexSize,
                columnCount: colCount,
                isOwner: isOwner,
                canInsert: canInsert
            ))
        }

        // Fetch accurate live row counts for eligible tables
        if !eligibleForExactCount.isEmpty {
            let exactCounts = await fetchAccurateRowCounts(schema: schema, tableNames: eligibleForExactCount)
            for i in 0..<details.count {
                if let exact = exactCounts[details[i].name] {
                    details[i].rowCount = exact
                }
            }
        }

        return details
    }

    /// Fetches the live row count for a specific table.
    public func fetchTableRowCount(schema: String, table: String) async throws -> Int64 {
        try await postgresService.fetchTableRowCount(schema: schema, table: table)
    }

    /// Fetches live, accurate row counts for a batch of tables in a schema using optimized batch queries.
    public func fetchAccurateRowCounts(schema: String, tableNames: [String]) async -> [String: Int64] {
        guard !tableNames.isEmpty else { return [:] }
        var counts: [String: Int64] = [:]

        let chunkSize = 25
        for chunkStart in stride(from: 0, to: tableNames.count, by: chunkSize) {
            let chunk = Array(tableNames[chunkStart..<min(chunkStart + chunkSize, tableNames.count)])
            let unionSql = chunk.map { tbl in
                "SELECT '\(tbl.pgEscapedLiteral)' AS tbl, COUNT(*)::bigint AS cnt FROM \(schema.pgQuotedIdentifier).\(tbl.pgQuotedIdentifier)"
            }.joined(separator: " UNION ALL ")

            do {
                let res = try await postgresService.executeQuery(unionSql)
                for row in res.rows {
                    if row.count >= 2,
                       case .string(let tbl) = row[0] {
                        if case .int(let cnt) = row[1] {
                            counts[tbl] = cnt
                        } else if case .string(let str) = row[1], let cnt = Int64(str) {
                            counts[tbl] = cnt
                        }
                    }
                }
            } catch {
                // If the batch fails (e.g. locks or specific table error), try individually
                for tbl in chunk {
                    if let cnt = try? await postgresService.fetchTableRowCount(schema: schema, table: tbl) {
                        counts[tbl] = cnt
                    }
                }
            }
        }

        return counts
    }

    // MARK: - Schema CRUD

    /// Creates a new schema.
    public func createSchema(name: String, authorization: String? = nil) async throws {
        var sql = "CREATE SCHEMA \(name.pgQuotedIdentifier)"
        if let auth = authorization, !auth.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sql += " AUTHORIZATION \(auth.pgQuotedIdentifier)"
        }
        _ = try await postgresService.executeQuery(sql)
    }

    /// Renames an existing schema.
    public func renameSchema(from oldName: String, to newName: String) async throws {
        let sql = "ALTER SCHEMA \(oldName.pgQuotedIdentifier) RENAME TO \(newName.pgQuotedIdentifier);"
        _ = try await postgresService.executeQuery(sql)
    }

    /// Drops a schema with optional CASCADE.
    public func dropSchema(name: String, cascade: Bool = false) async throws {
        let mode = cascade ? "CASCADE" : "RESTRICT"
        let sql = "DROP SCHEMA \(name.pgQuotedIdentifier) \(mode);"
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
            var def = "\(col.name.pgQuotedIdentifier) \(col.dataType)"
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

        let sql = "CREATE TABLE \(schema.pgQuotedIdentifier).\(name.pgQuotedIdentifier) (\n  " + colDefs.joined(separator: ",\n  ") + "\n);"
        _ = try await postgresService.executeQuery(sql)
    }

    /// Renames a table.
    public func renameTable(schema: String, from oldName: String, to newName: String) async throws {
        let sql = "ALTER TABLE \(schema.pgQuotedIdentifier).\(oldName.pgQuotedIdentifier) RENAME TO \(newName.pgQuotedIdentifier);"
        _ = try await postgresService.executeQuery(sql)
    }

    /// Truncates a table.
    public func truncateTable(schema: String, name: String, restartIdentity: Bool = true, cascade: Bool = false) async throws {
        var sql = "TRUNCATE TABLE \(schema.pgQuotedIdentifier).\(name.pgQuotedIdentifier)"
        if restartIdentity { sql += " RESTART IDENTITY" }
        if cascade { sql += " CASCADE" } else { sql += " RESTRICT" }
        _ = try await postgresService.executeQuery(sql)
    }

    /// Drops a table with optional CASCADE.
    public func dropTable(schema: String, name: String, cascade: Bool = false) async throws {
        let mode = cascade ? "CASCADE" : "RESTRICT"
        let sql = "DROP TABLE \(schema.pgQuotedIdentifier).\(name.pgQuotedIdentifier) \(mode);"
        _ = try await postgresService.executeQuery(sql)
    }

    // MARK: - Database Lifecycle (Create & Drop)

    /// Creates a new PostgreSQL database with optional owner, encoding, template, and connection limit.
    public func createDatabase(
        name: String,
        owner: String? = nil,
        encoding: String? = nil,
        template: String? = nil,
        connectionLimit: Int? = nil
    ) async throws {
        var sql = "CREATE DATABASE \(name.pgQuotedIdentifier)"
        var options: [String] = []

        if let owner = owner?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty {
            options.append("OWNER \(owner.pgQuotedIdentifier)")
        }
        if let encoding = encoding?.trimmingCharacters(in: .whitespacesAndNewlines), !encoding.isEmpty {
            options.append("ENCODING '\(encoding.pgEscapedLiteral)'")
        }
        if let template = template?.trimmingCharacters(in: .whitespacesAndNewlines), !template.isEmpty {
            options.append("TEMPLATE \(template.pgQuotedIdentifier)")
        }
        if let limit = connectionLimit, limit >= -1 {
            options.append("CONNECTION LIMIT \(limit)")
        }

        if !options.isEmpty {
            sql += " " + options.joined(separator: " ")
        }
        _ = try await postgresService.executeQuery(sql)
    }

    /// Drops a PostgreSQL database with optional FORCE mode (terminates active connections first).
    public func dropDatabase(name: String, force: Bool = false) async throws {
        if force {
            // Terminate backends connected to the database to drop
            _ = try? await postgresService.executeQuery("""
                SELECT pg_terminate_backend(pid)
                FROM pg_stat_activity
                WHERE datname = '\(name.pgEscapedLiteral)'
                  AND pid <> pg_backend_pid();
            """)

            // Attempt DROP DATABASE WITH (FORCE) in PostgreSQL 13+
            do {
                _ = try await postgresService.executeQuery("DROP DATABASE \(name.pgQuotedIdentifier) WITH (FORCE);")
                return
            } catch {
                // Fallback to standard DROP DATABASE if WITH (FORCE) is not supported
            }
        }

        _ = try await postgresService.executeQuery("DROP DATABASE \(name.pgQuotedIdentifier);")
    }
}
