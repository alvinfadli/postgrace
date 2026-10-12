import Foundation

/// Item representing a single SQL autocompletion or contextual suggestion.
public struct SQLCompletionItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let text: String
    public let insertText: String
    public let kind: Kind
    public let detail: String?

    public enum Kind: String, Sendable, CaseIterable {
        case keyword = "Keyword"
        case table = "Table"
        case column = "Column"
        case function = "Function"
        case clause = "Clause"
        case snippet = "Snippet"

        public var iconName: String {
            switch self {
            case .keyword: return "textformat"
            case .table: return "tablecells"
            case .column: return "number"
            case .function: return "function"
            case .clause: return "flowchart"
            case .snippet: return "doc.text"
            }
        }

        public var priority: Int {
            switch self {
            case .table: return 1
            case .column: return 2
            case .keyword: return 3
            case .function: return 4
            default: return 5
            }
        }
    }

    public init(text: String, insertText: String? = nil, kind: Kind, detail: String? = nil) {
        self.id = "\(kind.rawValue):\(text):\(insertText ?? text)"
        self.text = text
        self.insertText = insertText ?? text
        self.kind = kind
        self.detail = detail
    }
}

/// Service providing SQL autocompletion, keyword hints, and context-aware query helper chips.
public enum SQLAutocompleteService {

    // MARK: - Built-in Keywords & Functions

    public static let standardKeywords: [String] = [
        "SELECT", "FROM", "WHERE", "JOIN", "INNER JOIN", "LEFT JOIN", "RIGHT JOIN", "FULL JOIN",
        "CROSS JOIN", "ON", "GROUP BY", "ORDER BY", "HAVING", "LIMIT", "OFFSET",
        "INSERT INTO", "VALUES", "UPDATE", "SET", "DELETE FROM",
        "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "TRUNCATE", "CREATE INDEX",
        "DISTINCT", "AS", "AND", "OR", "NOT", "IN", "EXISTS", "BETWEEN",
        "LIKE", "ILIKE", "IS NULL", "IS NOT NULL",
        "CASE", "WHEN", "THEN", "ELSE", "END",
        "UNION", "UNION ALL", "INTERSECT", "EXCEPT",
        "DESC", "ASC", "RETURNING", "CASCADE", "WITH"
    ]

    public static let standardFunctions: [(name: String, insert: String, detail: String)] = [
        ("COUNT(*)", "COUNT(*)", "Count all matching rows"),
        ("COUNT()", "COUNT()", "Count non-null values"),
        ("SUM()", "SUM()", "Sum of numeric values"),
        ("AVG()", "AVG()", "Average of numeric values"),
        ("MIN()", "MIN()", "Minimum value"),
        ("MAX()", "MAX()", "Maximum value"),
        ("NOW()", "NOW()", "Current timestamp with timezone"),
        ("COALESCE()", "COALESCE(, )", "Return first non-null argument"),
        ("CONCAT()", "CONCAT(, )", "Concatenate strings"),
        ("LOWER()", "LOWER()", "Convert string to lowercase"),
        ("UPPER()", "UPPER()", "Convert string to uppercase"),
        ("DATE_TRUNC()", "DATE_TRUNC('day', )", "Truncate timestamp to specified precision"),
        ("ROUND()", "ROUND(, 2)", "Round numeric value"),
        ("CAST()", "CAST( AS text)", "Cast value to target type"),
        ("GEN_RANDOM_UUID()", "GEN_RANDOM_UUID()", "Generate v4 UUID")
    ]

    // MARK: - Word Token Extraction

    /// Finds the current partial word token being typed directly before/at the cursor position.
    public static func currentWord(in text: String, at location: Int) -> (word: String, range: NSRange) {
        let nsString = text as NSString
        let loc = max(0, min(location, nsString.length))

        var start = loc
        while start > 0 {
            let prevChar = nsString.character(at: start - 1)
            // Allow alphanumeric, underscores, and dots (for table.column scoping)
            if let scalar = UnicodeScalar(prevChar),
               (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == ".") {
                start -= 1
            } else {
                break
            }
        }

        let range = NSRange(location: start, length: loc - start)
        let word = nsString.substring(with: range)
        return (word, range)
    }

    // MARK: - Autocomplete Suggestions

