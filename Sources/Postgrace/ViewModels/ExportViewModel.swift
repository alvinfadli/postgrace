import Foundation
import SwiftUI
import AppKit

/// Observable ViewModel orchestrating the Export workflow, options, and progress modal.
@Observable
public final class ExportViewModel {

    private let exportService: ExportService

    // UI Presentation state
    public var isShowingSheet: Bool = false
    public var configuration: ExportConfiguration
    public var progress: DataTransferProgress = DataTransferProgress()
    public var isExporting: Bool = false
    public var errorMessage: String? = nil

    public init(postgresService: PostgresService) {
        self.exportService = ExportService(postgresService: postgresService)
        self.configuration = ExportConfiguration(scope: .database(name: ""))
    }

    /// Prepares and opens the export sheet for a table.
    public func startTableExport(schema: String, table: String, filterClause: String = "") {
        var config = ExportConfiguration(scope: .table(schema: schema, table: table), format: .csv)
        config.whereClause = filterClause
        self.configuration = config
        self.progress = DataTransferProgress()
        self.errorMessage = nil
        self.isShowingSheet = true
    }

    /// Prepares and opens the export sheet for an entire schema.
    public func startSchemaExport(schema: String) {
        self.configuration = ExportConfiguration(scope: .schema(name: schema), format: .sql)
        self.progress = DataTransferProgress()
        self.errorMessage = nil
        self.isShowingSheet = true
    }

    /// Prepares and opens the export sheet for an entire database.
    public func startDatabaseExport(database: String) {
        self.configuration = ExportConfiguration(scope: .database(name: database), format: .sql)
        self.progress = DataTransferProgress()
        self.errorMessage = nil
        self.isShowingSheet = true
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

    private func performExport(to destinationURL: URL) {
        self.isExporting = true
        self.errorMessage = nil

        Task { @MainActor in
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
            } catch {
                self.isExporting = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func closeSheet() {
        guard !isExporting else { return }
        self.isShowingSheet = false
    }
}
