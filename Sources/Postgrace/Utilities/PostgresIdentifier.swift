import Foundation

extension String {
    /// Safely quotes an identifier for PostgreSQL (e.g. table, schema, column name).
    /// Escapes embedded double quotes by doubling them per SQL-92 / PostgreSQL standard.
    public var pgQuotedIdentifier: String {
        "\"" + self.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Safely escapes a string literal for PostgreSQL by doubling single quotes and stripping NUL bytes.
    public var pgEscapedLiteral: String {
        self.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "'", with: "''")
    }

    /// Safely quotes an identifier for MySQL and MariaDB using backticks.
    /// Escapes embedded backticks by doubling them.
    public var mysqlQuotedIdentifier: String {
        "`" + self.replacingOccurrences(of: "`", with: "``") + "`"
    }

    /// Safely escapes a string literal for MySQL and MariaDB, stripping NUL bytes.
    public var mysqlEscapedLiteral: String {
        self.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "''")
    }

    /// Quotes an identifier dynamically based on active database engine.
    public func quotedIdentifier(for engine: DatabaseEngine) -> String {
        engine.quoteIdentifier(self)
    }
}
