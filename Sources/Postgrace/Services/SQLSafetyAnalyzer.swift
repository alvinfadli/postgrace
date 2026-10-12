import Foundation

/// Result of evaluating a SQL statement for destructive or mutating risks.
public struct SQLSafetyCheckResult: Identifiable, Equatable, Hashable {
    /// Whether the query is classified as dangerous in Safe Mode.
    public let isDangerous: Bool
    /// The high-level statement type (e.g., "DELETE", "UPDATE", "DROP", "TRUNCATE", "SELECT", "BATCH").
    public let statementType: String
    /// True if the statement modifies or deletes data without a WHERE clause (e.g. unbounded DELETE/UPDATE).
    public let isUnbounded: Bool
    /// The primary target table, schema, or database affected, if identifiable.
    public let targetObject: String?
    /// User-facing descriptive summary of the risk.
    public let description: String

    public var id: String {
        "\(statementType)_\(isUnbounded)_\(targetObject ?? "")_\(description)"
    }

    public init(
        isDangerous: Bool,
        statementType: String,
        isUnbounded: Bool = false,
        targetObject: String? = nil,
        description: String
    ) {
        self.isDangerous = isDangerous
        self.statementType = statementType
        self.isUnbounded = isUnbounded
        self.targetObject = targetObject
        self.description = description
    }
}

/// Client-side lexical analyzer that checks SQL statements prior to execution.
/// Fast (< 1 ms latency), zero network calls, strictly client-side.
public enum SQLSafetyAnalyzer {

    // MARK: - Internal Token Definition

    struct Token: Equatable {
        enum Kind: Equatable {
            case keyword(String)
            case identifier(String)
            case symbol(Character)
            case stringLiteral
        }

        let kind: Kind
        let text: String
        let parenDepth: Int
    }

    private static let knownKeywords: Set<String> = [
        "SELECT", "INSERT", "UPDATE", "DELETE", "DROP", "TRUNCATE", "ALTER", "CREATE",
        "TABLE", "DATABASE", "SCHEMA", "VIEW", "INDEX", "WHERE", "FROM", "INTO", "SET",
        "MERGE", "GRANT", "REVOKE", "VACUUM", "FULL", "EXPLAIN", "SHOW", "WITH", "DO",
        "ONLY", "IF", "EXISTS", "CASCADE", "RESTRICT", "BEGIN", "COMMIT", "ROLLBACK",
        "RESET", "CALL", "REPLACE", "UNIQUE", "COLUMN", "FUNCTION", "PROCEDURE", "TRIGGER",
        "SEQUENCE", "TYPE"
    ]

    // MARK: - Public Analyzer Entrypoint

    /// Analyzes the given SQL text and returns a safety classification.
    public static func analyze(_ sql: String) -> SQLSafetyCheckResult {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return SQLSafetyCheckResult(
                isDangerous: false,
                statementType: "EMPTY",
                isUnbounded: false,
                targetObject: nil,
                description: "Empty statement"
            )
        }

