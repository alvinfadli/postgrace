import Foundation
import AppKit
import SwiftUI

/// Token categories for SQL syntax highlighting (FR-2.1 & FR-2.2).
public enum SQLTokenKind: String, Sendable, Equatable, CaseIterable {
    case keyword
    case command
    case dataType
    case function
    case stringLiteral
    case numericLiteral
    case identifier
    case comment
    case operatorSymbol

    public var nsColor: NSColor {
        switch self {
        case .keyword: return PostgraceTheme.sqlKeywordNSColor
        case .command: return PostgraceTheme.sqlCommandNSColor
        case .dataType: return PostgraceTheme.sqlDataTypeNSColor
        case .function: return PostgraceTheme.sqlFunctionNSColor
        case .stringLiteral: return PostgraceTheme.sqlStringNSColor
        case .numericLiteral: return PostgraceTheme.sqlNumberNSColor
        case .identifier: return PostgraceTheme.sqlIdentifierNSColor
        case .comment: return PostgraceTheme.sqlCommentNSColor
        case .operatorSymbol: return PostgraceTheme.sqlOperatorNSColor
        }
    }

    public var swiftUIColor: Color {
        switch self {
        case .keyword: return PostgraceTheme.sqlKeyword
        case .command: return PostgraceTheme.sqlCommand
        case .dataType: return PostgraceTheme.sqlDataType
        case .function: return PostgraceTheme.sqlFunction
        case .stringLiteral: return PostgraceTheme.sqlString
        case .numericLiteral: return PostgraceTheme.sqlNumber
        case .identifier: return PostgraceTheme.sqlIdentifier
        case .comment: return PostgraceTheme.sqlComment
        case .operatorSymbol: return PostgraceTheme.sqlOperator
        }
    }
}

/// A single lexical token with its semantic classification and UTF-16 `NSRange`.
public struct SQLSyntaxToken: Equatable, Sendable {
    public let kind: SQLTokenKind
    public let range: NSRange

