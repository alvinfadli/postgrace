import SwiftUI

/// Tab options for the main content area.
enum ContentTab: Hashable {
    case data, query, structure
}

/// Main content area that switches between Data, Query, and Structure views.
struct ContentAreaView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
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
            if let table = schemaViewModel.selectedTable {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "tablecells")
                            .foregroundColor(.accentColor)
                        Text(table.name)
                            .font(.title3.bold())
                        if let schema = schemaViewModel.selectedSchema {
                            Text("(\(schema.name))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(8)

                    Divider()

                    // TODO: Fetch and display table data
                    Text("Table data view coming soon")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let table = schemaViewModel.selectedTable {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundColor(.accentColor)
                        Text("Structure: \(table.name)")
                            .font(.title3.bold())
                        Spacer()
                    }
                    .padding(8)

                    Divider()

                    // TODO: Display column info, indexes, constraints
                    Text("Structure view coming soon")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
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
