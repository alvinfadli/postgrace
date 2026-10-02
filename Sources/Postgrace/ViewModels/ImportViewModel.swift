import Foundation
import SwiftUI
import AppKit

/// Observable ViewModel orchestrating file picking, column mapping, and import execution.
@Observable
public final class ImportViewModel {

    private let importService: ImportService
    private var targetTableColumns: [String] = []

    // UI Presentation state
    public var isShowingSheet: Bool = false
    public var configuration: ImportConfiguration?
    public var progress: DataTransferProgress = DataTransferProgress()
    public var isImporting: Bool = false
    public var errorMessage: String? = nil
    public var previewRows: [[String: String]] = []

    public init(postgresService: PostgresService) {
        self.importService = ImportService(postgresService: postgresService)
    }

    /// Prepares and opens the import sheet for a table.
    public func startTableImport(schema: String, table: String, tableColumns: [String] = []) {
        self.targetTableColumns = tableColumns
        self.configuration = nil
        self.progress = DataTransferProgress()
        self.errorMessage = nil
        self.previewRows = []
        self.isShowingSheet = true

        promptSelectFile(for: .table(schema: schema, table: table))
    }

    /// Prepares and opens the import sheet for a database.
    public func startDatabaseImport(database: String) {
        self.targetTableColumns = []
        self.configuration = nil
        self.progress = DataTransferProgress()
        self.errorMessage = nil
        self.previewRows = []
        self.isShowingSheet = true

        promptSelectFile(for: .database(name: database))
    }

    /// Prompts user to pick a source file.
    public func promptSelectFile(for scope: ImportTargetScope? = nil) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false

        if openPanel.runModal() == .OK, let fileURL = openPanel.url {
            let activeScope = scope ?? configuration?.targetScope ?? .database(name: "")
            setupConfiguration(for: fileURL, scope: activeScope)
        }
    }

    /// Configures the import and inspects headers / preview data.
    public func setupConfiguration(for fileURL: URL, scope: ImportTargetScope) {
        var config = ImportConfiguration(targetScope: scope, sourceURL: fileURL)

        if case .table = scope {
            if config.sourceType == .csv {
                if let (headers, previews) = try? CSVHandler.inspect(url: fileURL, maxPreviewRows: 3) {
                    config.columnMappings = autoMapColumns(headers: headers, previewSamples: previews)
                }
            } else if config.sourceType == .json {
                if let (keys, previews) = try? JSONHandler.inspect(url: fileURL, maxPreviewRows: 3) {
                    var sampleGrid: [[String]] = []
                    for row in previews {
                        sampleGrid.append(keys.map { row[$0] ?? "" })
                    }
                    config.columnMappings = autoMapColumns(headers: keys, previewSamples: sampleGrid)
                }
            }
        }

        self.configuration = config
    }

    private func autoMapColumns(headers: [String], previewSamples: [[String]]) -> [ColumnMappingItem] {
        return headers.enumerated().map { (index, header) in
            // Try to match target column case-insensitively
            let matchedTarget = targetTableColumns.first(where: {
                $0.lowercased() == header.lowercased() ||
                $0.lowercased().replacingOccurrences(of: "_", with: "") == header.lowercased().replacingOccurrences(of: "_", with: "")
            })

            var samples: [String] = []
            for row in previewSamples {
                if index < row.count {
                    samples.append(row[index])
                }
            }

            return ColumnMappingItem(
                sourceColumn: header,
                targetColumn: matchedTarget ?? (targetTableColumns.contains(header) ? header : nil),
                sampleValues: samples
            )
        }
    }

    private var activeTask: Task<Void, Never>?

    public func cancelImport() {
        activeTask?.cancel()
        activeTask = nil
        isImporting = false
        progress.status = .cancelled
    }

    /// Executes the import task.
    public func performImport() {
        guard let config = configuration else { return }
        self.isImporting = true
        self.errorMessage = nil

        self.activeTask = Task { @MainActor in
            do {
                try await importService.importData(config: config) { [weak self] currentProgress in
                    Task { @MainActor in
                        self?.progress = currentProgress
                    }
                }
                self.isImporting = false
            } catch is CancellationError {
                self.isImporting = false
                self.progress.status = .cancelled
            } catch {
                self.isImporting = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func closeSheet() {
        if isImporting {
            cancelImport()
        }
        self.isShowingSheet = false
    }
}
