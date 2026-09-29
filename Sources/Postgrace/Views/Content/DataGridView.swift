import SwiftUI

/// A row wrapper for displaying query result data in a grid.
struct RowData: Identifiable {
    let id: Int
    let values: [CellValue]
}

/// Grid view for displaying query results.
///
/// SwiftUI's `Table` requires statically-defined columns at compile time,
/// which doesn't work for dynamic SQL results with varying column counts.
/// Instead, we use a scrollable grid with an `NSTableView`-style layout.
struct DataGridView: View {
    let queryResult: QueryResult

    var body: some View {
        if queryResult.columns.isEmpty && queryResult.rows.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                resultGrid
                footer
            }
        }
    }

    // MARK: - Result Grid

    private var resultGrid: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(queryResult.rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            // Row number
                            Text("\(rowIndex + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                                .padding(.horizontal, 4)

                            ForEach(Array(row.enumerated()), id: \.offset) { _, cellValue in
                                cellView(for: cellValue)
                                    .frame(minWidth: 120, maxWidth: 300, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                            }
                        }
                        .background(rowIndex % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.5))
                    }
                } header: {
                    // Column headers
                    HStack(spacing: 0) {
                        Text("#")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                            .padding(.horizontal, 4)

                        ForEach(Array(queryResult.columns.enumerated()), id: \.offset) { _, column in
                            Text(column.name)
                                .font(.caption.bold())
                                .frame(minWidth: 120, maxWidth: 300, alignment: .leading)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .border(Color(NSColor.separatorColor), width: 0.5)
                }
            }
        }
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