    public init(kind: SQLTokenKind, range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

/// High-performance, UTF-16 exact SQL lexical tokenizer and syntax highlighter for PostgreSQL and MySQL/MariaDB.
public enum SQLSyntaxHighlighter {

    // MARK: - Grammar Dictionaries

    public static let commands: Set<String> = [
        "INSERT", "UPDATE", "SET", "DELETE", "TRUNCATE",
        "CREATE", "ALTER", "DROP", "REPLACE", "MERGE", "UPSERT",
        "TABLE", "TEMP", "TEMPORARY", "VIEW", "MATERIALIZED",
        "INDEX", "CONCURRENTLY", "SCHEMA", "DATABASE", "EXTENSION",
        "TRIGGER", "FUNCTION", "PROCEDURE", "SEQUENCE", "DOMAIN",
        "ROLE", "USER", "GRANT", "REVOKE",
        "BEGIN", "START", "TRANSACTION", "COMMIT", "ROLLBACK", "SAVEPOINT", "RELEASE",
        "VACUUM", "REINDEX", "CLUSTER", "COMMENT", "RENAME", "ADD", "COLUMN", "VALUES"
    ]

    public static let keywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT",
        "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "OFFSET",
        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "FULL", "NATURAL",
        "ON", "USING", "AS", "INTO", "TO",
        "UNION", "ALL", "INTERSECT", "EXCEPT", "DISTINCT",
        "WITH", "RECURSIVE", "CASE", "WHEN", "THEN", "ELSE", "END",
        "EXISTS", "IN", "BETWEEN", "LIKE", "ILIKE", "SIMILAR", "IS",
        "ASC", "DESC", "NULLS", "FIRST", "LAST",
        "RETURNING", "CASCADE", "RESTRICT",
        "PRIMARY", "KEY", "FOREIGN", "REFERENCES", "DEFAULT", "CONSTRAINT", "UNIQUE", "CHECK",
        "EXPLAIN", "ANALYZE", "VERBOSE", "COSTS", "BUFFERS", "FORMAT",
        "OVER", "PARTITION", "FILTER", "WITHIN", "WINDOW",
        "ROWS", "RANGE", "UNBOUNDED", "PRECEDING", "FOLLOWING", "CURRENT", "ROW",
        "FETCH", "NEXT", "ONLY", "FOR", "SHARE", "NOWAIT", "SKIP", "LOCKED",
        "LATERAL", "CONFLICT", "DO", "NOTHING", "IF",
        "AUTHORIZATION", "OWNER", "ENCODING", "TEMPLATE", "CONNECTION"
    ]

    public static let dataTypes: Set<String> = [
        "INTEGER", "INT", "INT2", "INT4", "INT8", "SMALLINT", "BIGINT", "TINYINT", "MEDIUMINT",
        "SERIAL", "SMALLSERIAL", "BIGSERIAL",
        "DECIMAL", "NUMERIC", "REAL", "FLOAT", "FLOAT4", "FLOAT8", "DOUBLE", "PRECISION", "MONEY",
        "VARCHAR", "CHAR", "CHARACTER", "VARYING", "TEXT", "TINYTEXT", "MEDIUMTEXT", "LONGTEXT", "CITEXT",
        "BOOLEAN", "BOOL",
        "DATE", "TIME", "TIMETZ", "TIMESTAMP", "TIMESTAMPTZ", "DATETIME", "YEAR", "INTERVAL",
        "JSON", "JSONB", "UUID", "BYTEA", "BLOB", "TINYBLOB", "MEDIUMBLOB", "LONGBLOB", "BINARY", "VARBINARY",
        "ARRAY", "INET", "CIDR", "MACADDR", "XML",
        "POINT", "LINE", "LSEG", "BOX", "PATH", "POLYGON", "CIRCLE",
        "TSVECTOR", "TSQUERY", "INT4RANGE", "INT8RANGE", "NUMRANGE", "TSRANGE", "TSTZRANGE", "DATERANGE",
        "REGCLASS", "OID", "ENUM"
    ]

    public static let functions: Set<String> = [
        "COUNT", "SUM", "AVG", "MIN", "MAX",
        "COALESCE", "NULLIF", "GREATEST", "LEAST",
        "ROUND", "FLOOR", "CEIL", "CEILING", "ABS", "MOD", "POWER", "SQRT", "EXP", "LN", "LOG", "RANDOM", "SIGN", "TRUNC",
        "CONCAT", "CONCAT_WS", "SUBSTRING", "SUBSTR", "LOWER", "UPPER", "INITCAP",
        "LENGTH", "CHAR_LENGTH", "OCTET_LENGTH", "BIT_LENGTH",
        "TRIM", "BTRIM", "LTRIM", "RTRIM", "LPAD", "RPAD", "REPEAT", "REVERSE", "SPLIT_PART", "STRPOS", "POSITION",
        "ASCII", "CHR", "MD5", "ENCODE", "DECODE",
        "REGEXP_REPLACE", "REGEXP_MATCHES", "REGEXP_SPLIT_TO_TABLE", "REGEXP_SPLIT_TO_ARRAY",
        "NOW", "CURRENT_TIMESTAMP", "CURRENT_DATE", "CURRENT_TIME", "LOCALTIME", "LOCALTIMESTAMP",
        "CLOCK_TIMESTAMP", "STATEMENT_TIMESTAMP", "TRANSACTION_TIMESTAMP",
        "DATE_TRUNC", "DATE_PART", "EXTRACT", "AGE",
        "MAKE_DATE", "MAKE_TIME", "MAKE_TIMESTAMP", "MAKE_TIMESTAMPTZ", "MAKE_INTERVAL",
        "TO_CHAR", "TO_DATE", "TO_TIMESTAMP", "TO_NUMBER", "CAST",
        "ARRAY_AGG", "STRING_AGG", "BOOL_AND", "BOOL_OR", "BIT_AND", "BIT_OR",
        "JSON_AGG", "JSONB_AGG", "JSON_OBJECT_AGG", "JSONB_OBJECT_AGG",
        "JSON_BUILD_OBJECT", "JSONB_BUILD_OBJECT", "JSON_BUILD_ARRAY", "JSONB_BUILD_ARRAY",
        "ROW_TO_JSON", "TO_JSON", "TO_JSONB", "JSONB_SET", "JSONB_PRETTY", "JSON_EXTRACT_PATH", "JSONB_EXTRACT_PATH",
        "GEN_RANDOM_UUID", "UUID_GENERATE_V4",
        "ROW_NUMBER", "RANK", "DENSE_RANK", "PERCENT_RANK", "CUME_DIST", "NTILE",
        "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE", "NTH_VALUE",
        "PG_SIZE_PRETTY", "PG_TOTAL_RELATION_SIZE", "PG_RELATION_SIZE", "PG_TABLE_SIZE", "PG_INDEXES_SIZE", "PG_DATABASE_SIZE",
        "PG_BACKEND_PID", "PG_CANCEL_BACKEND", "PG_TERMINATE_BACKEND", "PG_SLEEP",
        "CURRENT_DATABASE", "CURRENT_SCHEMA", "CURRENT_USER", "SESSION_USER", "VERSION",
        "IFNULL", "NVL", "DATEDIFF", "DATE_ADD", "DATE_SUB", "DATE_FORMAT", "STR_TO_DATE",
        "UNIX_TIMESTAMP", "FROM_UNIXTIME", "GROUP_CONCAT", "FIND_IN_SET", "JSON_EXTRACT", "JSON_OBJECT", "JSON_ARRAY"
    ]

    public static let niladicFunctions: Set<String> = [
        "CURRENT_TIMESTAMP", "CURRENT_DATE", "CURRENT_TIME",
        "LOCALTIME", "LOCALTIMESTAMP", "CURRENT_USER", "SESSION_USER"
    ]

    public static let literalKeywords: Set<String> = [
        "TRUE", "FALSE", "NULL"
    ]

    private static let tableDeclaringKeywords: Set<String> = [
        "TABLE", "INTO", "INDEX", "VIEW", "ON", "UPDATE", "JOIN", "FROM"
    ]

    // MARK: - Lexical Scanner (UTF-16 Exact)

    /// Scans a SQL string and returns syntax tokens with exact UTF-16 `NSRange` bounds.
    /// Optionally restricts returned tokens to those intersecting `targetRange`.
    public static func tokenize(_ sql: String, in targetRange: NSRange? = nil) -> [SQLSyntaxToken] {
        let units = Array(sql.utf16)
        let len = units.count
        guard len > 0 else { return [] }

        var tokens: [SQLSyntaxToken] = []
        tokens.reserveCapacity(min(len / 4 + 8, 8192))

        let filterStart = targetRange?.location ?? 0
        let filterEnd = targetRange.map { $0.location + $0.length } ?? len

        @inline(__always)
        func emit(_ kind: SQLTokenKind, start: Int, end: Int) {
            guard end > start else { return }
            if end <= filterStart || start >= filterEnd {
                return
            }
            tokens.append(SQLSyntaxToken(kind: kind, range: NSRange(location: start, length: end - start)))
        }

        var i = 0
        var prevNonWhitespaceUnit: UInt16 = 0
        var prevUpperWord: String? = nil

        while i < len {
            if let tr = targetRange, i >= tr.location + tr.length {
                break
            }

            let u = units[i]

            // Skip whitespace (space, tab, LF, CR)
            if u == 32 || u == 9 || u == 10 || u == 13 {
                i += 1
                continue
            }

            // 1. Single-line comment: -- ... or # ...
            if (u == 45 && i + 1 < len && units[i + 1] == 45) || u == 35 { // '-'=45, '#'=35
                let start = i
                i += (u == 35 ? 1 : 2)
                while i < len && units[i] != 10 && units[i] != 13 {
                    i += 1
                }
                emit(.comment, start: start, end: i)
                continue
            }

            // 2. Multi-line block comment: /* ... */ (supports nesting)
            if u == 47 && i + 1 < len && units[i + 1] == 42 { // '/'=47, '*'=42
                let start = i
                i += 2
                var depth = 1
                while i < len && depth > 0 {
                    if units[i] == 47 && i + 1 < len && units[i + 1] == 42 {
                        depth += 1
                        i += 2
                    } else if units[i] == 42 && i + 1 < len && units[i + 1] == 47 {
                        depth -= 1
                        i += 2
                    } else {
                        i += 1
                    }
                }
                emit(.comment, start: start, end: i)
                continue
            }

            // 3. Single-quoted string literal: '...' (with '' or \' escape)
            if u == 39 { // '\''=39
                let start = i
                i += 1
                while i < len {
                    let cu = units[i]
                    if cu == 92 { // '\\'=92 escape
                        i = min(len, i + 2)
                        continue
                    }
                    if cu == 39 {
                        if i + 1 < len && units[i + 1] == 39 {
                            i += 2
                            continue
                        } else {
                            i += 1
                            break
                        }
                    }
                    i += 1
                }
                emit(.stringLiteral, start: start, end: i)
                prevNonWhitespaceUnit = 39
                prevUpperWord = nil
                continue
            }

            // 4. Dollar-quoted string (`$$...$$` or `$tag$...$tag$`) or positional parameter (`$1`)
            if u == 36 { // '$'=36
                if i + 1 < len && isASCIIDigit(units[i + 1]) {
                    let start = i
                    i += 1
                    while i < len && isASCIIDigit(units[i]) {
                        i += 1
                    }
                    emit(.numericLiteral, start: start, end: i)
                    prevNonWhitespaceUnit = 36
                    prevUpperWord = nil
                    continue
                }

                if let tagEnd = matchDollarTagEnd(units: units, startIndex: i) {
                    let start = i
                    let tagLen = tagEnd - start
                    i = tagEnd
                    while i < len {
                        if units[i] == 36 && matchDollarTagSlice(units: units, tagStart: start, tagLen: tagLen, at: i) {
                            i += tagLen
                            break
                        }
                        i += 1
                    }
                    emit(.stringLiteral, start: start, end: i)
                    prevNonWhitespaceUnit = 36
                    prevUpperWord = nil
                    continue
                }
            }

            // 5. Quoted identifier: "..." (PostgreSQL) or `...` (MySQL/MariaDB)
            if u == 34 || u == 96 { // '"'=34, '`'=96
                let quote = u
                let start = i
                i += 1
                while i < len {
                    let cu = units[i]
                    if cu == quote {
                        if i + 1 < len && units[i + 1] == quote {
                            i += 2
                            continue
                        } else {
                            i += 1
                            break
                        }
                    }
                    i += 1
                }
                emit(.identifier, start: start, end: i)
                prevNonWhitespaceUnit = quote
                prevUpperWord = nil
                continue
            }

            // 6. Numeric literal: integers, decimals, scientific notation (1e-6), hex (0xFF)
            if isASCIIDigit(u) {
                let start = i
                if u == 48 && i + 1 < len && (units[i + 1] == 120 || units[i + 1] == 88) { // 0x / 0X
                    i += 2
                    while i < len && isASCIIHexDigit(units[i]) {
                        i += 1
                    }
                } else {
                    while i < len && isASCIIDigit(units[i]) {
                        i += 1
                    }
                    if i < len && units[i] == 46 && (i + 1 < len && isASCIIDigit(units[i + 1])) { // '.'=46
                        i += 1
                        while i < len && isASCIIDigit(units[i]) {
                            i += 1
                        }
                    }
                    if i < len && (units[i] == 101 || units[i] == 69) { // 'e' or 'E'
                        var expIdx = i + 1
                        if expIdx < len && (units[expIdx] == 43 || units[expIdx] == 45) { // '+' or '-'
                            expIdx += 1
                        }
                        if expIdx < len && isASCIIDigit(units[expIdx]) {
                            i = expIdx + 1
                            while i < len && isASCIIDigit(units[i]) {
                                i += 1
                            }
                        }
                    }
                }
                emit(.numericLiteral, start: start, end: i)
                prevNonWhitespaceUnit = units[i - 1]
                prevUpperWord = nil
                continue
            }

            // 7. Word token (Keywords, DDL/DML Commands, Data Types, Functions, Literals, or Bare Identifiers)
            if isIdentifierStart(u) {
                let start = i
                i += 1
                while i < len && isIdentifierContinue(units[i]) {
                    i += 1
                }

                // Check if followed by '(' (ignoring horizontal whitespace)
                var lookahead = i
                while lookahead < len && (units[lookahead] == 32 || units[lookahead] == 9) {
                    lookahead += 1
                }
                let followedByParen = (lookahead < len && units[lookahead] == 40) // '('=40

                // Build uppercased ASCII word for dictionary lookup
                let upperWord = makeUpperASCIIString(units: units, start: start, end: i)
                let afterTableKeyword = prevUpperWord.map { tableDeclaringKeywords.contains($0) } ?? false

                let kind: SQLTokenKind
                if prevNonWhitespaceUnit == 46 { // Preceded by '.' (e.g., table.column or schema.func())
                    kind = (followedByParen && !afterTableKeyword) ? .function : .identifier
                } else if let upper = upperWord {
                    if literalKeywords.contains(upper) {
                        kind = .numericLiteral
                    } else if niladicFunctions.contains(upper) {
                        kind = .function
                    } else if followedByParen && (functions.contains(upper) || upper == "LEFT" || upper == "RIGHT" || upper == "REPLACE") {
                        kind = .function
                    } else if commands.contains(upper) {
                        kind = .command
                    } else if dataTypes.contains(upper) {
                        kind = .dataType
                    } else if keywords.contains(upper) {
                        kind = .keyword
                    } else if followedByParen && !afterTableKeyword {
                        kind = .function
                    } else {
                        kind = .identifier
                    }
                } else {
                    kind = (followedByParen && !afterTableKeyword) ? .function : .identifier
                }

                emit(kind, start: start, end: i)
                prevNonWhitespaceUnit = units[i - 1]
                if !(i < len && units[i] == 46) {
                    prevUpperWord = upperWord
                }
                continue
            }

            // 8. Operators & Type Casts (::, ->, ->>, #>, #>>, @>, <@, ||, !=, <>, <=, >=, =, <, >, +, -, *, /, %, ^, ~)
            if isOperatorChar(u) {
                let start = i
                i += 1
                while i < len && isOperatorChar(units[i]) {
                    // Don't consume comment starters (-- or /*) into an operator token
                    if units[i] == 45 && i + 1 < len && units[i + 1] == 45 { break }
                    if units[i] == 47 && i + 1 < len && units[i + 1] == 42 { break }
                    i += 1
                }
                emit(.operatorSymbol, start: start, end: i)
                prevNonWhitespaceUnit = units[i - 1]
                prevUpperWord = nil
                continue
            }

            // 9. Delimiters / Punctuation (., ,, ;, (, ), [, ])
            prevNonWhitespaceUnit = u
            if u != 46 { // Keep prevUpperWord across schema.table '.' separator
                prevUpperWord = nil
            }
            i += 1
        }

        return tokens
    }

    // MARK: - AppKit NSTextStorage Highlighting

    /// Applies syntax highlighting colors directly to an `NSTextStorage` without disrupting selection or Undo history.
    public static func highlight(
        _ textStorage: NSTextStorage,
        font: NSFont,
        in targetRange: NSRange? = nil
    ) {
        let fullLength = textStorage.length
        guard fullLength > 0 else { return }

        let effectiveRange: NSRange
        if let tr = targetRange {
            let clampedLoc = max(0, min(tr.location, fullLength))
            let clampedLen = max(0, min(tr.length, fullLength - clampedLoc))
            effectiveRange = NSRange(location: clampedLoc, length: clampedLen)
        } else {
            effectiveRange = NSRange(location: 0, length: fullLength)
        }
        guard effectiveRange.length > 0 else { return }

        let tokens = tokenize(textStorage.string, in: effectiveRange)

        textStorage.beginEditing()
        // Set base identifier color and font across the target range
        textStorage.addAttributes([
            .font: font,
            .foregroundColor: PostgraceTheme.sqlIdentifierNSColor
        ], range: effectiveRange)

        for token in tokens where token.kind != .identifier {
            let intersection = NSIntersectionRange(token.range, effectiveRange)
            if intersection.length > 0 {
                textStorage.addAttribute(.foregroundColor, value: token.kind.nsColor, range: intersection)
            }
        }
        textStorage.endEditing()
    }

    // MARK: - SwiftUI AttributedString Generation

    /// Produces a syntax-highlighted SwiftUI `AttributedString` for read-only SQL previews
    /// (Query History, Safe Mode Confirmation, DDL Previews, and Status Bars).
    public static func attributedString(
        for sql: String,
        fontSize: CGFloat = 11,
        weight: Font.Weight = .regular
    ) -> AttributedString {
        guard !sql.isEmpty else { return AttributedString("") }

        let nsAttr = NSMutableAttributedString(string: sql)
        let fullRange = NSRange(location: 0, length: nsAttr.length)
        let nsFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: nsFontWeight(from: weight))

        nsAttr.addAttributes([
            .font: nsFont,
            .foregroundColor: PostgraceTheme.sqlIdentifierNSColor
        ], range: fullRange)

        let tokens = tokenize(sql)
        for token in tokens where token.kind != .identifier {
            if token.range.location + token.range.length <= fullRange.length {
                nsAttr.addAttribute(.foregroundColor, value: token.kind.nsColor, range: token.range)
            }
        }

        return (try? AttributedString(nsAttr, including: \.appKit)) ?? AttributedString(sql)
    }

