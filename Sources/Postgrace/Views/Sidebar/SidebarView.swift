import SwiftUI

/// Sidebar view showing saved connections and schema tree.
struct SidebarView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel

    var body: some View {
        @Bindable var connVM = connectionViewModel

        List {
            Section("Connections") {
                ForEach(connectionViewModel.savedConnections) { connection in
                    ConnectionRow(connection: connection)
                        .contextMenu {
                            Button("Connect") {
                                Task {
                                    await connectionViewModel.connect(to: connection)
                                    await schemaViewModel.loadSchemas()
                                }
                            }
                            Divider()
                            Button("Edit") {
                                connectionViewModel.selectedConnection = connection
                                connectionViewModel.showingEditForm = true
                            }
                            Button("Delete", role: .destructive) {
                                connectionViewModel.deleteConnection(connection)
                            }
                        }
                        .onTapGesture(count: 2) {
                            Task {
                                await connectionViewModel.connect(to: connection)
                                await schemaViewModel.loadSchemas()
                            }
                        }
                }
            }

            if connectionViewModel.isConnected {
                Section("Database Structure") {
                    if schemaViewModel.isLoading && schemaViewModel.schemas.isEmpty {
                        ProgressView("Loading schemas…")
                    }
                    ForEach(schemaViewModel.schemas) { schema in
                        DisclosureGroup {
                            if let tables = schemaViewModel.tables[schema.name] {
                                ForEach(tables) { table in
                                    HStack {
                                        Image(systemName: iconForTableType(table.tableType))
                                            .foregroundColor(.accentColor)
                                        Text(table.name)
                                        Spacer()
                                        Text("\(table.estimatedRowCount) rows")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        schemaViewModel.selectedSchema = schema
                                        schemaViewModel.selectedTable = table
                                    }
                                }
                            } else {
                                ProgressView()
                                    .task {
                                        await schemaViewModel.loadTables(for: schema.name)
                                    }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "cylinder.split.1x2")
                                    .foregroundColor(.accentColor)
                                Text(schema.name)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    connectionViewModel.showingConnectionForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("New Connection")
            }
        }
        .sheet(isPresented: $connVM.showingConnectionForm) {
            ConnectionFormView(connection: nil)
        }
        .sheet(isPresented: $connVM.showingEditForm) {
            ConnectionFormView(connection: connectionViewModel.selectedConnection)
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
}

/// A single connection row in the sidebar.
struct ConnectionRow: View {
    let connection: SavedConnection

    private var tagColor: Color {
        switch connection.colorTag {
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .none: return .gray.opacity(0.3)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tagColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.headline)
                Text("\(connection.host):\(connection.port)/\(connection.database)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
