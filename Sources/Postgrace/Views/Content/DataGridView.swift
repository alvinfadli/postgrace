import SwiftUI
import AppKit

/// A row wrapper for displaying query result data in a grid.
struct RowData: Identifiable {
    let id: Int
    let values: [CellValue]
}

/// Grid view for displaying table data and SQL query results.
/// Starts pinned at top-left, fills the entire available section, and supports interactive column width resizing.
struct DataGridView: View {
    let queryResult: QueryResult

    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var draggingColumn: String?
    @State private var dragStartWidth: CGFloat = 0

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
        return max(110, min(300, estimated))
    }

    // MARK: - Result Grid

    private var resultGrid: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(queryResult.rows.enumerated()), id: \.offset) { rowIndex, row in
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
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    // MARK: - Header Row

    @ViewBuilder
    private func headerRow(availableWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Row number gutter header
            Text("#")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 6)
                .overlay(
                    Rectangle()
                        .frame(width: 0.5)
                        .foregroundColor(Color(NSColor.separatorColor)),
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
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }

    // MARK: - Header Cell with Resize Handle

    @ViewBuilder
    private func headerCell(column: ResultColumn, colIndex: Int, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Column Name & Data Type
            VStack(alignment: .leading, spacing: 1) {
                Text(column.name)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !column.dataTypeName.isEmpty && column.dataTypeName != "unknown" {
                    Text(column.dataTypeName.lowercased())
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 5)

            Spacer(minLength: 0)

            // Interactive Column Resizer Handle
            Rectangle()
                .fill(draggingColumn == column.name ? Color.accentColor : Color.clear)
                .frame(width: 7)
                .contentShape(Rectangle())
                .overlay(
                    Rectangle()
                        .fill(draggingColumn == column.name ? Color.accentColor : Color(NSColor.separatorColor))
                        .frame(width: 0.5),
                    alignment: .trailing
                )
                .onHover { isHovered in
                    if isHovered {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { gesture in
                            if draggingColumn != column.name {
                                draggingColumn = column.name
                                dragStartWidth = width
                            }
                            let newWidth = max(50, dragStartWidth + gesture.translation.width)
                            columnWidths[column.name] = newWidth
                        }
                        .onEnded { _ in
                            draggingColumn = nil
                        }
                )
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        columnWidths[column.name] = defaultWidth(for: column)
                    }
                )
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: - Data Row

    @ViewBuilder
    private func dataRow(rowIndex: Int, row: [CellValue], availableWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Row number gutter
            Text("\(rowIndex + 1)")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 6)
                .overlay(
                    Rectangle()
                        .frame(width: 0.5)
                        .foregroundColor(Color(NSColor.separatorColor)),
                    alignment: .trailing
                )

            // Cell values
            ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cellValue in
                let width = queryResult.columns.indices.contains(colIndex)
                    ? widthForColumn(at: colIndex, column: queryResult.columns[colIndex])
                    : 120

                cellView(for: cellValue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(width: width, alignment: .leading)
                    .overlay(
                        Rectangle()
                            .frame(width: 0.5)
                            .foregroundColor(Color(NSColor.separatorColor).opacity(0.35)),
                        alignment: .trailing
                    )
            }

            Spacer(minLength: 0)
        }
        .frame(minWidth: availableWidth, alignment: .leading)
        .background(rowIndex % 2 == 0 ? Color(NSColor.textBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.45))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(NSColor.separatorColor).opacity(0.25)),
            alignment: .bottom
        )
    }

    // MARK: - Cell View

    @ViewBuilder
    private func cellView(for cellValue: CellValue) -> some View {
        switch cellValue {
        case .null:
            Text("NULL")
                .font(.system(.body, design: .monospaced))
                .italic()
                .foregroundColor(.gray)
        case .bool(let b):
            Text(b ? "true" : "false")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(b ? .green : .red)
        default:
            Text(cellValue.displayString)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Text("\(queryResult.rows.count) rows")
                .font(.caption)
            Text("•")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(queryResult.columns.count) columns")
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .border(Color(NSColor.separatorColor), width: 0.5)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tablecells")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Data Available")
                .font(.title3)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
