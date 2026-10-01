import Foundation

extension String {
    /// Safely quotes an identifier for PostgreSQL (e.g. table, schema, column name).
    /// Escapes embedded double quotes by doubling them per SQL-92 / PostgreSQL standard.
    public var pgQuotedIdentifier: String {
        "\"" + self.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Safely escapes a string literal for PostgreSQL by doubling single quotes.
    public var pgEscapedLiteral: String {
        self.replacingOccurrences(of: "'", with: "''")
    }
}