        // 1. Check for multi-statement batch scripts
        let statements = SQLScriptSplitter.split(trimmed)
        if statements.count > 1 {
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: "BATCH",
                isUnbounded: false,
                targetObject: nil,
                description: "Batch execution of \(statements.count) semicolon-separated statements."
            )
        }

        let statementToAnalyze = statements.first ?? trimmed
        let tokens = tokenize(statementToAnalyze)
        guard let firstToken = tokens.first else {
            return SQLSafetyCheckResult(
                isDangerous: false,
                statementType: "EMPTY",
                isUnbounded: false,
                targetObject: nil,
                description: "Empty statement"
            )
        }

        let firstKeyword: String
        switch firstToken.kind {
        case .keyword(let kw):
            firstKeyword = kw
        case .identifier(let id):
            firstKeyword = id.uppercased()
        default:
            firstKeyword = firstToken.text.uppercased()
        }

        switch firstKeyword {
        case "SELECT":
            // Check for SELECT ... INTO (which creates a new table)
            if hasTopLevelKeyword("INTO", in: tokens) {
                let target = extractTargetAfterKeyword("INTO", in: tokens)
                return SQLSafetyCheckResult(
                    isDangerous: true,
                    statementType: "SELECT INTO",
                    isUnbounded: false,
                    targetObject: target,
                    description: "Creation of new table via SELECT INTO"
                )
            }
            return SQLSafetyCheckResult(
                isDangerous: false,
                statementType: "SELECT",
                isUnbounded: false,
                targetObject: nil,
                description: "Read-only SELECT query"
            )

        case "EXPLAIN":
            return SQLSafetyCheckResult(
                isDangerous: false,
                statementType: "EXPLAIN",
                isUnbounded: false,
                targetObject: nil,
                description: "Read-only query execution plan"
            )

        case "SHOW":
            return SQLSafetyCheckResult(
                isDangerous: false,
                statementType: "SHOW",
                isUnbounded: false,
                targetObject: nil,
                description: "Read-only configuration inspection"
            )

        case "WITH":
            // Common Table Expression (CTE)
            // If the query contains any data mutating keyword outside string literals, flag as dangerous
            let mutatingKeywords: [String] = ["DELETE", "UPDATE", "INSERT", "DROP", "TRUNCATE", "ALTER", "CREATE", "MERGE"]
            for token in tokens {
                if case .keyword(let kw) = token.kind, mutatingKeywords.contains(kw) {
                    let target = extractTargetAfterKeyword("FROM", in: tokens)
                        ?? extractTargetAfterKeyword("INTO", in: tokens)
                        ?? extractTargetAfterKeyword(kw, in: tokens)
                    let hasWhere = hasTopLevelKeyword("WHERE", in: tokens)
                    let isUnbounded = (kw == "DELETE" || kw == "UPDATE") && !hasWhere
                    return SQLSafetyCheckResult(
                        isDangerous: true,
                        statementType: "WITH \(kw)",
                        isUnbounded: isUnbounded,
                        targetObject: target,
                        description: isUnbounded
                            ? "This query will modify/delete ALL rows in \(target ?? "the table")"
                            : "CTE containing \(kw) mutation"
                    )
                }
            }
            return SQLSafetyCheckResult(
                isDangerous: false,
                statementType: "SELECT",
                isUnbounded: false,
                targetObject: nil,
                description: "Read-only CTE query"
            )

        case "DELETE":
            let target = extractTargetAfterKeyword("FROM", in: tokens)
                ?? extractTargetAfterKeyword("DELETE", in: tokens)
            let hasWhere = hasTopLevelKeyword("WHERE", in: tokens)
            let isUnbounded = !hasWhere
            let desc = isUnbounded
                ? "This query will modify/delete ALL rows in \(target != nil ? "\"\(target!)\"" : "the table")"
                : "DELETE statement on \(target != nil ? "\"\(target!)\"" : "table")"
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: "DELETE",
                isUnbounded: isUnbounded,
                targetObject: target,
                description: desc
            )

        case "UPDATE":
            let target = extractTargetAfterKeyword("UPDATE", in: tokens)
            let hasWhere = hasTopLevelKeyword("WHERE", in: tokens)
            let isUnbounded = !hasWhere
            let desc = isUnbounded
                ? "This query will modify/delete ALL rows in \(target != nil ? "\"\(target!)\"" : "the table")"
                : "UPDATE statement on \(target != nil ? "\"\(target!)\"" : "table")"
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: "UPDATE",
                isUnbounded: isUnbounded,
                targetObject: target,
                description: desc
            )

        case "DROP":
            let subType = extractSecondKeyword(in: tokens) ?? "OBJECT"
            let target = extractTargetAfterDrop(in: tokens)
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: "DROP",
                isUnbounded: false,
                targetObject: target,
                description: "Destructive DROP of \(subType) \(target != nil ? "\"\(target!)\"" : "")"
            )

        case "TRUNCATE":
            let target = extractTargetAfterKeyword("TABLE", in: tokens)
                ?? extractTargetAfterKeyword("TRUNCATE", in: tokens)
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: "TRUNCATE",
                isUnbounded: false,
                targetObject: target,
                description: "TRUNCATE permanently empties table \(target != nil ? "\"\(target!)\"" : "")"
            )

        case "ALTER":
            let subType = extractSecondKeyword(in: tokens) ?? "TABLE"
            let target = extractTargetAfterKeyword(subType, in: tokens)
                ?? extractTargetAfterKeyword("ALTER", in: tokens)
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: "ALTER",
                isUnbounded: false,
                targetObject: target,
                description: "Schema modification on \(target != nil ? "\"\(target!)\"" : "object")"
            )

        case "CREATE":
            let subType = extractSecondKeyword(in: tokens) ?? "OBJECT"
            let target = extractTargetAfterKeyword(subType, in: tokens)
                ?? extractTargetAfterKeyword("CREATE", in: tokens)
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: "CREATE",
                isUnbounded: false,
                targetObject: target,
                description: "Structural DDL creating \(subType) \(target != nil ? "\"\(target!)\"" : "")"
            )

        case "INSERT":
            let target = extractTargetAfterKeyword("INTO", in: tokens)
                ?? extractTargetAfterKeyword("INSERT", in: tokens)
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: "INSERT",
                isUnbounded: false,
                targetObject: target,
                description: "INSERT mutation on \(target != nil ? "\"\(target!)\"" : "table")"
            )

        case "MERGE":
            let target = extractTargetAfterKeyword("INTO", in: tokens)
                ?? extractTargetAfterKeyword("MERGE", in: tokens)
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: "MERGE",
                isUnbounded: false,
                targetObject: target,
                description: "MERGE mutation on \(target != nil ? "\"\(target!)\"" : "table")"
            )

        case "GRANT", "REVOKE":
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: firstKeyword,
                isUnbounded: false,
                targetObject: nil,
                description: "Privilege alteration (\(firstKeyword))"
            )

        case "DO":
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: "DO",
                isUnbounded: false,
                targetObject: nil,
                description: "Procedural DO block execution"
            )

        case "VACUUM":
            if hasTopLevelKeyword("FULL", in: tokens) {
                return SQLSafetyCheckResult(
                    isDangerous: true,
                    statementType: "VACUUM FULL",
                    isUnbounded: false,
                    targetObject: nil,
                    description: "Administrative full vacuum locks tables and rewrites storage"
                )
            }
            return SQLSafetyCheckResult(
                isDangerous: false,
                statementType: "VACUUM",
                isUnbounded: false,
                targetObject: nil,
                description: "Maintenance vacuum"
            )

        case "BEGIN", "COMMIT", "ROLLBACK", "SET", "RESET":
            return SQLSafetyCheckResult(
                isDangerous: false,
                statementType: firstKeyword,
                isUnbounded: false,
                targetObject: nil,
                description: "Session/transaction command (\(firstKeyword))"
            )

        default:
            return SQLSafetyCheckResult(
                isDangerous: true,
                statementType: firstKeyword,
                isUnbounded: false,
                targetObject: nil,
                description: "Potentially mutating statement (\(firstKeyword))"
            )
        }
    }

    // MARK: - Tokenizer

    private static func tokenize(_ sql: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(sql)
        var i = 0
        let len = chars.count
        var parenDepth = 0

        while i < len {
            let c = chars[i]

            // Skip whitespace
            if c.isWhitespace {
                i += 1
                continue
            }

            // Single line comment: -- ... or # ... (MySQL)
            if (c == "-" && i + 1 < len && chars[i + 1] == "-") || c == "#" {
                i += (c == "#" ? 1 : 2)
                while i < len && chars[i] != "\n" && chars[i] != "\r" {
                    i += 1
                }
                continue
            }

            // Block comment: /* ... */
            if c == "/" && i + 1 < len && chars[i + 1] == "*" {
                i += 2
                while i < len {
                    if chars[i] == "*" && i + 1 < len && chars[i + 1] == "/" {
                        i += 2
                        break
                    }
                    i += 1
                }
                continue
            }

            // String literal: '...' (with '' escape)
            if c == "'" {
                i += 1
                while i < len {
                    let sc = chars[i]
                    if sc == "'" {
                        if i + 1 < len && chars[i + 1] == "'" {
                            i += 2
                            continue
                        } else {
                            i += 1
                            break
                        }
                    }
                    i += 1
                }
                tokens.append(Token(kind: .stringLiteral, text: "''", parenDepth: parenDepth))
                continue
            }

            // Dollar-quoted string: $$ ... $$ or $tag$ ... $tag$
            if c == "$" {
                if let (tag, tagEndIndex) = matchDollarTag(chars: chars, startIndex: i) {
                    let tagChars = Array(tag)
                    i = tagEndIndex
                    while i < len {
                        if chars[i] == "$" && matchTagAt(chars: chars, index: i, tagChars: tagChars) {
                            i += tag.count
                            break
                        }
                        i += 1
                    }
                    tokens.append(Token(kind: .stringLiteral, text: "$$", parenDepth: parenDepth))
                    continue
                }
            }

            // Quoted identifier: "..." (PostgreSQL) or `...` (MySQL/MariaDB)
            if c == "\"" || c == "`" {
                let quoteChar = c
                i += 1
                var id = ""
                while i < len {
                    let qc = chars[i]
                    if qc == quoteChar {
                        if i + 1 < len && chars[i + 1] == quoteChar {
                            id.append(quoteChar)
                            i += 2
                            continue
                        } else {
                            i += 1
                            break
                        }
                    } else {
                        id.append(qc)
                        i += 1
                    }
                }
                tokens.append(Token(kind: .identifier(id), text: id, parenDepth: parenDepth))
                continue
            }

            // Parentheses
            if c == "(" {
                tokens.append(Token(kind: .symbol(c), text: "(", parenDepth: parenDepth))
                parenDepth += 1
                i += 1
                continue
            }
            if c == ")" {
                parenDepth = max(0, parenDepth - 1)
                tokens.append(Token(kind: .symbol(c), text: ")", parenDepth: parenDepth))
                i += 1
                continue
            }

            // Other symbols (e.g. ;, ,, .)
            if c == ";" || c == "," || c == "." {
                tokens.append(Token(kind: .symbol(c), text: String(c), parenDepth: parenDepth))
                i += 1
                continue
            }

            // Word: letters, numbers, underscores
            if c.isLetter || c.isNumber || c == "_" {
                var word = ""
                while i < len && (chars[i].isLetter || chars[i].isNumber || chars[i] == "_") {
                    word.append(chars[i])
                    i += 1
                }

                let upper = word.uppercased()
                if knownKeywords.contains(upper) {
                    tokens.append(Token(kind: .keyword(upper), text: upper, parenDepth: parenDepth))
                } else {
                    tokens.append(Token(kind: .identifier(word), text: word, parenDepth: parenDepth))
                }
                continue
            }

            // Any other punctuation / operator
            tokens.append(Token(kind: .symbol(c), text: String(c), parenDepth: parenDepth))
            i += 1
        }

        return tokens
    }

    // MARK: - Dollar Quote Helpers

    private static func matchDollarTag(chars: [Character], startIndex: Int) -> (String, Int)? {
        guard chars[startIndex] == "$" else { return nil }
        var tag = "$"
        var idx = startIndex + 1

        while idx < chars.count {
            let c = chars[idx]
            tag.append(c)
            idx += 1
            if c == "$" {
                return (tag, idx)
            }
            if !(c.isLetter || c.isNumber || c == "_") {
                return nil
            }
        }
        return nil
    }

    private static func matchTagAt(chars: [Character], index: Int, tagChars: [Character]) -> Bool {
        guard index + tagChars.count <= chars.count else { return false }
        for j in 0..<tagChars.count {
            if chars[index + j] != tagChars[j] {
                return false
            }
        }
        return true
    }

    // MARK: - Query Analysis Helpers

    private static func hasTopLevelKeyword(_ keyword: String, in tokens: [Token]) -> Bool {
        let target = keyword.uppercased()
        return tokens.contains { token in
            token.parenDepth == 0 && token.text.uppercased() == target
        }
    }

    private static func extractSecondKeyword(in tokens: [Token]) -> String? {
        var foundFirst = false
        for token in tokens {
            if !foundFirst {
                foundFirst = true
                continue
            }
            if case .keyword(let kw) = token.kind {
                if kw != "IF" && kw != "EXISTS" && kw != "OR" && kw != "REPLACE" && kw != "UNIQUE" {
                    return kw
                }
            }
        }
        return nil
    }

    private static func extractTargetAfterKeyword(_ targetKeyword: String, in tokens: [Token]) -> String? {
        let upper = targetKeyword.uppercased()
        var foundIndex: Int?

        for (idx, token) in tokens.enumerated() {
            if token.text.uppercased() == upper {
                foundIndex = idx
                break
            }
        }

        guard let foundIdx = foundIndex else { return nil }

        // Walk forward skipping ONLY, IF, EXISTS, TABLE, etc.
        var cur = foundIdx + 1
        while cur < tokens.count {
            let t = tokens[cur]
            let textUpper = t.text.uppercased()
            if textUpper == "ONLY" || textUpper == "TABLE" || textUpper == "IF" || textUpper == "EXISTS" {
                cur += 1
                continue
            }
            break
        }

        return extractObjectPath(from: cur, in: tokens)
    }

    private static func extractTargetAfterDrop(in tokens: [Token]) -> String? {
        var cur = 1 // After DROP
        while cur < tokens.count {
            let textUpper = tokens[cur].text.uppercased()
            if ["TABLE", "DATABASE", "SCHEMA", "VIEW", "INDEX", "SEQUENCE", "TYPE", "FUNCTION", "PROCEDURE", "TRIGGER", "IF", "EXISTS"].contains(textUpper) {
                cur += 1
                continue
            }
            break
        }
        return extractObjectPath(from: cur, in: tokens)
    }

    private static func extractObjectPath(from index: Int, in tokens: [Token]) -> String? {
        guard index < tokens.count else { return nil }
        var parts: [String] = []
        var cur = index

        while cur < tokens.count {
            let token = tokens[cur]
            switch token.kind {
            case .identifier(let name):
                parts.append(name)
                cur += 1
            case .keyword(let kw):
                // In some cases table names might clash with keywords, or end of path
                if parts.isEmpty {
                    parts.append(kw.lowercased())
                    cur += 1
                } else {
                    return parts.joined(separator: ".")
                }
            case .symbol(let s) where s == ".":
                cur += 1
                continue
            default:
                return parts.isEmpty ? nil : parts.joined(separator: ".")
            }

            // If the next token isn't a dot, path is complete
            if cur < tokens.count {
                if case .symbol(let s) = tokens[cur].kind, s == "." {
                    cur += 1
                    continue
                } else {
                    break
                }
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: ".")
    }
}
