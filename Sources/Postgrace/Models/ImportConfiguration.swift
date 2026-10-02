import Foundation

/// Defines the target scope for data import.
public enum ImportTargetScope: Equatable, Hashable {
    case table(schema: String, table: String)
    case database(name: String)

    public var title: String {
        switch self {
        case .table(let schema, let table):
            return "\(schema).\(table)"
        case .database(let name):
            return "Database: \(name)"
        }
    }
}

/// Supported import source file types.
public enum ImportSourceType: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    case sql = "SQL Script (.sql)"
    case customDump = "PostgreSQL Dump (.dump / .tar)"

    public var id: String { rawValue }

    public static func detect(from url: URL) -> ImportSourceType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "csv", "tsv", "txt":
            return .csv
        case "json", "ndjson", "jsonl":
            return .json
        case "sql":
            return .sql
        case "dump", "tar", "pgdump":
            return .customDump
        default:
            return .csv
        }
    }
}

/// How to handle insertion conflicts or errors.
public enum ImportConflictPolicy: String, CaseIterable, Identifiable {
    case abort = "Abort on first error (Rollback)"
    case skipErrors = "Continue on error (Skip invalid rows)"

    public var id: String { rawValue }
}

/// Column mapping item pairing a source file header/key with a target table column.
public struct ColumnMappingItem: Identifiable, Equatable {
    public var id: String { sourceColumn }
    public var sourceColumn: String
    public var targetColumn: String? // nil means ignore/skip
    public var sampleValues: [String]

    public init(sourceColumn: String, targetColumn: String? = nil, sampleValues: [String] = []) {
        self.sourceColumn = sourceColumn
        self.targetColumn = targetColumn
        self.sampleValues = sampleValues
    }
}

/// Configuration parameters for an import task.
public struct ImportConfiguration: Equatable {
    public var targetScope: ImportTargetScope
    public var sourceURL: URL
    public var sourceType: ImportSourceType

    // Table import CSV/JSON options
    public var csvDelimiter: String = ","
    public var hasHeaders: Bool = true
    public var batchSize: Int = 250
    public var conflictPolicy: ImportConflictPolicy = .abort
    public var treatEmptyAsNull: Bool = true
    public var columnMappings: [ColumnMappingItem] = []

    public init(targetScope: ImportTargetScope, sourceURL: URL, sourceType: ImportSourceType? = nil) {
        self.targetScope = targetScope
        self.sourceURL = sourceURL
        self.sourceType = sourceType ?? ImportSourceType.detect(from: sourceURL)
    }
}
