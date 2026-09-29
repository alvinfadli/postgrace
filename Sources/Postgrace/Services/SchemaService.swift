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
}
