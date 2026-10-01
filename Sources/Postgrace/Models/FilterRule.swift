import Foundation

/// Supported comparison operators for visual table filtering.
public enum FilterOperator: String, CaseIterable, Identifiable, Hashable, Codable {
    case equals = "="
    case notEquals = "!="
    case greaterThan = ">"
    case lessThan = "<"
    case greaterThanOrEqual = ">="
    case lessThanOrEqual = "<="
    case contains = "contains"
    case startsWith = "starts with"
    case endsWith = "ends with"
    case isNull = "is NULL"
    case isNotNull = "is NOT NULL"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .equals: return "= (equals)"
        case .notEquals: return "≠ (not equals)"
        case .greaterThan: return "> (greater than)"
        case .lessThan: return "< (less than)"
        case .greaterThanOrEqual: return "≥ (greater or equal)"
        case .lessThanOrEqual: return "≤ (less or equal)"
        case .contains: return "contains (ILIKE)"
        case .startsWith: return "starts with"
        case .endsWith: return "ends with"
        case .isNull: return "is NULL"
        case .isNotNull: return "is NOT NULL"
        }
    }

    /// Whether this operator expects a user input value.
    public var requiresValue: Bool {
        self != .isNull && self != .isNotNull
    }
}

/// Logical conjunction between multiple filter conditions.
public enum FilterConjunction: String, CaseIterable, Identifiable, Hashable, Codable {
    case and = "AND"
    case or = "OR"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .and: return "Match ALL (AND)"
        case .or: return "Match ANY (OR)"
        }
    }
}

/// A structured filter rule representing a single condition in the visual filter builder.
public struct FilterRule: Identifiable, Hashable, Codable {
    public let id: UUID
    public var column: String
    public var op: FilterOperator
    public var value: String

    public init(id: UUID = UUID(), column: String = "", op: FilterOperator = .equals, value: String = "") {
        self.id = id
        self.column = column
        self.op = op
        self.value = value
    }

    /// Compiles this rule into a safe SQL WHERE condition.
    public func toSQLExpression() -> String? {
        let trimmedCol = column.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCol.isEmpty else { return nil }
        let quotedCol = trimmedCol.pgQuotedIdentifier

        switch op {
        case .isNull:
            return "\(quotedCol) IS NULL"
        case .isNotNull:
            return "\(quotedCol) IS NOT NULL"
        case .contains:
            let escaped = value.pgEscapedLiteral
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            return "\(quotedCol)::text ILIKE '%\(escaped)%'"
        case .startsWith:
            let escaped = value.pgEscapedLiteral
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            return "\(quotedCol)::text ILIKE '\(escaped)%'"
        case .endsWith:
            let escaped = value.pgEscapedLiteral
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            return "\(quotedCol)::text ILIKE '%\(escaped)'"
        case .equals, .notEquals, .greaterThan, .lessThan, .greaterThanOrEqual, .lessThanOrEqual:
            let trimmedVal = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedVal.isEmpty else { return nil }

            if trimmedVal.lowercased() == "true" || trimmedVal.lowercased() == "false" {
                return "\(quotedCol) \(op.rawValue) \(trimmedVal.lowercased())"
            } else if let _ = Double(trimmedVal), !trimmedVal.hasPrefix("0") || trimmedVal == "0" {
                // Numeric literal (e.g. 100, -5, 3.14)
                return "\(quotedCol) \(op.rawValue) \(trimmedVal)"
            } else {
                // String literal with SQL-92 single-quote escaping
                return "\(quotedCol) \(op.rawValue) '\(trimmedVal.pgEscapedLiteral)'"
            }
        }
    }
}
