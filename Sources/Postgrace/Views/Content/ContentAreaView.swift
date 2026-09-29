import SwiftUI

/// Tab options for the main content area.
enum ContentTab: Hashable {
    case data, query, structure
}

/// Main content area that switches between Data, Query, and Structure views.
struct ContentAreaView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @Environment(DataGridViewModel.self) private var dataGridViewModel
    @State private var selectedTab: ContentTab = .query

    var body: some View {
        if !connectionViewModel.isConnected {
            welcomeView
        } else {
            VStack(spacing: 0) {
                // Tab picker
                Picker("", selection: $selectedTab) {
                    Label("Data", systemImage: "tablecells").tag(ContentTab.data)
                    Label("Query", systemImage: "text.alignleft").tag(ContentTab.query)
                    Label("Structure", systemImage: "list.bullet.rectangle").tag(ContentTab.structure)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)

                Divider()

                // Tab content
                switch selectedTab {
                case .data:
                    dataTab
                case .query:
                    QueryEditorView()
                case .structure:
                    structureTab
                }
            }
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.slash.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Not Connected")
                .font(.title)
            Text("Select a connection from the sidebar or create a new one.")
                .foregroundColor(.secondary)
            Text("⌘N to create a new connection")
                .font(.caption)
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Tab

    private var dataTab: some View {
        Group {
            if let table = schemaViewModel.selectedTable,
               let schema = schemaViewModel.selectedSchema {
                VStack(spacing: 0) {
                    // Table header with pagination
                    HStack {
                        Image(systemName: "tablecells")
                            .foregroundColor(.accentColor)
                        Text(table.name)
                            .font(.title3.bold())
                        Text("(\(schema.name))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Spacer()

                        // Pagination controls
                        if dataGridViewModel.totalRows > 0 {
                            Text("\(dataGridViewModel.totalRows) total rows")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 4) {
                                Button {
                                    Task { await dataGridViewModel.previousPage() }
                                } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .disabled(!dataGridViewModel.hasPreviousPage)

                                Text("Page \(dataGridViewModel.currentPage + 1) / \(dataGridViewModel.totalPages)")
                                    .font(.caption.monospacedDigit())
                                    .frame(minWidth: 80)

                                Button {
                                    Task { await dataGridViewModel.nextPage() }
                                } label: {
                                    Image(systemName: "chevron.right")
                                }
                                .disabled(!dataGridViewModel.hasNextPage)
                            }
                            .controlSize(.small)
                        }

                        Button {
                            Task { await dataGridViewModel.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .controlSize(.small)
                    }
                    .padding(8)

                    Divider()

                    // Data grid
                    if dataGridViewModel.isLoading {
                        ProgressView("Loading data…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = dataGridViewModel.error {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let result = dataGridViewModel.result {
                        DataGridView(queryResult: result)
                    }
                }
                .task(id: table.oid) {
                    await dataGridViewModel.loadTableData(schema: schema.name, table: table.name)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Select a table from the sidebar to view its data")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Structure Tab

    private var structureTab: some View {
        Group {
            if let table = schemaViewModel.selectedTable,
               let schema = schemaViewModel.selectedSchema {
                TableStructureView(schema: schema, table: table)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Select a table to view its structure")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
