import SwiftUI

/// Visual, dropdown-based multi-condition filter bar for PostgreSQL tables.
/// Eliminates raw SQL WHERE typing in favor of structured column/operator dropdowns and multiple inputs.
struct QuickFilterBarView: View {
    @Environment(DataGridViewModel.self) private var dataGridViewModel
    @Environment(ExportViewModel.self) private var exportViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    let availableColumns: [String]
    let onApply: () -> Void

    private var paginationText: String {
        guard dataGridViewModel.totalRows > 0 else { return "0 rows" }
        let startRow: Int64 = Int64(dataGridViewModel.currentPage * dataGridViewModel.pageSize + 1)
        let endRow: Int64 = min(startRow + Int64(dataGridViewModel.pageSize) - 1, dataGridViewModel.totalRows)
        return "\(startRow) – \(endRow) of \(dataGridViewModel.totalRows) rows"
    }

    var body: some View {
        @Bindable var dataVM = dataGridViewModel

        VStack(spacing: 8) {
            // Main Top Bar
            HStack(spacing: 8) {
                // Filter Icon & Label
                HStack(spacing: 5) {
                    Image(systemName: dataVM.filterRules.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(dataVM.filterRules.isEmpty ? .secondary : PostgraceTheme.accentSky)

                    Text("FILTER")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(dataVM.filterRules.isEmpty ? .secondary : .primary)
                }

                if dataVM.filterRules.isEmpty {
                    // Quick "+ Add Filter" trigger when no filters exist
                    Button {
                        let defaultCol = availableColumns.first ?? dataVM.availableColumns.first ?? ""
                        dataVM.addFilterRule(defaultColumn: defaultCol)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                            Text("Add Filter")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(PostgraceTheme.accentSky)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(PostgraceTheme.accentSkyMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(PostgraceTheme.accentSky.opacity(0.3), lineWidth: PostgraceTheme.hairlineBorder)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Add a structured filter condition")
                } else {
                    // Conjunction Picker: Match ALL (AND) vs Match ANY (OR) via clean segmented picker
                    if dataVM.filterRules.count > 1 {
                        Picker("", selection: Binding(
                            get: { dataVM.filterConjunction },
                            set: {
                                dataVM.filterConjunction = $0
                                onApply()
                            }
                        )) {
                            Text("AND").tag(FilterConjunction.and)
                            Text("OR").tag(FilterConjunction.or)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 84)
                        .help("Match ALL conditions (AND) or ANY condition (OR)")
                    }

                    if !dataVM.filterClause.isEmpty {
                        Text("\(dataVM.filterRules.count) active")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(PostgraceTheme.emeraldRw)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(PostgraceTheme.emeraldRwMuted)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                // Export Table / Filtered Rows Button
                Menu {
                    Button("Export Table Data…") {
                        if let tbl = schemaViewModel.selectedTable {
                            exportViewModel.startTableExport(
                                schema: tbl.schema,
                                table: tbl.name,
                                filterClause: ""
                            )
                        }
                    }

                    if !dataVM.filterClause.isEmpty {
                        Button("Export Filtered Rows (\(dataVM.filterRules.count) conditions)…") {
                            if let tbl = schemaViewModel.selectedTable {
                                exportViewModel.startTableExport(
                                    schema: tbl.schema,
                                    table: tbl.name,
                                    filterClause: dataVM.filterClause
                                )
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 9))
                        Text("Export")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .menuStyle(.borderlessButton)
                .help("Export table data to CSV, JSON, or SQL")

                // Pagination Controls
                if dataVM.totalRows > 0 {
                    Text(paginationText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)

                    HStack(spacing: 2) {
                        Button {
                            Task { await dataVM.previousPage() }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(dataVM.hasPreviousPage ? .primary : .secondary.opacity(0.4))
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .disabled(!dataVM.hasPreviousPage)

                        Button {
                            Task { await dataVM.nextPage() }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(dataVM.hasNextPage ? .primary : .secondary.opacity(0.4))
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .disabled(!dataVM.hasNextPage)
                    }
                }
            }

            // Expanded Multiple Filter Rules List
            if !dataVM.filterRules.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(dataVM.filterRules.enumerated()), id: \.element.id) { index, rule in
                        filterRuleRow(index: index, rule: rule)
                    }

                    // Bottom Filter Actions Bar
                    HStack(spacing: 8) {
                        // "+ Add Condition" button
                        Button {
                            let defaultCol = availableColumns.first ?? dataVM.availableColumns.first ?? ""
                            dataVM.addFilterRule(defaultColumn: defaultCol)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 8, weight: .bold))
                            Text("Add Condition")
                                .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(PostgraceTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Add another filter condition")

                        // "Apply Filter" Button
                        Button {
                            onApply()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Apply")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3.5)
                            .background(PostgraceTheme.accentSky)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [.command])
                        .help("Apply filter (⌘↵)")

                        // "Clear All" Button
                        Button {
                            Task {
                                await dataVM.clearFilters()
                            }
                        } label: {
                            Text("Clear")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3.5)
                        }
                        .buttonStyle(.plain)
                        .help("Reset all filters")

                        Spacer()

                        // SQL WHERE Preview
                        let sql = dataVM.buildFilterClause()
                        if !sql.isEmpty {
                            Text("WHERE \(sql)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.top, 2)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PostgraceTheme.surface)
        .overlay(
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder),
            alignment: .bottom
        )
    }

    // MARK: - Filter Rule Row

    @ViewBuilder
    private func filterRuleRow(index: Int, rule: FilterRule) -> some View {
        let cols = availableColumns.isEmpty ? dataGridViewModel.availableColumns : availableColumns

        HStack(spacing: 6) {
            // WHERE / AND / OR Prefix badge
            Text(index == 0 ? "WHERE" : dataGridViewModel.filterConjunction.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(index == 0 ? PostgraceTheme.accentSky : PostgraceTheme.amberRo)
                .frame(width: 46, alignment: .trailing)

            // 1. Column Selection Dropdown
            Menu {
                ForEach(cols, id: \.self) { colName in
                    Button {
                        if let ruleIndex = dataGridViewModel.filterRules.firstIndex(where: { $0.id == rule.id }) {
                            dataGridViewModel.filterRules[ruleIndex].column = colName
                        }
                    } label: {
                        HStack {
                            Text(colName)
                            if rule.column == colName {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(rule.column.isEmpty ? "Select column…" : rule.column)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(rule.column.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minWidth: 100, alignment: .leading)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
            }
            .menuStyle(.borderlessButton)
            .help("Click to select column")

            // 2. Comparison Operator Dropdown
            Menu {
                ForEach(FilterOperator.allCases) { op in
                    Button {
                        if let ruleIndex = dataGridViewModel.filterRules.firstIndex(where: { $0.id == rule.id }) {
                            dataGridViewModel.filterRules[ruleIndex].op = op
                        }
                    } label: {
                        HStack {
                            Text(op.label)
                            if rule.op == op {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(rule.op.label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(PostgraceTheme.accentSky)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minWidth: 36, alignment: .center)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
            }
            .menuStyle(.borderlessButton)
            .help("Click to change operator")

            // 3. Value Input Field (or hidden if IS NULL / IS NOT NULL)
            if rule.op.requiresValue {
                HStack(spacing: 4) {
                    TextField("Value…", text: Binding(
                        get: { rule.value },
                        set: { newVal in
                            if let ruleIndex = dataGridViewModel.filterRules.firstIndex(where: { $0.id == rule.id }) {
                                dataGridViewModel.filterRules[ruleIndex].value = newVal
                            }
                        }
                    ))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .onSubmit {
                        onApply()
                    }

                    if !rule.value.isEmpty {
                        Button {
                            if let ruleIndex = dataGridViewModel.filterRules.firstIndex(where: { $0.id == rule.id }) {
                                dataGridViewModel.filterRules[ruleIndex].value = ""
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .frame(minWidth: 140, maxWidth: 260)
                .background(PostgraceTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )
            } else {
                Text("(no value required)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                    .italic()
                    .padding(.horizontal, 6)
            }

            // 4. Remove Rule Button
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    dataGridViewModel.removeFilterRule(id: rule.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(5)
            }
            .buttonStyle(.plain)
            .help("Remove this condition")

            Spacer(minLength: 0)
        }
    }
}
