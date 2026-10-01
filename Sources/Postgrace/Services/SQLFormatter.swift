import Foundation

/// Pure Swift SQL Formatter for PostgreSQL statements.
/// Uppercases keywords and organizes major clauses with clean indentation while respecting string literals.
public enum SQLFormatter {
    private static let majorKeywords: [String] = [
        "SELECT", "FROM", "WHERE", "GROUP BY", "ORDER BY", "HAVING",
        "LIMIT", "OFFSET", "LEFT JOIN", "RIGHT JOIN", "INNER JOIN",
        "FULL JOIN", "CROSS JOIN", "JOIN", "ON", "VALUES", "SET",
        "INSERT INTO", "UPDATE", "DELETE FROM", "UNION ALL", "UNION"
    ]

    private static let inlineKeywords: [String] = [
        "AND", "OR", "NOT", "IN", "AS", "ASC", "DESC", "DISTINCT",
        "IS NULL", "IS NOT NULL", "BETWEEN", "LIKE", "ILIKE",
        "CASE", "WHEN", "THEN", "ELSE", "END", "EXISTS", "NOT EXISTS",
        "CREATE TABLE", "ALTER TABLE", "DROP TABLE", "PRIMARY KEY",
        "REFERENCES", "DEFAULT", "CASCADE", "RETURNING"
    ]

    /// Format a SQL query with proper capitalization and newline breaks for clauses.
    public static func format(_ sql: String) -> String {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Step 1: Tokenize respecting single quotes / string literals
        var tokens: [String] = []
        var currentToken = ""
        var inQuotes = false
        var quoteChar: Character = "'"

        let chars = Array(trimmed)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            if inQuotes {
                currentToken.append(c)
                if c == quoteChar {
                    // Check for escaped quote ''
                    if i + 1 < chars.count && chars[i + 1] == quoteChar {
                        currentToken.append(chars[i + 1])
                        i += 1
                    } else {
                        inQuotes = false
                        tokens.append(currentToken)
                        currentToken = ""
                    }
                }
            } else {
                // Line comment --
                if c == "-" && i + 1 < chars.count && chars[i + 1] == "-" {
                    if !currentToken.isEmpty {
                        tokens.append(currentToken)
                        currentToken = ""
                    }
                    var comment = "--"
                    i += 2
                    while i < chars.count && chars[i] != "\n" {
                        comment.append(chars[i])
                        i += 1
                    }
                    tokens.append(comment)
                    continue
                }

                // Block comment /* ... */
                if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                    if !currentToken.isEmpty {
                        tokens.append(currentToken)
                        currentToken = ""
                    }
                    var comment = "/*"
                    i += 2
                    while i < chars.count {
                        if chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "/" {
                            comment.append("*/")
                            i += 2
                            break
                        } else {
                            comment.append(chars[i])
                            i += 1
                        }
                    }
                    tokens.append(comment)
                    continue
                }

                // Dollar-quoted string $$ ... $$ or $tag$ ... $tag$
                if c == "$" {
                    var tagEnd = i + 1
                    while tagEnd < chars.count && chars[tagEnd] != "$" && (chars[tagEnd].isLetter || chars[tagEnd].isNumber || chars[tagEnd] == "_") {
                        tagEnd += 1
                    }
                    if tagEnd < chars.count && chars[tagEnd] == "$" {
                        let tag = String(chars[i...tagEnd])
                        if !currentToken.isEmpty {
                            tokens.append(currentToken)
                            currentToken = ""
                        }
                        var block = tag
                        i = tagEnd + 1
                        let tagChars = Array(tag)
                        while i < chars.count {
                            if chars[i] == "$" && i + tagChars.count <= chars.count {
                                let potentialClose = String(chars[i..<(i + tagChars.count)])
                                if potentialClose == tag {
                                    block.append(tag)
                                    i += tagChars.count
                                    break
                                }
                            }
                            block.append(chars[i])
                            i += 1
                        }
                        tokens.append(block)
                        continue
                    }
                }

                if c == "'" || c == "\"" {
                    if !currentToken.isEmpty {
                        tokens.append(currentToken)
                        currentToken = ""
                    }
                    inQuotes = true
                    quoteChar = c
                    currentToken.append(c)
                } else if c.isWhitespace {
                    if !currentToken.isEmpty {
                        tokens.append(currentToken)
                        currentToken = ""
                    }
                } else if c == "," || c == ";" {
                    if !currentToken.isEmpty {
                        tokens.append(currentToken)
                        currentToken = ""
                    }
                    tokens.append(String(c))
                } else {
                    currentToken.append(c)
                }
            }
            i += 1
        }

        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }

        // Step 2: Uppercase recognizable keywords (outside strings, comments, and dollar-quotes)
        let uppercaseKeywords = Set((majorKeywords + inlineKeywords).flatMap { $0.components(separatedBy: " ") })
        var normalizedTokens: [String] = []

        for token in tokens {
            if token.hasPrefix("'") || token.hasPrefix("\"") || token.hasPrefix("--") || token.hasPrefix("/*") || token.hasPrefix("$") {
                normalizedTokens.append(token)
            } else if uppercaseKeywords.contains(token.uppercased()) {
                normalizedTokens.append(token.uppercased())
            } else {
                normalizedTokens.append(token)
            }
        }

        // Step 3: Reconstruct with line breaks for major clauses
        var result = ""
        var index = 0

        while index < normalizedTokens.count {
            let token = normalizedTokens[index]

            // Check two-word major keywords like "GROUP BY", "ORDER BY", "LEFT JOIN", "INSERT INTO"
            if index + 1 < normalizedTokens.count {
                let twoWords = "\(token) \(normalizedTokens[index + 1])".uppercased()
                if majorKeywords.contains(twoWords) {
                    if !result.isEmpty && !result.hasSuffix("\n") {
                        result.append("\n")
                    }
                    result.append(twoWords + " ")
                    index += 2
                    continue
                }
            }

            if majorKeywords.contains(token.uppercased()) {
                if !result.isEmpty && !result.hasSuffix("\n") {
                    result.append("\n")
                }
                result.append(token.uppercased() + " ")
            } else if token == "," {
                if result.hasSuffix(" ") {
                    result.removeLast()
                }
                result.append(", ")
            } else if token == ";" {
                if result.hasSuffix(" ") {
                    result.removeLast()
                }
                result.append(";\n")
            } else {
                result.append(token + " ")
            }

            index += 1
        }

        // Clean up trailing spaces on lines
        let formattedLines = result.components(separatedBy: "\n").map { line in
            line.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        return formattedLines.joined(separator: "\n")
    }
}
