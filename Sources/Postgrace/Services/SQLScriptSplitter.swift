import Foundation

public struct SQLStatementSpan: Equatable, Identifiable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let statement: String
    public let range: NSRange

    public init(index: Int, statement: String, range: NSRange) {
        self.index = index
        self.statement = statement
        self.range = range
    }
}

/// Robust SQL script parser and statement splitter for PostgreSQL and MySQL.
/// Correctly handles single quotes, dollar quotes ($$...$$ or $tag$...$tag$),
/// line comments (--), and block comments (/* ... */) without breaking statements.
public enum SQLScriptSplitter {

    /// Splits a full SQL script into individual executable statements.
    public static func split(_ sql: String) -> [String] {
        return splitWithSpans(sql).map(\.statement)
    }

    /// Splits a full SQL script into individual statements along with their character NSRanges in the original string.
    public static func splitWithSpans(_ sql: String) -> [SQLStatementSpan] {
        var spans: [SQLStatementSpan] = []
        let chars = Array(sql)
        var i = 0
        let len = chars.count
        var statementStartCharIndex = 0

        func addSpan(startChar: Int, endCharExclusive: Int) {
            guard startChar < endCharExclusive else { return }
            var s = startChar
            while s < endCharExclusive && (chars[s].isWhitespace || chars[s].isNewline) {
                s += 1
            }
            var e = endCharExclusive - 1
            while e >= s && (chars[e].isWhitespace || chars[e].isNewline) {
                e -= 1
            }
            guard s <= e else { return }

            let startIdx = sql.index(sql.startIndex, offsetBy: s)
            let endIdx = sql.index(sql.startIndex, offsetBy: e + 1)
            let trimmedText = String(sql[startIdx..<endIdx])
            let nsRange = NSRange(startIdx..<endIdx, in: sql)

            spans.append(SQLStatementSpan(index: spans.count, statement: trimmedText, range: nsRange))
        }

        while i < len {
            let c = chars[i]

            // 1. Single-line comment: -- ... or # ... (MySQL)
            if (c == "-" && i + 1 < len && chars[i + 1] == "-") || c == "#" {
                i += (c == "#" ? 1 : 2)
                while i < len && chars[i] != "\n" && chars[i] != "\r" {
                    i += 1
                }
                continue
            }

            // 2. Block comment: /* ... */
            if c == "/" && i + 1 < len && chars[i + 1] == "*" {
                i += 2
                while i < len {
                    if chars[i] == "*" && i + 1 < len && chars[i + 1] == "/" {
                        i += 2
                        break
                    } else {
                        i += 1
                    }
                }
                continue
            }

            // 3. String literal: '...' (with '' escape)
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
                    } else {
                        i += 1
                    }
                }
                continue
            }

            // 4. Dollar-quoted string: $$ ... $$ or $tag$ ... $tag$
            if c == "$" {
                if let (tag, tagEndIndex) = matchDollarTag(chars: chars, startIndex: i) {
                    i = tagEndIndex
                    while i < len {
                        if chars[i] == "$" && matchTagAt(chars: chars, index: i, tag: tag) {
                            i += tag.count
                            break
                        } else {
                            i += 1
                        }
                    }
                    continue
                }
            }

            // 5. Quoted identifier: "..." (PostgreSQL) or `...` (MySQL/MariaDB)
            if c == "\"" || c == "`" {
                let quoteChar = c
                i += 1
                while i < len {
                    let qc = chars[i]
                    if qc == quoteChar {
                        if i + 1 < len && chars[i + 1] == quoteChar {
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
                continue
            }

            // 6. Statement Terminator: semicolon outside quotes/comments
            if c == ";" {
                addSpan(startChar: statementStartCharIndex, endCharExclusive: i)
                i += 1
                statementStartCharIndex = i
                continue
            }

            // Regular character
            i += 1
        }

        if statementStartCharIndex < len {
            addSpan(startChar: statementStartCharIndex, endCharExclusive: len)
        }

        return spans
    }

    /// Finds the statement span at or closest to the specified cursor offset (UTF-16 based NSRange location).
    public static func statement(at cursorOffset: Int, in sql: String) -> SQLStatementSpan? {
        let spans = splitWithSpans(sql)
        guard !spans.isEmpty else { return nil }

        // Exact match: cursor falls within statement span range (inclusive of borders)
        for span in spans {
            if cursorOffset >= span.range.location && cursorOffset <= (span.range.location + span.range.length) {
                return span
            }
        }

        // Closest match: cursor is in whitespace before, between, or after statements
        var closest = spans[0]
        var minDistance = Int.max

        for span in spans {
            let distance: Int
            if cursorOffset < span.range.location {
                distance = span.range.location - cursorOffset
            } else {
                distance = cursorOffset - (span.range.location + span.range.length)
            }
            if distance < minDistance {
                minDistance = distance
                closest = span
            }
        }

        return closest
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
