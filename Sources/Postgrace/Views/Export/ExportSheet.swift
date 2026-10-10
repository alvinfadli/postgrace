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

                        PostgraceSegmentedControl(
                            selection: $vm.configuration.contentMode,
                            items: ExportContentMode.allCases,
                            titleFor: { $0.rawValue }
                        )
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

                        PostgraceSegmentedControl(
                            selection: $vm.configuration.format,
                            items: availableFormats(for: vm.configuration.scope, contentMode: vm.configuration.contentMode),
                            titleFor: { $0.rawValue }
                        )
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

                    // 6. PostgreSQL Advanced Options
                    if vm.configuration.format == .sql || vm.configuration.format == .customDump {
                        Divider().background(PostgraceTheme.border)
                        postgresAdvancedOptionsSection(config: $vm.configuration)
                    }

                    // 7. Live Progress Display
                    if vm.isExporting || vm.progress.status != .idle {
                        Divider().background(PostgraceTheme.border)
                        exportProgressSection(progress: vm.progress, isExporting: vm.isExporting)
                    }

                    // 8. Error Message Banner
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
                    PostgraceButton("Done", variant: .primary) {
                        vm.closeSheet()
                    }
                } else if vm.isExporting {
                    PostgraceButton("Cancel Export", variant: .destructive) {
                        vm.cancelExport()
                    }

                    PostgraceSpinner(size: .small)
                        .padding(.leading, 8)
                } else {
                    PostgraceButton("Cancel", variant: .secondary) {
                        vm.closeSheet()
                    }

                    PostgraceButton(
                        "Export To File…",
                        icon: "square.and.arrow.down",
                        variant: .primary
                    ) {
                        vm.promptSaveAndExport()
                    }
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

            // Schema filter chips when multiple schemas are present
            if vm.availableSchemas.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(vm.availableSchemas, id: \.self) { schema in
                            let isSelected = vm.isSchemaSelected(schema)
                            Button {
                                vm.toggleSchemaSelection(schema)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 10))
                                    Text(schema)
                                        .font(.system(size: 11, design: .monospaced))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(isSelected ? PostgraceTheme.accentSky.opacity(0.12) : PostgraceTheme.surfaceElevated)
                                .foregroundColor(isSelected ? PostgraceTheme.accentSky : .secondary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? PostgraceTheme.accentSky.opacity(0.3) : PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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
                    PostgraceSpinner(size: .small)
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

                PostgraceTextField(
                    "Optional filter clause (e.g. status = 'active' AND created_at >= '2025-01-01')",
                    text: $vm.configuration.whereClause,
                    isMonospaced: true
                )
            }
        }
    }

    // MARK: - Options Views

    @ViewBuilder
    private func csvOptionsView(config: Binding<ExportConfiguration>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PostgraceCheckbox("Include Header Row (Column Names)", isOn: config.csvIncludeHeaders)
            PostgraceCheckbox("Include UTF-8 BOM (for Microsoft Excel)", isOn: config.csvIncludeBOM)

            HStack(spacing: 8) {
                Text("Delimiter:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                PostgracePicker(
                    selection: config.csvDelimiter,
                    items: [",", "\t", ";", "|"],
                    titleFor: { d in
                        switch d {
                        case ",": return "Comma (,)"
                        case "\t": return "Tab (\\t)"
                        case ";": return "Semicolon (;)"
                        case "|": return "Pipe (|)"
                        default: return d
                        }
                    }
                )
                .frame(width: 150)
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
            PostgraceCheckbox("Include DROP TABLE IF EXISTS statement", isOn: config.sqlIncludeDropTable)

            HStack(spacing: 8) {
                Text("Rows per INSERT batch:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                PostgracePicker(
                    selection: config.sqlBatchSize,
                    items: [100, 200, 500, 1000],
                    titleFor: { "\($0) rows" }
                )
                .frame(width: 140)
            }
        }
    }

    @ViewBuilder
    private func customDumpOptionsView(config: Binding<ExportConfiguration>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PostgraceCheckbox("Include clean commands (--clean --if-exists)", isOn: config.cleanBeforeRestore)

            HStack(spacing: 8) {
                Text("Compression level:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                PostgracePicker(
                    selection: config.postgresOptions.customDumpCompressionLevel,
                    items: [1, 3, 6, 9],
                    titleFor: { "Level \($0)\($0 == 6 ? " (Default)" : "")" }
                )
                .frame(width: 160)
            }
        }
    }

    // MARK: - PostgreSQL Advanced Options

    @ViewBuilder
    private func postgresAdvancedOptionsSection(config: Binding<ExportConfiguration>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("POSTGRESQL ADVANCED OPTIONS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            PostgraceCheckbox("Clean before restore (DROP ... IF EXISTS)", isOn: config.postgresOptions.cleanBeforeRestore)
            PostgraceCheckbox("Wrap in single transaction (BEGIN ... COMMIT)", isOn: config.postgresOptions.singleTransaction)
            PostgraceCheckbox("Include CREATE SCHEMA declaration", isOn: config.postgresOptions.includeSchemaCreate)
            PostgraceCheckbox("Set search_path header", isOn: config.postgresOptions.setPathHeader)

            if isSingleSchemaOrTableScope(config.wrappedValue.scope) {
                PostgraceCheckbox("Include external cross-schema foreign keys", isOn: config.postgresOptions.includeExternalForeignKeys)
            }
        }
    }

    private func isSingleSchemaOrTableScope(_ scope: ExportScope) -> Bool {
        switch scope {
        case .table, .schema:
            return true
        default:
            return false
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
                PostgraceProgressBar(progress: fraction, height: 6, showPercentLabel: true)
            } else if isExporting {
                HStack(spacing: 8) {
                    PostgraceSpinner(size: .small)
                    Text("Streaming data transfer in progress…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
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
