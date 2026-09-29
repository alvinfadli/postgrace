import SwiftUI

/// Sidebar view showing schemas, tables, and views for the active connection.
struct SidebarView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @Environment(WorkspaceTabViewModel.self) private var tabViewModel
    @Environment(QueryViewModel.self) private var queryViewModel

    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search / Filter Tables Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Filter tables…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(8)

            Divider()

            // Schema & Table List
            List {
                if schemaViewModel.isLoading && schemaViewModel.schemas.isEmpty {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Introspecting database…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }

                ForEach(schemaViewModel.schemas) { schema in
                    DisclosureGroup(isExpanded: .constant(true)) {
                        let allTables = schemaViewModel.tables[schema.name] ?? []
                        let filteredTables = searchText.isEmpty
                            ? allTables
                            : allTables.filter { $0.name.localizedCaseInsensitiveContains(searchText) }

                        if filteredTables.isEmpty && !allTables.isEmpty {
                            Text("No matching tables")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.leading, 12)
                        } else {
                            ForEach(filteredTables) { table in
                                tableRow(schema: schema, table: table)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)
                                .font(.caption)
                            Text(schema.name)
                                .font(.caption.bold())
                            Spacer()
                            if let count = schemaViewModel.tables[schema.name]?.count {
                                Text("\(count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .task(id: schema.name) {
                        if schemaViewModel.tables[schema.name] == nil {
                            await schemaViewModel.loadTables(for: schema.name)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Sidebar Footer Actions
            HStack {
                Button {
                    Task {
                        await schemaViewModel.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Refresh Schemas")

                Spacer()

                Button {
                    tabViewModel.openQueryTab()
                } label: {
                    Label("New Query", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Open New Query Tab (⌘T)")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    // MARK: - Table Row

    @ViewBuilder
    private func tableRow(schema: SchemaInfo, table: TableInfo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconForTableType(table.tableType))
                .font(.caption)
                .foregroundColor(colorForTableType(table.tableType))

            Text(table.name)
                .font(.caption)
                .lineLimit(1)

            Spacer()

            if table.estimatedRowCount > 0 {
                Text("\(table.estimatedRowCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            schemaViewModel.selectedSchema = schema
            schemaViewModel.selectedTable = table
            tabViewModel.openTableTab(schema: schema.name, table: table.name)
        }
        .contextMenu {
            Button("Open Data") {
                tabViewModel.openTableTab(schema: schema.name, table: table.name)
            }
            Button("Open Structure") {
                tabViewModel.openStructureTab(schema: schema.name, table: table.name)
            }
            Divider()
            Button("Query: SELECT * FROM \"\(table.name)\"") {
                queryViewModel.queryText = "SELECT * FROM \"\(schema.name)\".\"\(table.name)\" LIMIT 100;"
                tabViewModel.openQueryTab()
            }
        }
    }

    private func iconForTableType(_ type: TableType) -> String {
        switch type {
        case .table: return "tablecells"
        case .view: return "eye"
        case .materializedView: return "eye.fill"
        case .foreignTable: return "link"
        }
    }

    private func colorForTableType(_ type: TableType) -> Color {
        switch type {
        case .table: return .accentColor
        case .view: return .purple
        case .materializedView: return .indigo
        case .foreignTable: return .orange
        }
    }
}
