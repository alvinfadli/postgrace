import SwiftUI
import AppKit

/// High-performance full-bleed data grid matching the artifact design.
/// Starts pinned at top-left, fills the entire available section, and supports interactive column width resizing.
struct DataGridView: View {
    let queryResult: QueryResult

    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var hoveredRowIndex: Int? = nil
    @State private var sortColumn: String? = nil
    @State private var sortAscending: Bool = true

    private var displayedRows: [[CellValue]] {
        guard let sortCol = sortColumn,
              let colIndex = queryResult.columns.firstIndex(where: { $0.name == sortCol }) else {
            return queryResult.rows
        }
        return queryResult.rows.sorted { row1, row2 in
            let val1 = colIndex < row1.count ? row1[colIndex] : .null
            let val2 = colIndex < row2.count ? row2[colIndex] : .null
            let isLess = compareCells(val1, val2)
            return sortAscending ? isLess : !isLess
        }
    }

    private func compareCells(_ a: CellValue, _ b: CellValue) -> Bool {
        switch (a, b) {
        case (.null, .null): return false
        case (.null, _): return false
        case (_, .null): return true
        case (.int(let x), .int(let y)): return x < y
        case (.double(let x), .double(let y)): return x < y
        case (.bool(let x), .bool(let y)): return !x && y
        case (.date(let x), .date(let y)): return x < y
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
        }
    }

    // MARK: - Column Width Calculation

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

    // MARK: - Result Grid

    private var resultGrid: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(displayedRows.enumerated()), id: \.offset) { rowIndex, row in
                                dataRow(rowIndex: rowIndex, row: row, availableWidth: proxy.size.width)
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

            // Resizable column headers
            ForEach(Array(queryResult.columns.enumerated()), id: \.offset) { colIndex, column in
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

    // MARK: - Header Cell with Resize Handle & Sort

    @ViewBuilder
    private func headerCell(column: ResultColumn, colIndex: Int, width: CGFloat) -> some View {
        HStack(spacing: 0) {
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
                .padding(.trailing, 4)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to sort by \(column.name)")

            Spacer(minLength: 0)

            // High-performance AppKit column resizer handle
            ColumnResizeHandle(
                currentWidth: width,
                onResize: { newWidth in
                    columnWidths[column.name] = newWidth
                },
                onDoubleClick: {
                    columnWidths[column.name] = defaultWidth(for: column)
                }
            )
            .frame(width: 8, height: 32)
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: - Data Row

    @ViewBuilder
    private func dataRow(rowIndex: Int, row: [CellValue], availableWidth: CGFloat) -> some View {
        let isHovered = hoveredRowIndex == rowIndex
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

            // Cell values
            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cellValue in
                let width = queryResult.columns.indices.contains(colIndex)
                    ? widthForColumn(at: colIndex, column: queryResult.columns[colIndex])
                    : 120

                let column = queryResult.columns.indices.contains(colIndex) ? queryResult.columns[colIndex] : ResultColumn(name: "col", dataTypeOID: 0, dataTypeName: "")

                cellView(for: cellValue, column: column, row: row)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(width: width, alignment: .leading)
                    .overlay(
                        Rectangle()
                            .frame(width: PostgraceTheme.hairlineBorder)
                            .foregroundColor(PostgraceTheme.borderSubtle.opacity(0.4)),
                        alignment: .trailing
                    )
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: availableWidth, alignment: .leading)
        .background(isHovered ? PostgraceTheme.surfaceHover : zebraBg)
        .overlay(
            Rectangle()
                .frame(height: PostgraceTheme.hairlineBorder)
                .foregroundColor(PostgraceTheme.borderSubtle.opacity(0.3)),
            alignment: .bottom
        )
        .onHover { hovering in
            hoveredRowIndex = hovering ? rowIndex : nil
        }
    }

    // MARK: - Cell View with Context Menu

    @ViewBuilder
    private func cellView(for cellValue: CellValue, column: ResultColumn, row: [CellValue]) -> some View {
        cellContent(for: cellValue)
            .contextMenu {
                Button("Copy Cell Value") {
                    copyToPasteboard(cellValue.displayString)
                }
                Button("Copy Column Name (\(column.name))") {
                    copyToPasteboard(column.name)
                }
                Divider()
                Button("Copy Row as CSV") {
                    copyRowAsCSV(row)
                }
                Button("Copy Row as JSON") {
                    copyRowAsJSON(row)
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
                .textSelection(.enabled)
        }
    }

    // MARK: - Footer with Export Actions

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(displayedRows.count) rows")
                .font(.system(size: 11, design: .monospaced))
            Text("•")
                .foregroundColor(PostgraceTheme.border)
            Text("\(queryResult.columns.count) columns")
                .font(.system(size: 11, design: .monospaced))
            if queryResult.executionTime > 0 {
                Text("•")
                    .foregroundColor(PostgraceTheme.border)
                Text(String(format: "%.3f s", queryResult.executionTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PostgraceTheme.emeraldRw)
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

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyRowAsCSV(_ row: [CellValue]) {
        let line = row.map { formatCSVCell($0.displayString) }.joined(separator: ",")
        copyToPasteboard(line)
    }

    private func copyRowAsJSON(_ row: [CellValue]) {
        var dict: [String: Any] = [:]
        for (i, col) in queryResult.columns.enumerated() {
            if i < row.count {
                let cell = row[i]
                switch cell {
                case .null: dict[col.name] = NSNull()
                case .int(let v): dict[col.name] = v
                case .double(let v): dict[col.name] = v
                case .bool(let v): dict[col.name] = v
                default: dict[col.name] = cell.displayString
                }
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
        var rowsArray: [[String: Any]] = []
        for row in displayedRows {
            var dict: [String: Any] = [:]
            for (i, col) in queryResult.columns.enumerated() {
                if i < row.count {
                    let cell = row[i]
                    switch cell {
                    case .null: dict[col.name] = NSNull()
                    case .int(let v): dict[col.name] = v
                    case .double(let v): dict[col.name] = v
                    case .bool(let v): dict[col.name] = v
                    default: dict[col.name] = cell.displayString
                    }
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
        var lines: [String] = []
        lines.append(queryResult.columns.map { formatCSVCell($0.name) }.joined(separator: ","))
        for row in displayedRows {
            lines.append(row.map { formatCSVCell($0.displayString) }.joined(separator: ","))
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
        if event.clickCount == 2 {
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
            ? (isDark ? NSColor(hex: "#38BDF8") : NSColor(hex: "#0284C7"))
            : (isDark ? NSColor(hex: "#262C36") : NSColor(hex: "#E2E8F0"))

        strokeColor.setFill()
        let lineRect = NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height)
        lineRect.fill()
    }
}

