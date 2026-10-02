import SwiftUI

/// Modern modal sheet for configuring and executing data exports across Table, Schema, and Database scopes.
struct ExportSheet: View {
    @Environment(ExportViewModel.self) private var exportViewModel

    var body: some View {
        @Bindable var vm = exportViewModel

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(PostgraceTheme.accentSky)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Data")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)

                    Text(vm.configuration.scope.title)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    vm.closeSheet()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(vm.isExporting)
            }
            .padding(16)
            .background(PostgraceTheme.surfaceElevated)
            .overlay(
                Rectangle()
                    .fill(PostgraceTheme.border)
                    .frame(height: PostgraceTheme.hairlineBorder),
                alignment: .bottom
            )

            // Body
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. Format Selection
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EXPORT FORMAT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $vm.configuration.format) {
                            ForEach(availableFormats(for: vm.configuration.scope)) { fmt in
                                Text(fmt.rawValue).tag(fmt)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(vm.isExporting)

                        Text(vm.configuration.format.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Divider().background(PostgraceTheme.border)

                    // 2. Options per format & scope
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OPTIONS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        switch vm.configuration.format {
                        case .csv:
                            csvOptionsView(config: $vm.configuration)
                        case .json:
                            jsonOptionsView(config: $vm.configuration)
                        case .sql:
                            sqlOptionsView(config: $vm.configuration)
                        case .customDump:
                            customDumpOptionsView(config: $vm.configuration)
                        }

                        // Table row limit & WHERE clause preview
                        if case .table = vm.configuration.scope {
                            if !vm.configuration.whereClause.isEmpty {
                                HStack(spacing: 6) {
                                    Text("Filter:")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(PostgraceTheme.accentSky)
                                    Text("WHERE \(vm.configuration.whereClause)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(8)
                                .background(PostgraceTheme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }

                    // 3. Live Progress Display
                    if vm.isExporting || vm.progress.status != .idle {
                        Divider().background(PostgraceTheme.border)
                        exportProgressSection(progress: vm.progress, isExporting: vm.isExporting)
                    }

                    // 4. Error Message Banner
                    if let err = vm.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(err)
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(16)
            }

            // Footer Actions
            HStack {
                Spacer()

                if case .completed = vm.progress.status {
                    Button("Done") {
                        vm.closeSheet()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else if vm.isExporting {
                    Button("Cancel Export") {
                        vm.cancelExport()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(PostgraceTheme.destructiveRed)

                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 8)
                } else {
                    Button("Cancel") {
                        vm.closeSheet()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                    Button {
                        vm.promptSaveAndExport()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Export To File…")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(PostgraceTheme.accentSky)
                }
            }
            .padding(14)
            .background(PostgraceTheme.surfaceElevated)
            .overlay(
                Rectangle()
                    .fill(PostgraceTheme.border)
                    .frame(height: PostgraceTheme.hairlineBorder),
                alignment: .top
            )
        }
        .frame(width: 520, height: 460)
        .background(PostgraceTheme.canvas)
    }

    private func availableFormats(for scope: ExportScope) -> [ExportFormat] {
        switch scope {
        case .table:
            return [.csv, .json, .sql]
        case .schema, .database:
            return [.sql, .customDump]
        }
    }

    // MARK: - Options Views

    @ViewBuilder
    private func csvOptionsView(config: Binding<ExportConfiguration>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Include Header Row (Column Names)", isOn: config.csvIncludeHeaders)
                .font(.system(size: 11))

            Toggle("Include UTF-8 BOM (for Microsoft Excel)", isOn: config.csvIncludeBOM)
                .font(.system(size: 11))

            HStack(spacing: 8) {
                Text("Delimiter:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Picker("", selection: config.csvDelimiter) {
                    Text("Comma (,)").tag(",")
                    Text("Tab (\\t)").tag("\t")
                    Text("Semicolon (;)").tag(";")
                    Text("Pipe (|)").tag("|")
                }
                .frame(width: 140)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func jsonOptionsView(config: Binding<ExportConfiguration>) -> some View {
        Picker("Format Style:", selection: config.jsonFlavor) {
            ForEach(JSONExportFlavor.allCases) { flavor in
                Text(flavor.rawValue).tag(flavor)
            }
        }
        .pickerStyle(.radioGroup)
        .font(.system(size: 11))
    }

    @ViewBuilder
    private func sqlOptionsView(config: Binding<ExportConfiguration>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Include DROP TABLE IF EXISTS statement", isOn: config.sqlIncludeDropTable)
                .font(.system(size: 11))

            HStack(spacing: 8) {
                Text("Rows per INSERT batch:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Picker("", selection: config.sqlBatchSize) {
                    Text("100 rows").tag(100)
                    Text("200 rows").tag(200)
                    Text("500 rows").tag(500)
                    Text("1,000 rows").tag(1000)
                }
                .frame(width: 140)
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func customDumpOptionsView(config: Binding<ExportConfiguration>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Export Table Schema (DDL)", isOn: config.exportStructure)
                .font(.system(size: 11))

            Toggle("Export Table Data", isOn: config.exportData)
                .font(.system(size: 11))

            Toggle("Include clean commands (--clean --if-exists)", isOn: config.cleanBeforeRestore)
                .font(.system(size: 11))
        }
    }

    // MARK: - Progress Section

    @ViewBuilder
    private func exportProgressSection(progress: DataTransferProgress, isExporting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(progress.currentOperation)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                if case .completed(let msg) = progress.status {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PostgraceTheme.emeraldRw)
                } else if isExporting {
                    Text(progress.formattedThroughput)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if let fraction = progress.fractionCompleted {
                ProgressView(value: fraction)
            } else if isExporting {
                ProgressView()
            }

            HStack {
                Text("\(progress.rowsProcessed) rows written")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Text(progress.formattedBytes)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(PostgraceTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
