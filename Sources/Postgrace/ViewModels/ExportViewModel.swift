import Foundation
import SwiftUI
import AppKit

/// Observable ViewModel orchestrating the Export workflow, options, and progress modal.
@Observable
public final class ExportViewModel {

    private let exportService: ExportService
    private let postgresService: PostgresService

    // UI Presentation state
    public var isShowingSheet: Bool = false
    public var configuration: ExportConfiguration
    public var progress: DataTransferProgress = DataTransferProgress()
    public var isExporting: Bool = false
    public var errorMessage: String? = nil

    // Table & Schema Selection State
    public var availableTables: [ExportTableItem] = []
    public var availableSchemas: [String] = []
    public var tableSearchFilter: String = ""
    public var isLoadingTables: Bool = false

    public init(postgresService: PostgresService) {
        self.postgresService = postgresService
        self.exportService = ExportService(postgresService: postgresService)
        self.configuration = ExportConfiguration(scope: .database(name: ""))
    }

    /// Filtered available tables according to tableSearchFilter.
    public var filteredAvailableTables: [ExportTableItem] {
        let trimmed = tableSearchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return availableTables
        }
        return availableTables.filter {
            $0.table.localizedCaseInsensitiveContains(trimmed) ||
            $0.schema.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public func isTableSelected(_ item: ExportTableItem) -> Bool {
        configuration.selectedTables.contains(item)
    }

    public func toggleTableSelection(_ item: ExportTableItem) {
        if let idx = configuration.selectedTables.firstIndex(of: item) {
            configuration.selectedTables.remove(at: idx)
        } else {
            configuration.selectedTables.append(item)
        }
    }

    public func selectAllTables() {
        for item in filteredAvailableTables where !configuration.selectedTables.contains(item) {
            configuration.selectedTables.append(item)
        }
    }

    public func deselectAllTables() {
        let currentFilteredSet = Set(filteredAvailableTables)
        configuration.selectedTables.removeAll { currentFilteredSet.contains($0) }
    }

    /// Prepares and opens the export sheet for a single table.
    public func startTableExport(schema: String, table: String, filterClause: String = "") {
        let item = ExportTableItem(schema: schema, table: table)
        var config = ExportConfiguration(scope: .table(schema: schema, table: table), format: .csv)
        config.whereClause = filterClause
        config.selectedTables = [item]
        self.configuration = config
        self.availableTables = [item]
        self.tableSearchFilter = ""
        self.progress = DataTransferProgress()
        self.errorMessage = nil
        self.isShowingSheet = true
    }

    /// Prepares and opens the export sheet for multiple specified tables.
    public func startMultipleTablesExport(tables: [ExportTableItem]) {
        var config = ExportConfiguration(scope: .multipleTables(items: tables), format: .sql)
        config.selectedTables = tables
        self.configuration = config
        self.availableTables = tables
        self.tableSearchFilter = ""
        self.progress = DataTransferProgress()
        self.errorMessage = nil
        self.isShowingSheet = true
    }

    /// Prepares and opens the export sheet for an entire schema.
    public func startSchemaExport(schema: String) {
        var config = ExportConfiguration(scope: .schema(name: schema), format: .sql)
        config.selectedSchemas = [schema]
        self.configuration = config
        self.availableTables = []
        self.tableSearchFilter = ""
        self.progress = DataTransferProgress()
        self.errorMessage = nil
        self.isShowingSheet = true

        Task { @MainActor in
            await loadTablesForSchema(schema)
        }
    }

    /// Prepares and opens the export sheet for multiple schemas.
    public func startMultipleSchemasExport(schemas: [String]) {
        var config = ExportConfiguration(scope: .multipleSchemas(names: schemas), format: .sql)
        config.selectedSchemas = schemas
        self.configuration = config
        self.availableTables = []
        self.tableSearchFilter = ""
        self.progress = DataTransferProgress()
        self.errorMessage = nil
        self.isShowingSheet = true

        Task { @MainActor in
            await loadTablesForMultipleSchemas(schemas)
        }
    }

    /// Prepares and opens the export sheet for an entire database.
    public func startDatabaseExport(database: String) {
        self.configuration = ExportConfiguration(scope: .database(name: database), format: .sql)
        self.availableTables = []
        self.tableSearchFilter = ""
        self.progress = DataTransferProgress()
        self.errorMessage = nil
        self.isShowingSheet = true

        Task { @MainActor in
            await loadTablesForDatabase()
        }
    }

    public func loadTablesForSchema(_ schema: String) async {
        isLoadingTables = true
        let query = """
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_schema = '\(schema.pgEscapedLiteral)'
              AND table_type IN ('BASE TABLE', 'VIEW')
            ORDER BY table_name ASC;
        """
        do {
            let result = try await postgresService.executeQuery(query)
            var items: [ExportTableItem] = []
            for row in result.rows {
                if row.count >= 2,
                   case .string(let s) = row[0],
                   case .string(let t) = row[1] {
                    items.append(ExportTableItem(schema: s, table: t))
                }
            }
            self.availableTables = items
            self.configuration.selectedTables = items
        } catch {
            print("Failed to load tables for schema export: \(error)")
        }
        isLoadingTables = false
    }

    public func loadTablesForMultipleSchemas(_ schemas: [String]) async {
        guard !schemas.isEmpty else { return }
        isLoadingTables = true
        let inClause = schemas.map { "'\($0.pgEscapedLiteral)'" }.joined(separator: ", ")
        let query = """
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_schema IN (\(inClause))
              AND table_type IN ('BASE TABLE', 'VIEW')
            ORDER BY table_schema ASC, table_name ASC;
        """
        do {
            let result = try await postgresService.executeQuery(query)
            var items: [ExportTableItem] = []
            for row in result.rows {
                if row.count >= 2,
                   case .string(let s) = row[0],
                   case .string(let t) = row[1] {
                    items.append(ExportTableItem(schema: s, table: t))
                }
            }
            self.availableTables = items
            self.configuration.selectedTables = items
        } catch {
            print("Failed to load tables for schemas export: \(error)")
        }
        isLoadingTables = false
    }

    public func loadTablesForDatabase() async {
        isLoadingTables = true
        let query = """
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_schema NOT LIKE 'pg_%'
              AND table_schema != 'information_schema'
              AND table_type IN ('BASE TABLE', 'VIEW')
            ORDER BY table_schema ASC, table_name ASC;
        """
        do {
            let result = try await postgresService.executeQuery(query)
            var items: [ExportTableItem] = []
            for row in result.rows {
                if row.count >= 2,
                   case .string(let s) = row[0],
                   case .string(let t) = row[1] {
                    items.append(ExportTableItem(schema: s, table: t))
                }
            }
            self.availableTables = items
            self.configuration.selectedTables = items
        } catch {
            print("Failed to load tables for database export: \(error)")
        }
        isLoadingTables = false
    }

    /// Prompts the user with NSSavePanel and begins export.
    public func promptSaveAndExport() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = configuration.suggestedFileName
        savePanel.allowedContentTypes = []

        if savePanel.runModal() == .OK, let destinationURL = savePanel.url {
            configuration.destinationURL = destinationURL
            performExport(to: destinationURL)
        }
    }

    private var activeTask: Task<Void, Never>?

    public func cancelExport() {
        activeTask?.cancel()
        activeTask = nil
        isExporting = false
        progress.status = .cancelled
    }

    private func performExport(to destinationURL: URL) {
        self.isExporting = true
        self.errorMessage = nil

        self.activeTask = Task { @MainActor in
            do {
                try await exportService.export(
                    config: configuration,
                    destinationURL: destinationURL
                ) { [weak self] currentProgress in
                    Task { @MainActor in
                        self?.progress = currentProgress
                    }
                }
                self.isExporting = false
            } catch is CancellationError {
                self.isExporting = false
                self.progress.status = .cancelled
            } catch {
                self.isExporting = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func closeSheet() {
        if isExporting {
            cancelExport()
        }
        self.isShowingSheet = false
    }
}
