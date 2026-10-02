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
                    // 1. Export Content Mode (Structure / Data / Both)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EXPORT CONTENT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $vm.configuration.contentMode) {
                            ForEach(ExportContentMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(vm.isExporting)
                        .onChange(of: vm.configuration.contentMode) { _, newMode in
                            if newMode == .structureOnly && (vm.configuration.format == .csv || vm.configuration.format == .json) {
                                vm.configuration.format = .sql
                            }
                        }

                        Text(vm.configuration.contentMode.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Divider().background(PostgraceTheme.border)

                    // 2. Format Selection
                    VStack(alignment: .leading, spacing: 6) {
                        Text("EXPORT FORMAT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Picker("", selection: $vm.configuration.format) {
                            ForEach(availableFormats(for: vm.configuration.scope, contentMode: vm.configuration.contentMode)) { fmt in
                                Text(fmt.rawValue).tag(fmt)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(vm.isExporting)

                        Text(vm.configuration.format.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    // 3. Table Selection & Filter (for multiple tables, schemas, or database)
                    if vm.availableTables.count > 1 || shouldShowTableSelection(for: vm.configuration.scope) {
                        Divider().background(PostgraceTheme.border)
                        tableSelectionSection()
                    }

                    // 4. Row Data Filter (WHERE clause & Limit)
                    if vm.configuration.contentMode != .structureOnly {
                        Divider().background(PostgraceTheme.border)
                        rowFilterSection()
                    }

                    Divider().background(PostgraceTheme.border)

                    // 5. Options per format & scope
                    VStack(alignment: .leading, spacing: 12) {
                        Text("FORMAT OPTIONS")
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
                    }

                    // 6. Live Progress Display
                    if vm.isExporting || vm.progress.status != .idle {
                        Divider().background(PostgraceTheme.border)
                        exportProgressSection(progress: vm.progress, isExporting: vm.isExporting)
                    }

                    // 7. Error Message Banner
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
                    .disabled(isExportDisabled)
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
        .frame(width: 580, height: 560)
        .background(PostgraceTheme.canvas)
    }

    private var isExportDisabled: Bool {
        if exportViewModel.isExporting { return true }
        if shouldShowTableSelection(for: exportViewModel.configuration.scope) && exportViewModel.configuration.selectedTables.isEmpty {
            return true
        }
        return false
    }

    private func shouldShowTableSelection(for scope: ExportScope) -> Bool {
        switch scope {
        case .table:
            return false
        case .multipleTables, .schema, .multipleSchemas, .database:
            return true
        }
    }

    private func availableFormats(for scope: ExportScope, contentMode: ExportContentMode) -> [ExportFormat] {
        if contentMode == .structureOnly {
            return [.sql, .customDump]
        }
        switch scope {
        case .table:
            return [.csv, .json, .sql, .customDump]
        case .multipleTables:
            return [.sql, .customDump, .json]
        case .schema, .multipleSchemas, .database:
            return [.sql, .customDump]
        }
    }

    // MARK: - Table Selection Subview

    @ViewBuilder
    private func tableSelectionSection() -> some View {
        @Bindable var vm = exportViewModel

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TABLES TO EXPORT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(vm.configuration.selectedTables.count) of \(vm.availableTables.count) selected")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Search filter & bulk toggles
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("Filter tables…", text: $vm.tableSearchFilter)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !vm.tableSearchFilter.isEmpty {
                        Button {
                            vm.tableSearchFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(PostgraceTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )

                Button("Select All") {
                    vm.selectAllTables()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(PostgraceTheme.accentSky)

                Text("•").foregroundColor(PostgraceTheme.border)

                Button("Deselect All") {
                    vm.deselectAllTables()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(PostgraceTheme.accentSky)
            }

            // Table checklist
            if vm.isLoadingTables && vm.availableTables.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading tables…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(20)
            } else if vm.filteredAvailableTables.isEmpty {
                Text("No matching tables found.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(vm.filteredAvailableTables) { item in
                            let isSelected = vm.isTableSelected(item)
                            Button {
                                vm.toggleTableSelection(item)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                        .foregroundColor(isSelected ? PostgraceTheme.accentSky : .secondary)
                                        .font(.system(size: 12))

                                    Text(item.schema)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(PostgraceTheme.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))

                                    Text(item.table)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.primary)

                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isSelected ? PostgraceTheme.accentSky.opacity(0.08) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 140)
                .background(PostgraceTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )
            }
        }
    }

    // MARK: - Row Filter Subview

    @ViewBuilder
    private func rowFilterSection() -> some View {
        @Bindable var vm = exportViewModel

        VStack(alignment: .leading, spacing: 8) {
            Text("DATA FILTER")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text("WHERE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(PostgraceTheme.accentSky)

                TextField("Optional filter clause (e.g. status = 'active' AND created_at >= '2025-01-01')", text: $vm.configuration.whereClause)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
            }
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
