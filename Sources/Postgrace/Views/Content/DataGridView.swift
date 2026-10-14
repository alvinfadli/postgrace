import SwiftUI
import AppKit

/// High-performance full-bleed data grid matching the artifact design.
/// Starts pinned at top-left, fills the entire available section, and supports interactive column width resizing.
struct DataGridView: View {
    let queryResult: QueryResult

    @Environment(DataGridViewModel.self) private var dataGridViewModel

    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var sortColumn: String? = nil
    @State private var sortAscending: Bool = true
    @State private var sortedRows: [[CellValue]] = []

    // Column filtering & visibility state
    @State private var activeFilterColumn: String? = nil
    @State private var hoveredColumnHeader: String? = nil
    @State private var showingColumnVisibilityPopover: Bool = false
    @State private var localHiddenColumns: Set<String> = []
    @State private var localColumnFilters: [String: (FilterOperator, String)] = [:]

    // Cell selection & copy feedback state
    @State private var selectedCell: SelectedGridCell? = nil
    @State private var copiedToastMessage: String? = nil
    @State private var toastDismissTask: Task<Void, Never>? = nil

    private var isTableContext: Bool {
        dataGridViewModel.currentTable != nil
    }

    private var currentHiddenColumns: Set<String> {
        isTableContext ? dataGridViewModel.hiddenColumns : localHiddenColumns
    }

    private var hasHiddenColumns: Bool {
        !currentHiddenColumns.isEmpty
    }

    private var visibleColumnIndices: [(column: ResultColumn, index: Int)] {
        let hidden = currentHiddenColumns
        return queryResult.columns.enumerated().compactMap { index, col in
            hidden.contains(col.name) ? nil : (column: col, index: index)
        }
    }

    var visibleColumns: [ResultColumn] {
        visibleColumnIndices.map(\.column)
    }

    private func toggleColumnVisibility(_ columnName: String) {
        if isTableContext {
            dataGridViewModel.toggleColumnVisibility(columnName)
        } else {
            if localHiddenColumns.contains(columnName) {
                localHiddenColumns.remove(columnName)
            } else {
                localHiddenColumns.insert(columnName)
            }
        }
    }

    private func showAllColumns() {
        if isTableContext {
            dataGridViewModel.showAllColumns()
        } else {
            localHiddenColumns.removeAll()
        }
    }

    private func hideAllColumns() {
        if isTableContext {
            dataGridViewModel.hideAllColumns()
        } else {
            let keep = queryResult.columns.first?.name ?? ""
            localHiddenColumns = Set(queryResult.columns.map(\.name).filter { $0 != keep })
        }
    }

    private func isColumnFiltered(_ columnName: String) -> Bool {
        if isTableContext {
            return dataGridViewModel.hasFilter(for: columnName)
        }
        return localColumnFilters[columnName] != nil
    }

    private func currentFilterRule(for columnName: String) -> FilterRule? {
        if isTableContext {
            return dataGridViewModel.filterRule(for: columnName)
        }
        if let local = localColumnFilters[columnName] {
            return FilterRule(column: columnName, op: local.0, value: local.1)
        }
        return nil
    }

    private func applyColumnFilter(column: String, op: FilterOperator, value: String) {
        if isTableContext {
            Task {
                await dataGridViewModel.setFilter(column: column, op: op, value: value)
            }
        } else {
            localColumnFilters[column] = (op, value)
            updateSortedRows()
        }
    }

    private func clearColumnFilter(column: String) {
        if isTableContext {
            Task {
                await dataGridViewModel.removeFilter(for: column)
            }
        } else {
            localColumnFilters.removeValue(forKey: column)
            updateSortedRows()
        }
    }

