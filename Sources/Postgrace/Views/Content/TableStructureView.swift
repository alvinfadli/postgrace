import SwiftUI

/// Displays table structure: columns, types, constraints, and indexes.
struct TableStructureView: View {
    @Environment(SchemaViewModel.self) private var schemaViewModel

    let schema: SchemaInfo
    let table: TableInfo

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.accentColor)
                Text(table.name)
                    .font(.title3.bold())
                Text("— \(schema.name)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    Task {
                        await schemaViewModel.loadColumns(for: schema.name, table: table.name)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }
            .padding(8)

            Divider()

            // Column list
            let key = "\(schema.name).\(table.name)"
            if let cols = schemaViewModel.columns[key] {
                if cols.isEmpty {
                    Text("No columns found")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    columnTable(cols)
                }
            } else {
                ProgressView("Loading columns…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task {
                        await schemaViewModel.loadColumns(for: schema.name, table: table.name)
                    }
            }
        }
    }

    // MARK: - Column Table

    @ViewBuilder
    private func columnTable(_ columns: [ColumnInfo]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(columns) { col in
                        HStack(spacing: 0) {
                            // Primary key indicator
                            Group {
                                if col.isPrimaryKey {
                                    Image(systemName: "key.fill")
                                        .foregroundColor(.yellow)
                                } else {
                                    Text("")
                                }
                            }
                            .frame(width: 30)

                            // Column name
                            Text(col.name)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(col.isPrimaryKey ? .bold : .regular)
                                .frame(minWidth: 150, alignment: .leading)
                                .padding(.horizontal, 6)

                            // Data type
                            Text(col.dataType)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.accentColor)
                                .frame(minWidth: 120, alignment: .leading)
                                .padding(.horizontal, 6)

                            // Max length
                            if let maxLen = col.characterMaxLength {
                                Text("(\(maxLen))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 50, alignment: .leading)
                            } else {
                                Text("")
                                    .frame(width: 50)
                            }

                            // Nullable
                            Text(col.isNullable ? "NULL" : "NOT NULL")
                                .font(.caption)
                                .foregroundColor(col.isNullable ? .secondary : .orange)
                                .frame(width: 70, alignment: .leading)

                            // Default value
                            if let def = col.defaultValue {
                                Text("= \(def)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .background(col.ordinalPosition % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.5))
                    }
                } header: {
                    HStack(spacing: 0) {
                        Text("")
                            .frame(width: 30)
                        Text("Column")
                            .font(.caption.bold())
                            .frame(minWidth: 150, alignment: .leading)
                            .padding(.horizontal, 6)
                        Text("Type")
                            .font(.caption.bold())
                            .frame(minWidth: 120, alignment: .leading)
                            .padding(.horizontal, 6)
                        Text("Size")
                            .font(.caption.bold())
                            .frame(width: 50, alignment: .leading)
                        Text("Nullable")
                            .font(.caption.bold())
                            .frame(width: 70, alignment: .leading)
                        Text("Default")
                            .font(.caption.bold())
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .background(Color(NSColor.windowBackgroundColor))
                    .border(Color(NSColor.separatorColor), width: 0.5)
                }
            }
        }
    }
}
