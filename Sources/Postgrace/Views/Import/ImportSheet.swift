import SwiftUI

/// Modern modal sheet for configuring column mapping and executing data imports.
struct ImportSheet: View {
    @Environment(ImportViewModel.self) private var importViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel

    var body: some View {
        @Bindable var vm = importViewModel

        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(PostgraceTheme.accentSky)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Data")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)

                    if let cfg = vm.configuration {
                        Text("Target: \(cfg.targetScope.title)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
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
                .disabled(vm.isImporting)
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
                    if isConnectedUserReadOnly {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(PostgraceTheme.amberRo)
                            Text("Warning: Connected user '\(schemaViewModel.userPrivileges?.username ?? "")' has Read-Only permissions. Import may fail if the server rejects INSERT / DDL commands.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(PostgraceTheme.amberRoMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    if let config = vm.configuration {
                        // 1. Source File Card
                        sourceFileCard(config: config)

                        // 2. Column Mapping (For Table Import)
                        if case .table(let schema, let table) = config.targetScope {
                            columnMappingSection(schema: schema, table: table)
                        }

                        // 3. Options
                        importOptionsSection(config: config)

                        // 4. Progress Section
                        if vm.isImporting || vm.progress.status != .idle {
                            Divider().background(PostgraceTheme.border)
                            importProgressSection(progress: vm.progress, isImporting: vm.isImporting)
                        }

                        // 5. Error Banner
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
                    } else {
                        // No file selected yet
                        VStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)

                            Text("Select a file to import")
                                .font(.system(size: 13, weight: .semibold))

                            Button("Choose File…") {
                                vm.promptSelectFile()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
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
                } else if vm.isImporting {
                    Button("Cancel Import") {
                        vm.cancelImport()
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
                        vm.performImport()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.doc")
                            Text("Start Import")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(PostgraceTheme.accentSky)
                    .disabled(vm.configuration == nil)
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
        .frame(width: 560, height: 500)
        .background(PostgraceTheme.canvas)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func sourceFileCard(config: ImportConfiguration) -> some View {
        HStack(spacing: 10) {
            Image(systemName: iconForSourceType(config.sourceType))
                .font(.system(size: 20))
                .foregroundColor(PostgraceTheme.accentSky)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.sourceURL.lastPathComponent)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                Text("Format: \(config.sourceType.rawValue)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Change File…") {
                importViewModel.promptSelectFile()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(PostgraceTheme.accentSky)
            .disabled(importViewModel.isImporting)
        }
        .padding(10)
        .background(PostgraceTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
        )
    }

    @ViewBuilder
    private func columnMappingSection(schema: String, table: String) -> some View {
        let tableCols = schemaViewModel.columns["\(schema).\(table)"]?.map(\.name) ?? []

        VStack(alignment: .leading, spacing: 8) {
            Text("COLUMN MAPPING")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                // Header
                HStack {
                    Text("Source Column")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundColor(.clear)

                    Text("Target Column")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                // Rows
                if let mappings = importViewModel.configuration?.columnMappings {
                    ForEach(Array(mappings.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            Text(item.sourceColumn)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)

                            Picker("", selection: Binding(
                                get: { item.targetColumn ?? "" },
                                set: { newVal in
                                    if var cfg = importViewModel.configuration {
                                        cfg.columnMappings[index].targetColumn = newVal.isEmpty ? nil : newVal
                                        importViewModel.configuration = cfg
                                    }
                                }
                            )) {
                                Text("(Skip Column)").tag("")
                                ForEach(tableCols, id: \.self) { col in
                                    Text(col).tag(col)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(index % 2 == 0 ? PostgraceTheme.surfaceElevated : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(6)
            .background(PostgraceTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
            )
        }
    }

    @ViewBuilder
    private func importOptionsSection(config: ImportConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPTIONS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Text("Conflict Resolution:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { config.conflictPolicy },
                    set: { importViewModel.configuration?.conflictPolicy = $0 }
                )) {
                    ForEach(ImportConflictPolicy.allCases) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                .controlSize(.small)
            }

            if config.sourceType == .csv || config.sourceType == .json {
                Toggle("Treat empty text fields as NULL", isOn: Binding(
                    get: { config.treatEmptyAsNull },
                    set: { importViewModel.configuration?.treatEmptyAsNull = $0 }
                ))
                .font(.system(size: 11))
                .toggleStyle(.checkbox)
            }
        }
    }

    @ViewBuilder
    private func importProgressSection(progress: DataTransferProgress, isImporting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(progress.currentOperation)
                    .font(.system(size: 11, weight: .semibold))

                Spacer()

                if case .completed(let msg) = progress.status {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(PostgraceTheme.emeraldRw)
                } else if isImporting {
                    Text(progress.formattedThroughput)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            if let fraction = progress.fractionCompleted {
                ProgressView(value: fraction)
            } else if isImporting {
                ProgressView()
            }

            Text("\(progress.rowsProcessed) rows inserted")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(PostgraceTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func iconForSourceType(_ type: ImportSourceType) -> String {
        switch type {
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        case .sql: return "terminal"
        case .customDump: return "archivebox"
        }
    }

    private var isConnectedUserReadOnly: Bool {
        guard let privs = schemaViewModel.userPrivileges else { return false }
        if privs.isSuperuser { return false }
        if privs.canCreateSchemaInDb { return false }
        return !privs.schemaPrivileges.values.contains { $0.canCreate }
    }
}