    /// Returns autocomplete suggestions based on the current word prefix and available schema metadata.
    public static func suggestions(
        for queryText: String,
        at cursorLocation: Int,
        tables: [String: [TableInfo]],
        columns: [String: [ColumnInfo]],
        schemas: [SchemaInfo]
    ) -> (prefix: String, replaceRange: NSRange, items: [SQLCompletionItem]) {
        let (rawWord, range) = currentWord(in: queryText, at: cursorLocation)
        let prefix = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else {
            return (prefix: "", replaceRange: range, items: [])
        }

        var results: [SQLCompletionItem] = []
        let lowerPrefix = prefix.lowercased()

        // 1. Scoped completion: e.g. "users." or "public."
        if prefix.contains(".") {
            let parts = prefix.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            let parent = parts.first?.lowercased() ?? ""
            let memberPrefix = parts.count > 1 ? parts[1].lowercased() : ""

            // Look for columns matching table `parent`
            for (key, cols) in columns {
                // key is "schema.table"
                let keyParts = key.split(separator: ".")
                let tableName = keyParts.last.map(String.init)?.lowercased() ?? ""

                if tableName == parent || key.lowercased() == parent {
                    for col in cols {
                        if memberPrefix.isEmpty || col.name.lowercased().hasPrefix(memberPrefix) {
                            results.append(SQLCompletionItem(
                                text: "\(parts[0]).\(col.name)",
                                insertText: col.name,
                                kind: .column,
                                detail: "\(col.dataType)\(col.isPrimaryKey ? " • PK" : "")"
                            ))
                        }
                    }
                }
            }

            // Look for tables matching schema `parent`
            if let schemaTables = tables[parent] {
                for tbl in schemaTables {
                    if memberPrefix.isEmpty || tbl.name.lowercased().hasPrefix(memberPrefix) {
                        results.append(SQLCompletionItem(
                            text: "\(parts[0]).\(tbl.name)",
                            insertText: tbl.name,
                            kind: .table,
                            detail: "Table (\(tbl.estimatedRowCount) rows)"
                        ))
                    }
                }
            }

            return (prefix: prefix, replaceRange: range, items: results)
        }

        // 2. Database Tables
        for (_, tblList) in tables {
            for tbl in tblList {
                if tbl.name.lowercased().hasPrefix(lowerPrefix) {
                    results.append(SQLCompletionItem(
                        text: tbl.name,
                        insertText: tbl.name,
                        kind: .table,
                        detail: "Table (\(tbl.estimatedRowCount) rows)"
                    ))
                }
            }
        }

        // 3. Database Columns
        var seenColumnNames = Set<String>()
        for (key, colList) in columns {
            let tableName = key.split(separator: ".").last.map(String.init) ?? ""
            for col in colList {
                if col.name.lowercased().hasPrefix(lowerPrefix) {
                    if seenColumnNames.insert(col.name).inserted {
                        results.append(SQLCompletionItem(
                            text: col.name,
                            insertText: col.name,
                            kind: .column,
                            detail: "\(col.dataType) • \(tableName)"
                        ))
                    }
                }
            }
        }

        // 4. SQL Keywords
        for kw in standardKeywords {
            if kw.lowercased().hasPrefix(lowerPrefix) {
                results.append(SQLCompletionItem(
                    text: kw,
                    insertText: kw,
                    kind: .keyword,
                    detail: "SQL Keyword"
                ))
            }
        }

        // 5. Built-in SQL Functions
        for fn in standardFunctions {
            if fn.name.lowercased().hasPrefix(lowerPrefix) {
                results.append(SQLCompletionItem(
                    text: fn.name,
                    insertText: fn.insert,
                    kind: .function,
                    detail: fn.detail
                ))
            }
        }

        // Rank results: exact case-insensitive match first, tables & columns prioritized
        results.sort { a, b in
            let aExact = a.text.caseInsensitiveCompare(prefix) == .orderedSame
            let bExact = b.text.caseInsensitiveCompare(prefix) == .orderedSame
            if aExact != bExact { return aExact && !bExact }

            let aPriority = a.kind.priority
            let bPriority = b.kind.priority
            if aPriority != bPriority { return aPriority < bPriority }
            return a.text.count < b.text.count
        }

        return (prefix: prefix, replaceRange: range, items: Array(results.prefix(15)))
    }

    // MARK: - Context-Aware Helper Chips

