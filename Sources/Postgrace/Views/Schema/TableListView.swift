import SwiftUI

/// Catalog view listing all tables in a specific PostgreSQL schema with sizes, row counts, permissions, and full CRUD operations.
struct TableListView: View {
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @Environment(WorkspaceTabViewModel.self) private var tabViewModel
    @Environment(QueryViewModel.self) private var queryViewModel

    let schema: String

    @State private var searchText: String = ""
    @State private var showingCreateTableSheet: Bool = false
    @State private var tableToRename: TableDetail?
    @State private var newTableName: String = ""
    @State private var tableToTruncate: TableDetail?
    @State private var tableToDrop: TableDetail?
    @State private var errorMessage: String?

    private var currentUser: String {
        schemaViewModel.userPrivileges?.username ?? ""
    }

    private var canCreateTableInSchema: Bool {
        guard let privs = schemaViewModel.userPrivileges else { return true }
        if privs.isSuperuser { return true }
        return privs.schemaPrivileges[schema]?.canCreate ?? false
    }

    private var tables: [TableDetail] {
        schemaViewModel.tableDetails[schema] ?? []
    }

    private var filteredTables: [TableDetail] {
        if searchText.isEmpty {
            return tables
        }
        return tables.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                        Text(schema)
                            .font(.title3.bold())
                        Text("/")
                            .foregroundColor(.secondary)
                        Text("Tables")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    Text("\(tables.count) tables & views in schema '\(schema)'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Filter Field
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
                .frame(width: 180)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Refresh Button
                Button {
                    Task {
                        await schemaViewModel.loadTableDetails(for: schema)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Tables in \(schema)")

                // + New Table Button (guarded by schema CREATE privilege)
                Button {
                    showingCreateTableSheet = true
                } label: {
                    Label("New Table", systemImage: "plus")
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!canCreateTableInSchema)
                .help(canCreateTableInSchema ? "Create new table in \(schema)" : "User '\(currentUser)' lacks CREATE privilege on schema '\(schema)'")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Error Banner
            if let error = errorMessage ?? schemaViewModel.crudError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button {
                        errorMessage = nil
                        schemaViewModel.crudError = nil
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                Divider()
            }

            // Tables Table
            if schemaViewModel.isLoading && tables.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading tables for \(schema)…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tables.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No Tables in '\(schema)'")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    if canCreateTableInSchema {
                        Button("Create First Table") {
                            showingCreateTableSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("You do not have permission to create tables in this schema.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredTables) {
                    TableColumn("Table Name") { table in
                        HStack(spacing: 6) {
                            Image(systemName: iconForTableType(table.tableType))
                                .foregroundColor(colorForTableType(table.tableType))
                                .font(.caption)
                            Text(table.name)
                                .fontWeight(.medium)
                        }
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Type") { table in
                        Text(table.tableType.rawValue.uppercased())
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .width(min: 80, ideal: 100)

                    TableColumn("Est. Rows") { table in
                        Text(table.rowCount >= 0 ? "\(table.rowCount)" : "—")
                            .font(.callout.monospacedDigit())
                    }
                    .width(min: 70, ideal: 90)

                    TableColumn("Total Size") { table in
                        Text(table.totalSize)
                            .font(.callout.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(min: 75, ideal: 95)

                    TableColumn("Index Size") { table in
                        Text(table.indexSize)
                            .font(.callout.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(min: 75, ideal: 95)

                    TableColumn("Cols") { table in
                        Text("\(table.columnCount)")
                            .font(.callout.monospacedDigit())
                    }
                    .width(min: 45, ideal: 60)

                    TableColumn("Access") { table in
                        HStack(spacing: 4) {
                            if table.isOwner {
                                Text("OWNER")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.purple.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            if table.canInsert {
                                Text("WRITE")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Actions") { table in
                        HStack(spacing: 8) {
                            Button("Data") {
                                tabViewModel.openTableTab(schema: table.schema, table: table.name)
                            }
                            .buttonStyle(.link)
                            .font(.caption)

                            Button("Structure") {
                                tabViewModel.openStructureTab(schema: table.schema, table: table.name)
                            }
                            .buttonStyle(.link)
                            .font(.caption)

                            Menu {
                                Button("Open Data") {
                                    tabViewModel.openTableTab(schema: table.schema, table: table.name)
                                }
                                Button("Open Structure") {
                                    tabViewModel.openStructureTab(schema: table.schema, table: table.name)
                                }
                                Button("Query: SELECT *") {
                                    queryViewModel.queryText = "SELECT * FROM \"\(table.schema)\".\"\(table.name)\" LIMIT 100;"
                                    tabViewModel.openQueryTab()
                                }

                                Divider()

                                Button("Rename Table…") {
                                    newTableName = table.name
                                    tableToRename = table
                                }
                                .disabled(!canAlterOrDrop(table))

                                Button("Truncate Data…") {
                                    tableToTruncate = table
                                }
                                .disabled(!canAlterOrDrop(table))

                                Button("Drop Table…", role: .destructive) {
                                    tableToDrop = table
                                }
                                .disabled(!canAlterOrDrop(table))
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.caption)
                            }
                            .menuStyle(.borderlessButton)
                        }
                    }
                    .width(min: 140, ideal: 170)
                }
            }
        }
        .task(id: schema) {
            await schemaViewModel.loadTableDetails(for: schema)
        }
        .sheet(isPresented: $showingCreateTableSheet) {
            CreateTableSheet(initialSchema: schema)
        }
        .sheet(item: $tableToTruncate) { table in
            DestructiveConfirmationSheet(
                title: "Truncate Table \"\(table.name)\"?",
                targetName: table.name,
                actionType: .truncateTable,
                canPerformAction: canAlterOrDrop(table),
                permissionWarning: canAlterOrDrop(table) ? nil : "Only the table owner or superuser can truncate this table.",
                allowsCascade: false
            ) { _ in
                Task {
                    do {
                        try await schemaViewModel.truncateTable(schema: table.schema, name: table.name)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .sheet(item: $tableToDrop) { table in
            DestructiveConfirmationSheet(
                title: "Drop Table \"\(table.name)\"?",
                targetName: table.name,
                actionType: .dropTable,
                canPerformAction: canAlterOrDrop(table),
                permissionWarning: canAlterOrDrop(table) ? nil : "Only the table owner or superuser can drop this table.",
                allowsCascade: true
            ) { cascade in
                Task {
                    do {
                        try await schemaViewModel.dropTable(schema: table.schema, name: table.name, cascade: cascade)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .sheet(item: $tableToRename) { table in
            renameTableModal(table)
        }
    }

    private func canAlterOrDrop(_ table: TableDetail) -> Bool {
        guard let privs = schemaViewModel.userPrivileges else { return true }
        if privs.isSuperuser { return true }
        return table.isOwner
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

    // MARK: - Rename Table Modal

    @ViewBuilder
    private func renameTableModal(_ table: TableDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rename Table \"\(table.name)\"")
                        .font(.headline)
                    Text("Enter a new identifier for this table")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("New Table Name")
                    .font(.caption.bold())
                TextField("New Name", text: $newTableName)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    tableToRename = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Rename Table") {
                    let oldName = table.name
                    let target = newTableName.trimmingCharacters(in: .whitespacesAndNewlines)
                    tableToRename = nil
                    Task {
                        do {
                            try await schemaViewModel.renameTable(schema: table.schema, oldName: oldName, newName: target)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(newTableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newTableName == table.name)
            }
        }
        .padding(20)
        .frame(width: 380, height: 200)
    }
}