    // MARK: - Fast UTF-16 Helpers

    @inline(__always)
    private static func isASCIIDigit(_ u: UInt16) -> Bool {
        u >= 48 && u <= 57 // '0'...'9'
    }

    @inline(__always)
    private static func isASCIIHexDigit(_ u: UInt16) -> Bool {
        (u >= 48 && u <= 57) || (u >= 65 && u <= 70) || (u >= 97 && u <= 102)
    }

    @inline(__always)
    private static func isIdentifierStart(_ u: UInt16) -> Bool {
        (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 95 || u > 127 // A-Z, a-z, _, or non-ASCII
    }

    @inline(__always)
    private static func isIdentifierContinue(_ u: UInt16) -> Bool {
        isIdentifierStart(u) || isASCIIDigit(u) || u == 36 // + 0-9, $
    }

    @inline(__always)
    private static func isOperatorChar(_ u: UInt16) -> Bool {
        switch u {
        case 61, 60, 62, 33, 43, 45, 42, 47, 37, 94, 126, 124, 58, 64, 38:
            // =, <, >, !, +, -, *, /, %, ^, ~, |, :, @, &
            return true
        default:
            return false
        }
    }

    @inline(__always)
    private static func makeUpperASCIIString(units: [UInt16], start: Int, end: Int) -> String? {
        let count = end - start
        guard count > 0 && count <= 32 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        for idx in start..<end {
            let u = units[idx]
            if u > 127 { return nil }
            if u >= 97 && u <= 122 {
                bytes.append(UInt8(u - 32))
            } else {
                bytes.append(UInt8(u))
            }
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func matchDollarTagEnd(units: [UInt16], startIndex: Int) -> Int? {
        let len = units.count
        guard startIndex + 1 < len && units[startIndex] == 36 else { return nil }
        var idx = startIndex + 1
        if units[idx] == 36 {
            return idx + 1 // $$
        }
        guard isIdentifierStart(units[idx]) else { return nil }
        idx += 1
        while idx < len {
            let u = units[idx]
            if u == 36 {
                return idx + 1 // $tag$
            }
            if !(isIdentifierStart(u) || isASCIIDigit(u)) {
                return nil
            }
            idx += 1
        }
        return nil
    }

    private static func matchDollarTagSlice(units: [UInt16], tagStart: Int, tagLen: Int, at index: Int) -> Bool {
        guard index + tagLen <= units.count else { return false }
        for offset in 0..<tagLen {
            if units[tagStart + offset] != units[index + offset] {
                return false
            }
        }
        return true
    }

    private static func nsFontWeight(from weight: Font.Weight) -> NSFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
