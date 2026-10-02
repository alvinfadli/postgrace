import Foundation

/// Robust SQL script parser and statement splitter for PostgreSQL.
/// Correctly handles single quotes, dollar quotes ($$...$$ or $tag$...$tag$),
/// line comments (--), and block comments (/* ... */) without breaking statements.
public enum SQLScriptSplitter {

    /// Splits a full SQL script into individual executable statements.
    public static func split(_ sql: String) -> [String] {
        var statements: [String] = []
        var currentStatement = ""
        let chars = Array(sql)
        var i = 0
        let len = chars.count

        while i < len {
            let c = chars[i]

            // 1. Single-line comment: -- ...
            if c == "-" && i + 1 < len && chars[i + 1] == "-" {
                var comment = "--"
                i += 2
                while i < len && chars[i] != "\n" && chars[i] != "\r" {
                    comment.append(chars[i])
                    i += 1
                }
                currentStatement.append(comment)
                continue
            }

            // 2. Block comment: /* ... */
            if c == "/" && i + 1 < len && chars[i + 1] == "*" {
                var comment = "/*"
                i += 2
                while i < len {
                    if chars[i] == "*" && i + 1 < len && chars[i + 1] == "/" {
                        comment.append("*/")
                        i += 2
                        break
                    } else {
                        comment.append(chars[i])
                        i += 1
                    }
                }
                currentStatement.append(comment)
                continue
            }

            // 3. String literal: '...' (with '' escape)
            if c == "'" {
                var literal = "'"
                i += 1
                while i < len {
                    let sc = chars[i]
                    literal.append(sc)
                    if sc == "'" {
                        // Check for escaped quote ''
                        if i + 1 < len && chars[i + 1] == "'" {
                            literal.append("'")
                            i += 2
                            continue
                        } else {
                            i += 1
                            break
                        }
                    } else {
                        i += 1
                    }
                }
                currentStatement.append(literal)
                continue
            }

            // 4. Dollar-quoted string: $$ ... $$ or $tag$ ... $tag$
            if c == "$" {
                if let (tag, tagEndIndex) = matchDollarTag(chars: chars, startIndex: i) {
                    var dollarBlock = tag
                    i = tagEndIndex
                    while i < len {
                        if chars[i] == "$" && matchTagAt(chars: chars, index: i, tag: tag) {
                            dollarBlock.append(tag)
                            i += tag.count
                            break
                        } else {
                            dollarBlock.append(chars[i])
                            i += 1
                        }
                    }
                    currentStatement.append(dollarBlock)
                    continue
                }
            }

            // 5. Statement Terminator: semicolon outside quotes/comments
            if c == ";" {
                let trimmed = currentStatement.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    statements.append(trimmed)
                }
                currentStatement = ""
                i += 1
                continue
            }

            // Regular character
            currentStatement.append(c)
            i += 1
        }

        let remaining = currentStatement.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            statements.append(remaining)
        }

        return statements
    }

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
            // Valid PostgreSQL dollar tag characters: letters, digits, underscores
            if !(c.isLetter || c.isNumber || c == "_") {
                return nil
            }
        }
        return nil
    }

    private static func matchTagAt(chars: [Character], index: Int, tag: String) -> Bool {
        let tagChars = Array(tag)
        guard index + tagChars.count <= chars.count else { return false }
        for j in 0..<tagChars.count {
            if chars[index + j] != tagChars[j] {
                return false
            }
        }
        return true
    }
}