    /// Generates quick contextual suggestion chips based on recent keywords before cursor.
    public static func contextualChips(
        for queryText: String,
        at cursorLocation: Int,
        tables: [String: [TableInfo]],
        columns: [String: [ColumnInfo]]
    ) -> [SQLCompletionItem] {
        let nsString = queryText as NSString
        let loc = max(0, min(cursorLocation, nsString.length))
        let beforeText = nsString.substring(to: loc).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        var chips: [SQLCompletionItem] = []

        let allTables: [TableInfo] = tables.values.flatMap { $0 }

        // Start of statement / empty editor
        if beforeText.isEmpty || beforeText.hasSuffix(";") {
            chips.append(SQLCompletionItem(text: "SELECT * FROM ...", insertText: "SELECT * FROM ", kind: .snippet, detail: "Query all columns"))
            chips.append(SQLCompletionItem(text: "INSERT INTO ...", insertText: "INSERT INTO ", kind: .snippet, detail: "Insert rows"))
            chips.append(SQLCompletionItem(text: "UPDATE ... SET", insertText: "UPDATE  SET ", kind: .snippet, detail: "Update rows"))
            chips.append(SQLCompletionItem(text: "CREATE TABLE ...", insertText: "CREATE TABLE ", kind: .snippet, detail: "Define new table"))
            return chips
        }

        // Just typed SELECT
        if beforeText.hasSuffix("SELECT") || beforeText.hasSuffix("SELECT DISTINCT") {
            chips.append(SQLCompletionItem(text: "*", insertText: "* ", kind: .keyword, detail: "All columns"))
            chips.append(SQLCompletionItem(text: "COUNT(*)", insertText: "COUNT(*) ", kind: .function, detail: "Total count"))
            chips.append(SQLCompletionItem(text: "DISTINCT", insertText: "DISTINCT ", kind: .keyword, detail: "Unique rows"))

            // Suggest top columns if available
            var added = 0
            for (_, cols) in columns {
                for col in cols where added < 3 {
                    chips.append(SQLCompletionItem(text: col.name, insertText: "\(col.name), ", kind: .column, detail: col.dataType))
                    added += 1
                }
            }
            return chips
        }

        // Just typed FROM or JOIN
        if beforeText.hasSuffix("FROM") || beforeText.hasSuffix("JOIN") || beforeText.hasSuffix("INTO") || beforeText.hasSuffix("UPDATE") {
            for tbl in allTables.prefix(6) {
                chips.append(SQLCompletionItem(text: tbl.name, insertText: "\(tbl.name) ", kind: .table, detail: "\(tbl.estimatedRowCount) rows"))
            }
            return chips
        }

        // Just typed WHERE or HAVING
        if beforeText.hasSuffix("WHERE") || beforeText.hasSuffix("AND") || beforeText.hasSuffix("OR") || beforeText.hasSuffix("HAVING") {
            chips.append(SQLCompletionItem(text: "id = 1", insertText: "id = ", kind: .snippet, detail: "Filter by identifier"))
            chips.append(SQLCompletionItem(text: "IS NOT NULL", insertText: "IS NOT NULL ", kind: .keyword, detail: "Exclude nulls"))
            chips.append(SQLCompletionItem(text: "LIKE '%...%'", insertText: "LIKE '%", kind: .snippet, detail: "Pattern match"))
            chips.append(SQLCompletionItem(text: "IN (...)", insertText: "IN ()", kind: .snippet, detail: "List containment"))

            // Suggest columns
            var added = 0
            for (_, cols) in columns {
                for col in cols where added < 3 {
                    chips.append(SQLCompletionItem(text: col.name, insertText: "\(col.name) = ", kind: .column, detail: col.dataType))
                    added += 1
                }
            }
            return chips
        }

        // After a table or clause is present, suggest standard continuation clauses
        chips.append(SQLCompletionItem(text: "WHERE", insertText: "WHERE ", kind: .clause, detail: "Filter rows"))
        chips.append(SQLCompletionItem(text: "ORDER BY", insertText: "ORDER BY ", kind: .clause, detail: "Sort order"))
        chips.append(SQLCompletionItem(text: "LIMIT 100", insertText: "LIMIT 100", kind: .clause, detail: "Limit result set"))
        chips.append(SQLCompletionItem(text: "JOIN", insertText: "INNER JOIN ", kind: .clause, detail: "Join table"))
        chips.append(SQLCompletionItem(text: "GROUP BY", insertText: "GROUP BY ", kind: .clause, detail: "Aggregate rows"))

        return chips
    }
}