    private func updateSortedRows() {
        var baseRows = queryResult.rows

        // Apply local filtering when not in table browse context
        if !isTableContext && !localColumnFilters.isEmpty {
            baseRows = baseRows.filter { row in
                for (colName, filter) in localColumnFilters {
                    guard let colIndex = queryResult.columns.firstIndex(where: { $0.name == colName }),
                          colIndex < row.count else { continue }
                    let cellValue = row[colIndex]
                    if !matchesLocalFilter(cellValue: cellValue, op: filter.0, target: filter.1) {
                        return false
                    }
                }
                return true
            }
        }

        guard let sortCol = sortColumn,
              let colIndex = queryResult.columns.firstIndex(where: { $0.name == sortCol }) else {
            sortedRows = baseRows
            return
        }
        sortedRows = baseRows.sorted { row1, row2 in
            let val1 = colIndex < row1.count ? row1[colIndex] : .null
            let val2 = colIndex < row2.count ? row2[colIndex] : .null
            let isLess = compareCells(val1, val2)
            return sortAscending ? isLess : !isLess
        }
    }

    private func matchesLocalFilter(cellValue: CellValue, op: FilterOperator, target: String) -> Bool {
        let str = cellValue.displayString
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)

        switch op {
        case .isNull:
            return cellValue == .null
        case .isNotNull:
            return cellValue != .null
        case .equals:
            return str.localizedCaseInsensitiveCompare(trimmedTarget) == .orderedSame
        case .notEquals:
            return str.localizedCaseInsensitiveCompare(trimmedTarget) != .orderedSame
        case .contains:
            return str.localizedCaseInsensitiveContains(trimmedTarget)
        case .startsWith:
            return str.range(of: trimmedTarget, options: [.anchored, .caseInsensitive]) != nil
        case .endsWith:
            return str.range(of: trimmedTarget, options: [.backwards, .anchored, .caseInsensitive]) != nil
        case .greaterThan:
            if let numCell = Double(str), let numTarget = Double(trimmedTarget) {
                return numCell > numTarget
            }
            return str.localizedStandardCompare(trimmedTarget) == .orderedDescending
        case .lessThan:
            if let numCell = Double(str), let numTarget = Double(trimmedTarget) {
                return numCell < numTarget
            }
            return str.localizedStandardCompare(trimmedTarget) == .orderedAscending
        case .greaterThanOrEqual:
            if let numCell = Double(str), let numTarget = Double(trimmedTarget) {
                return numCell >= numTarget
            }
            let comp = str.localizedStandardCompare(trimmedTarget)
            return comp == .orderedDescending || comp == .orderedSame
        case .lessThanOrEqual:
            if let numCell = Double(str), let numTarget = Double(trimmedTarget) {
                return numCell <= numTarget
            }
            let comp = str.localizedStandardCompare(trimmedTarget)
            return comp == .orderedAscending || comp == .orderedSame
        }
    }

    private func compareCells(_ a: CellValue, _ b: CellValue) -> Bool {
        switch (a, b) {
        case (.null, .null): return false
        case (.null, _): return false
        case (_, .null): return true
        case (.int(let x), .int(let y)): return x < y
        case (.double(let x), .double(let y)): return x < y
        case (.int(let x), .double(let y)): return Double(x) < y
        case (.double(let x), .int(let y)): return x < Double(y)
        case (.bool(let x), .bool(let y)): return !x && y
        case (.date(let x), .date(let y)): return x < y
        case (.string(let x), .string(let y)): return x.localizedStandardCompare(y) == .orderedAscending
        default:
            return a.displayString.localizedStandardCompare(b.displayString) == .orderedAscending
        }
    }

    var body: some View {
        if queryResult.columns.isEmpty && queryResult.rows.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                resultGrid
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .bottom) {
                if let toast = copiedToastMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(PostgraceTheme.emeraldRw)
                            .font(.system(size: 11, weight: .bold))
                        Text(toast)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(PostgraceTheme.borderSubtle, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.18), radius: 6, y: 2)
                    .padding(.bottom, 36)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .background {
                // Invisible button for ⌘C keyboard shortcut
                Button("") {
                    copySelectedCellOrRow()
                }
                .keyboardShortcut("c", modifiers: [.command])
                .opacity(0)
                .frame(width: 0, height: 0)
            }
        }
    }

    // MARK: - Column Width Calculation & Auto-Fit

    private func widthForColumn(at index: Int, column: ResultColumn) -> CGFloat {
        if let userWidth = columnWidths[column.name] {
            return userWidth
        }
        return defaultWidth(for: column)
    }

    private func defaultWidth(for column: ResultColumn) -> CGFloat {
        let nameLength = column.name.count
        let typeLength = column.dataTypeName.count
        let charCount = max(nameLength, typeLength)
        let estimated = CGFloat(charCount * 9 + 48)
        return max(110, min(320, estimated))
    }

    /// Calculates the optimal auto-adjusted width for a column to fully display its header and cell contents.
    public static func calculateFittedWidth(
        for column: ResultColumn,
        in rows: [[CellValue]],
        columns: [ResultColumn],
        sampleLimit: Int = 300
    ) -> CGFloat {
        guard let dataIndex = columns.firstIndex(where: { $0.name == column.name }) else {
            return 110
        }

        // 1. Measure Header Width
        let nameFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let nameWidth = (column.name as NSString).size(withAttributes: [.font: nameFont]).width
        let typeFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        let typeWidth = (!column.dataTypeName.isEmpty && column.dataTypeName != "unknown")
            ? (column.dataTypeName.lowercased() as NSString).size(withAttributes: [.font: typeFont]).width + 8
            : 0
        // Name + type badge + sort icon space (~16px) + filter icon (~20px) + margins (~24px)
        var maxRequiredWidth: CGFloat = nameWidth + typeWidth + 56

        // 2. Measure Cell Contents Across Rows
        let cellFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let count = min(rows.count, sampleLimit)

        for i in 0..<count {
            let row = rows[i]
            if dataIndex < row.count {
                let cell = row[dataIndex]
                let text = cell.displayString
                if !text.isEmpty {
                    // Cell text width + 16px horizontal padding + 8px margin
                    let textWidth = (text as NSString).size(withAttributes: [.font: cellFont]).width + 24
                    if textWidth > maxRequiredWidth {
                        maxRequiredWidth = textWidth
                    }
                }
            }
        }

        // Clamp to sensible min/max constraints (min 90, max 700)
        return max(90, min(700, ceil(maxRequiredWidth)))
    }

    private func autoFitColumnWidth(column: ResultColumn) {
        let fittedWidth = DataGridView.calculateFittedWidth(
            for: column,
            in: sortedRows,
            columns: queryResult.columns
        )
        withAnimation(.easeInOut(duration: 0.15)) {
            columnWidths[column.name] = fittedWidth
        }
    }

    private func autoFitAllColumns() {
        withAnimation(.easeInOut(duration: 0.15)) {
            for col in queryResult.columns {
                let fitted = DataGridView.calculateFittedWidth(
                    for: col,
                    in: sortedRows,
                    columns: queryResult.columns
                )
                columnWidths[col.name] = fitted
            }
        }
    }

    private var visibleGridColumns: [VisibleGridColumn] {
        visibleColumnIndices.map { item in
            VisibleGridColumn(
                column: item.column,
                index: item.index,
                width: columnWidths[item.column.name] ?? defaultWidth(for: item.column)
            )
        }
    }

    // MARK: - Result Grid

    private var resultGrid: some View {
        let gridColumns = visibleGridColumns
        return GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(0..<sortedRows.count, id: \.self) { rowIndex in
                                DataGridRowView(
                                    rowIndex: rowIndex,
                                    row: sortedRows[rowIndex],
                                    visibleColumns: gridColumns,
                                    availableWidth: proxy.size.width,
                                    selectedColumn: selectedCell?.rowIndex == rowIndex ? selectedCell?.columnName : nil,
                                    onSelectCell: { cell in
                                        selectedCell = cell
                                    },
                                    onCopyCell: { copyCellToClipboard($0) },
                                    onCopyColumn: {
                                        copyToPasteboard($0)
                                        showCopiedToast("Column \($0)")
                                    },
                                    onCopyRowCSV: {
                                        copyRowAsCSV($0)
                                        showCopiedToast("Row CSV")
                                    },
                                    onCopyRowJSON: {
                                        copyRowAsJSON($0)
                                        showCopiedToast("Row JSON")
                                    },
                                    onFilterCell: { col, op, val in
                                        applyColumnFilter(column: col, op: op, value: val)
                                    }
                                )
                                .equatable()
                            }
                        } header: {
                            headerRow(availableWidth: proxy.size.width)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(PostgraceTheme.canvas)
        }
        .onAppear {
            updateSortedRows()
        }
        .onChange(of: sortColumn) { _, _ in
            updateSortedRows()
        }
        .onChange(of: sortAscending) { _, _ in
            updateSortedRows()
        }
        .onChange(of: queryResult.rows.count) { _, _ in
            updateSortedRows()
        }
    }

    // MARK: - Header Row

    @ViewBuilder
    private func headerRow(availableWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Row number gutter header
            Text("#")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.vertical, 6)
                .overlay(
                    Rectangle()
                        .frame(width: PostgraceTheme.hairlineBorder)
                        .foregroundColor(PostgraceTheme.border),
                    alignment: .trailing
                )

            // Resizable visible column headers
            ForEach(Array(visibleColumns.enumerated()), id: \.element.name) { colIndex, column in
                let width = widthForColumn(at: colIndex, column: column)
                headerCell(column: column, colIndex: colIndex, width: width)
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: availableWidth, alignment: .leading)
        .background(PostgraceTheme.surface)
        .overlay(
            Rectangle()
                .frame(height: PostgraceTheme.hairlineBorder)
                .foregroundColor(PostgraceTheme.border),
            alignment: .bottom
        )
    }

    // MARK: - Header Cell with Resize Handle, Sort, and Column Filter

    @ViewBuilder
    private func headerCell(column: ResultColumn, colIndex: Int, width: CGFloat) -> some View {
        let isFiltered = isColumnFiltered(column.name)

        HStack(spacing: 0) {
            // Sort Button
            Button {
                if sortColumn == column.name {
                    if sortAscending {
                        sortAscending = false
                    } else {
                        sortColumn = nil
                        sortAscending = true
                    }
                } else {
                    sortColumn = column.name
                    sortAscending = true
                }
            } label: {
                HStack(spacing: 4) {
                    Text(column.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(sortColumn == column.name ? PostgraceTheme.accentSky : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if sortColumn == column.name {
                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(PostgraceTheme.accentSky)
                    }

                    if !column.dataTypeName.isEmpty && column.dataTypeName != "unknown" {
                        Text(column.dataTypeName.lowercased())
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 2)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to sort by \(column.name)")

            Spacer(minLength: 0)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    autoFitColumnWidth(column: column)
                }

            // Column Filter Button with Interactive Popover
            Button {
                activeFilterColumn = (activeFilterColumn == column.name) ? nil : column.name
            } label: {
                Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                    .font(.system(size: 9, weight: isFiltered ? .bold : .medium))
                    .foregroundColor(isFiltered ? PostgraceTheme.accentSky : .secondary.opacity(hoveredColumnHeader == column.name ? 0.9 : 0.45))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isFiltered ? "Column '\(column.name)' has active filter" : "Filter column '\(column.name)'")
            .popover(
                isPresented: Binding(
                    get: { activeFilterColumn == column.name },
                    set: { if !$0 { activeFilterColumn = nil } }
                ),
                arrowEdge: .bottom
            ) {
                ColumnFilterPopoverView(
                    columnName: column.name,
                    dataTypeName: column.dataTypeName,
                    currentRule: currentFilterRule(for: column.name),
                    onApply: { op, val in
                        applyColumnFilter(column: column.name, op: op, value: val)
                        activeFilterColumn = nil
                    },
                    onClear: {
                        clearColumnFilter(column: column.name)
                        activeFilterColumn = nil
                    }
                )
            }

            // High-performance AppKit column resizer handle
            ColumnResizeHandle(
                currentWidth: width,
                onResize: { newWidth in
                    columnWidths[column.name] = newWidth
                },
                onDoubleClick: {
                    autoFitColumnWidth(column: column)
                }
            )
            .frame(width: 10, height: 32)
            .help("Drag to resize. Double-click to auto-adjust width.")
        }
        .frame(width: width, alignment: .leading)
        .onHover { hovering in
            if hovering {
                hoveredColumnHeader = column.name
            } else if hoveredColumnHeader == column.name {
                hoveredColumnHeader = nil
            }
        }
        .contextMenu {
            Button {
                autoFitColumnWidth(column: column)
            } label: {
                Label("Auto-Fit Column Width", systemImage: "arrow.left.and.right")
            }

            Button {
                autoFitAllColumns()
            } label: {
                Label("Auto-Fit All Columns", systemImage: "tablecells.badge.ellipsis")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    columnWidths[column.name] = defaultWidth(for: column)
                }
            } label: {
                Label("Reset to Default Width", systemImage: "arrow.counterclockwise")
            }

            Divider()

            Button {
                activeFilterColumn = column.name
            } label: {
                Label("Filter by '\(column.name)'…", systemImage: "line.3.horizontal.decrease")
            }

            if isFiltered {
                Button {
                    clearColumnFilter(column: column.name)
                } label: {
                    Label("Clear Filter on '\(column.name)'", systemImage: "xmark.circle")
                }
            }

            Divider()

            Button {
                sortColumn = column.name
                sortAscending = true
            } label: {
                Label("Sort Ascending", systemImage: "arrow.up")
            }

            Button {
                sortColumn = column.name
                sortAscending = false
            } label: {
                Label("Sort Descending", systemImage: "arrow.down")
            }

            if sortColumn == column.name {
                Button {
                    sortColumn = nil
                } label: {
                    Label("Clear Sort", systemImage: "arrow.up.arrow.down")
                }
            }

            Divider()

            Button {
                toggleColumnVisibility(column.name)
            } label: {
                Label("Hide Column '\(column.name)'", systemImage: "eye.slash")
            }

            if hasHiddenColumns {
                Button {
                    showAllColumns()
                } label: {
                    Label("Show All Columns", systemImage: "eye")
                }
            }
        }
    }

    // MARK: - Footer with Columns Visibility & Export Actions

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(sortedRows.count) rows")
                .font(.system(size: 11, design: .monospaced))
            Text("•")
                .foregroundColor(PostgraceTheme.border)

            // Column Visibility Button & Popover
            Button {
                showingColumnVisibilityPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 9))
                    Text(hasHiddenColumns ? "\(visibleColumns.count) of \(queryResult.columns.count) columns" : "\(queryResult.columns.count) columns")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(hasHiddenColumns ? PostgraceTheme.accentSky : .secondary)
            }
            .buttonStyle(.plain)
            .help("Configure column visibility in table view")
            .popover(isPresented: $showingColumnVisibilityPopover, arrowEdge: .top) {
                ColumnVisibilityPopoverView(
                    allColumns: queryResult.columns,
                    hiddenColumns: currentHiddenColumns,
                    onToggleColumn: { toggleColumnVisibility($0) },
                    onShowAll: { showAllColumns() },
                    onHideAll: { hideAllColumns() }
                )
            }

            Text("•")
                .foregroundColor(PostgraceTheme.border)

            // Auto-fit all columns button
            Button {
                autoFitAllColumns()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.and.right")
                        .font(.system(size: 9))
                    Text("Auto-fit")
                        .font(.system(size: 11, design: .monospaced))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Auto-adjust all column widths to fit cell contents (or double-click column divider)")

            if queryResult.executionTime > 0 {
                Text("•")
                    .foregroundColor(PostgraceTheme.border)
                Text(String(format: "%.3f s", queryResult.executionTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PostgraceTheme.emeraldRw)
            }

            if let sel = selectedCell, sel.rowIndex < sortedRows.count {
                let row = sortedRows[sel.rowIndex]
                if let colIdx = queryResult.columns.firstIndex(where: { $0.name == sel.columnName }),
                   colIdx < row.count {
                    let val = row[colIdx].displayString
                    Text("•")
                        .foregroundColor(PostgraceTheme.border)
                    HStack(spacing: 4) {
                        Text("Selected:")
                            .foregroundColor(.secondary)
                        Text("\(sel.columnName) = \"\(val.count > 25 ? String(val.prefix(25)) + "…" : val)\"")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)

                        Button {
                            copyCellToClipboard(val)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10))
                                .foregroundColor(PostgraceTheme.accentSky)
                        }
                        .buttonStyle(.plain)
                        .help("Copy selected cell value (⌘C)")
                    }
                }
            }

            Spacer()

            Menu {
                Button("Copy All as CSV") {
                    copyAsCSV()
                }
                Button("Copy All as JSON") {
                    copyAsJSON()
                }
                Divider()
                Button("Export to CSV...") {
                    exportToCSVFile()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 10))
                    Text("Export")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(PostgraceTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(PostgraceTheme.surface)
        .overlay(
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder),
            alignment: .top
        )
    }

    // MARK: - Export & Clipboard Helpers

    private func copySelectedCellOrRow() {
        if let sel = selectedCell, sel.rowIndex < sortedRows.count {
            let row = sortedRows[sel.rowIndex]
            if let colIdx = queryResult.columns.firstIndex(where: { $0.name == sel.columnName }),
               colIdx < row.count {
                let text = row[colIdx].displayString
                copyCellToClipboard(text)
                return
            }
        }
        copyAsCSV()
    }

    private func copyCellToClipboard(_ text: String, notify: Bool = true) {
        copyToPasteboard(text)
        if notify {
            showCopiedToast(text.isEmpty ? "(empty)" : text)
        }
    }

    private func showCopiedToast(_ content: String) {
        toastDismissTask?.cancel()
        let preview = content.count > 25 ? String(content.prefix(25)) + "…" : content
        withAnimation(.easeOut(duration: 0.15)) {
            copiedToastMessage = "Copied \"\(preview)\""
        }
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        copiedToastMessage = nil
                    }
                }
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyRowAsCSV(_ row: [CellValue]) {
        let cols = visibleColumns.isEmpty ? queryResult.columns : visibleColumns
        let line = cols.map { col -> String in
            guard let idx = queryResult.columns.firstIndex(where: { $0.name == col.name }),
                  idx < row.count else { return "" }
            return formatCSVCell(row[idx].displayString)
        }.joined(separator: ",")
        copyToPasteboard(line)
    }

    private func copyRowAsJSON(_ row: [CellValue]) {
        let cols = visibleColumns.isEmpty ? queryResult.columns : visibleColumns
        var dict: [String: Any] = [:]
        for col in cols {
            guard let idx = queryResult.columns.firstIndex(where: { $0.name == col.name }),
                  idx < row.count else { continue }
            let cell = row[idx]
            switch cell {
            case .null: dict[col.name] = NSNull()
            case .int(let v): dict[col.name] = v
            case .double(let v): dict[col.name] = v
            case .bool(let v): dict[col.name] = v
            default: dict[col.name] = cell.displayString
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            copyToPasteboard(str)
        }
    }

    private func copyAsCSV() {
        let csv = generateCSVString()
        copyToPasteboard(csv)
    }

    private func copyAsJSON() {
        let cols = visibleColumns.isEmpty ? queryResult.columns : visibleColumns
        var rowsArray: [[String: Any]] = []
        for row in sortedRows {
            var dict: [String: Any] = [:]
            for col in cols {
                guard let idx = queryResult.columns.firstIndex(where: { $0.name == col.name }),
                      idx < row.count else { continue }
                let cell = row[idx]
                switch cell {
                case .null: dict[col.name] = NSNull()
                case .int(let v): dict[col.name] = v
                case .double(let v): dict[col.name] = v
                case .bool(let v): dict[col.name] = v
                default: dict[col.name] = cell.displayString
                }
            }
            rowsArray.append(dict)
        }
        if let data = try? JSONSerialization.data(withJSONObject: rowsArray, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            copyToPasteboard(str)
        }
    }

    private func generateCSVString() -> String {
        let cols = visibleColumns.isEmpty ? queryResult.columns : visibleColumns
        var lines: [String] = []
        lines.append(cols.map { formatCSVCell($0.name) }.joined(separator: ","))
        for row in sortedRows {
            let rowCells = cols.map { col -> String in
                guard let idx = queryResult.columns.firstIndex(where: { $0.name == col.name }),
                      idx < row.count else { return "" }
                return formatCSVCell(row[idx].displayString)
            }
            lines.append(rowCells.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func formatCSVCell(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return text
    }

    private func exportToCSVFile() {
        let panel = NSSavePanel()
        panel.title = "Export Query Results to CSV"
        panel.nameFieldStringValue = "query_results.csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                let csv = generateCSVString()
                try? csv.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tablecells")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No Data Available")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PostgraceTheme.canvas)
    }
}

// MARK: - Dedicated High-Performance Data Grid Row View

/// Represents a selected cell in the data grid.
struct SelectedGridCell: Equatable, Sendable {
    let rowIndex: Int
    let columnName: String
}

/// Precomputed visible column metadata and width for fast row rendering and Equatable diffing.
struct VisibleGridColumn: Equatable, Identifiable, Sendable {
    var id: String { column.name }
    let column: ResultColumn
    let index: Int
    let width: CGFloat
}

struct DataGridRowView: View, Equatable {
    let rowIndex: Int
    let row: [CellValue]
    let visibleColumns: [VisibleGridColumn]
    let availableWidth: CGFloat
    let selectedColumn: String?
    let onSelectCell: (SelectedGridCell) -> Void
    let onCopyCell: (String) -> Void
    let onCopyColumn: (String) -> Void
    let onCopyRowCSV: ([CellValue]) -> Void
    let onCopyRowJSON: ([CellValue]) -> Void
    let onFilterCell: (String, FilterOperator, String) -> Void

    @State private var isHovered: Bool = false

    static func == (lhs: DataGridRowView, rhs: DataGridRowView) -> Bool {
        lhs.rowIndex == rhs.rowIndex &&
        lhs.selectedColumn == rhs.selectedColumn &&
        lhs.availableWidth == rhs.availableWidth &&
        lhs.visibleColumns == rhs.visibleColumns &&
        lhs.row == rhs.row
    }

    var body: some View {
        let zebraBg = rowIndex % 2 == 0 ? PostgraceTheme.canvas : PostgraceTheme.surface.opacity(0.35)

        HStack(spacing: 0) {
            // Row number gutter
            Text("\(rowIndex + 1)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.8))
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .background(PostgraceTheme.surface.opacity(0.2))
                .overlay(
                    Rectangle()
                        .frame(width: PostgraceTheme.hairlineBorder)
                        .foregroundColor(PostgraceTheme.borderSubtle),
                    alignment: .trailing
                )

            // Cell values for visible columns
            ForEach(visibleColumns) { item in
                let column = item.column
                let colIndex = item.index
                let cellValue = colIndex < row.count ? row[colIndex] : .null
                let isSelected = selectedColumn == column.name

                cellView(for: cellValue, column: column, width: item.width, isSelected: isSelected)
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: availableWidth, alignment: .leading)
        .background(isHovered ? PostgraceTheme.surfaceHover : zebraBg)
        .overlay(
            Rectangle()
                .frame(height: PostgraceTheme.hairlineBorder)
                .foregroundColor(PostgraceTheme.borderSubtle.opacity(0.3))
                .allowsHitTesting(false),
            alignment: .bottom
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button("Copy Row as CSV") {
                onCopyRowCSV(row)
            }
            Button("Copy Row as JSON") {
                onCopyRowJSON(row)
            }
        }
    }

    @ViewBuilder
    private func cellView(for cellValue: CellValue, column: ResultColumn, width: CGFloat, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            cellContent(for: cellValue)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(
            isSelected ? PostgraceTheme.accentSky.opacity(0.12) : Color.clear
        )
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(isSelected ? PostgraceTheme.accentSky : Color.clear, lineWidth: 1.5)
                .allowsHitTesting(false)
        )
        .overlay(
            Rectangle()
                .frame(width: PostgraceTheme.hairlineBorder)
                .foregroundColor(PostgraceTheme.borderSubtle.opacity(0.4))
                .allowsHitTesting(false),
            alignment: .trailing
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelectCell(SelectedGridCell(rowIndex: rowIndex, columnName: column.name))
        }
        .contextMenu {
            // Prominent Copy Cell Value at the top
            Button {
                onSelectCell(SelectedGridCell(rowIndex: rowIndex, columnName: column.name))
                onCopyCell(cellValue.displayString)
            } label: {
                Label("Copy Cell Value", systemImage: "doc.on.doc")
            }

            Button {
                onCopyColumn(column.name)
            } label: {
                Label("Copy Column Name (\(column.name))", systemImage: "text.quote")
            }

            Divider()

            // Quick Filter Actions
            Button {
                onFilterCell(column.name, .equals, cellValue.displayString)
            } label: {
                Label("Filter: \(column.name) = '\(cellValue.displayString)'", systemImage: "line.3.horizontal.decrease")
            }

            Button {
                onFilterCell(column.name, .notEquals, cellValue.displayString)
            } label: {
                Label("Filter: \(column.name) ≠ '\(cellValue.displayString)'", systemImage: "line.3.horizontal.decrease")
            }

            if !cellValue.displayString.isEmpty && cellValue != .null {
                Button {
                    onFilterCell(column.name, .contains, cellValue.displayString)
                } label: {
                    Label("Filter: \(column.name) contains '\(cellValue.displayString)'", systemImage: "text.magnifyingglass")
                }
            }

            if cellValue == .null {
                Button {
                    onFilterCell(column.name, .isNull, "")
                } label: {
                    Label("Filter: \(column.name) IS NULL", systemImage: "line.3.horizontal.decrease")
                }
            } else {
                Button {
                    onFilterCell(column.name, .isNotNull, "")
                } label: {
                    Label("Filter: \(column.name) IS NOT NULL", systemImage: "line.3.horizontal.decrease")
                }
            }

            Divider()

            Button("Copy Row as CSV") {
                onCopyRowCSV(row)
            }
            Button("Copy Row as JSON") {
                onCopyRowJSON(row)
            }
        }
    }

    @ViewBuilder
    private func cellContent(for cellValue: CellValue) -> some View {
        switch cellValue {
        case .null:
            Text("NULL")
                .font(.system(size: 11, design: .monospaced))
                .italic()
                .foregroundColor(.secondary.opacity(0.6))
        case .bool(let b):
            Text(b ? "true" : "false")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(b ? PostgraceTheme.emeraldRw : PostgraceTheme.destructiveRed)
        default:
            Text(cellValue.displayString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
    }
}

// MARK: - AppKit Column Resize Handle

/// High-performance AppKit-backed column resize handle.
/// Prevents SwiftUI gesture fighting, local coordinate jitter, and window movement during resizing.
struct ColumnResizeHandle: NSViewRepresentable {
    let currentWidth: CGFloat
    let onResize: (CGFloat) -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ColumnResizeHandleNSView {
        let view = ColumnResizeHandleNSView()
        view.currentWidth = currentWidth
        view.onResize = onResize
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: ColumnResizeHandleNSView, context: Context) {
        nsView.currentWidth = currentWidth
        nsView.onResize = onResize
        nsView.onDoubleClick = onDoubleClick
    }
}

final class ColumnResizeHandleNSView: NSView {
    var currentWidth: CGFloat = 0
    var onResize: ((CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?

    private var startLocationX: CGFloat = 0
    private var initialWidth: CGFloat = 0
    private var isDragging: Bool = false
    private var isHovered: Bool = false
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            if isDragging {
                isDragging = false
                NSCursor.pop()
            }
            onDoubleClick?()
            return
        }

        isDragging = true
        startLocationX = event.locationInWindow.x
        initialWidth = currentWidth
        NSCursor.resizeLeftRight.push()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let deltaX = event.locationInWindow.x - startLocationX
        if abs(deltaX) < 2 { return }
        let newWidth = max(50, initialWidth + deltaX)
        onResize?(newWidth)
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            NSCursor.pop()
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let isDark = effectiveAppearance.isDark
        let strokeColor = (isDragging || isHovered)
            ? (isDark ? NSColor(hex: "#3B82F6") : NSColor(hex: "#2563EB"))
            : (isDark ? NSColor(hex: "#2B2F38") : NSColor(hex: "#E2E8F0"))

        strokeColor.setFill()
        let lineRect = NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height)
        lineRect.fill()
    }
}
