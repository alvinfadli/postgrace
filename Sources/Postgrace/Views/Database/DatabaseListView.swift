import SwiftUI

/// Catalog view listing all PostgreSQL databases on the connected server instance with sizes, owners, encodings, and full CRUD.
struct DatabaseListView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @Environment(ExportViewModel.self) private var exportViewModel
    @Environment(ImportViewModel.self) private var importViewModel

    @State private var showingCreateSheet: Bool = false
    @State private var databaseToDrop: DatabaseInfo?
    @State private var searchText: String = ""
    @State private var errorMessage: String?

    private var currentDatabaseName: String {
        connectionViewModel.selectedConnection?.database ?? ""
    }

    private var currentUser: String {
        schemaViewModel.userPrivileges?.username ?? ""
    }

    private var filteredDatabases: [DatabaseInfo] {
        let list = schemaViewModel.databases.isEmpty ? connectionViewModel.availableDatabases : schemaViewModel.databases
        if searchText.isEmpty {
            return list
        }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.owner.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "cylinder.split.1x2")
                            .foregroundColor(PostgraceTheme.accentSky)
                            .font(.title3)
                        Text("Databases")
                            .font(.title3.bold())
                    }
                    Text("\(schemaViewModel.databases.count) databases on server '\(connectionViewModel.selectedConnection?.name ?? "Server")'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Filter Field
                PostgraceSearchField("Filter databases…", text: $searchText)
                    .frame(width: 200)

                // Refresh Button
                PostgraceIconButton(
                    icon: "arrow.clockwise",
                    tooltip: "Refresh Databases List",
                    variant: .standard,
                    size: 26
                ) {
                    Task {
                        let dbs = await schemaViewModel.loadAvailableDatabases()
                        connectionViewModel.availableDatabases = dbs
                    }
                }

                // + New Database Button
                PostgraceButton(
                    "New Database",
                    icon: "plus",
                    variant: .primary,
                    size: .small
                ) {
                    showingCreateSheet = true
                }
                .disabled(!schemaViewModel.canCreateDatabase)
                .help(schemaViewModel.canCreateDatabase ? "Create a new database" : "Requires CREATEDB or SUPERUSER privilege")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(PostgraceTheme.surface)
            .overlay(
                Rectangle()
                    .fill(PostgraceTheme.border)
                    .frame(height: PostgraceTheme.hairlineBorder),
                alignment: .bottom
            )

            // Error banner if any
            if let error = errorMessage ?? schemaViewModel.crudError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(PostgraceTheme.destructiveRed)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(PostgraceTheme.destructiveRed)
                    Spacer()
                    Button {
                        errorMessage = nil
                        schemaViewModel.crudError = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(PostgraceTheme.destructiveRed.opacity(0.1))
                .overlay(
                    Rectangle()
                        .fill(PostgraceTheme.destructiveRed.opacity(0.3))
                        .frame(height: PostgraceTheme.hairlineBorder),
                    alignment: .bottom
                )
            }

            // Database Table Header
            HStack(spacing: 0) {
                Text("NAME")
                    .frame(minWidth: 180, alignment: .leading)
                Text("STATUS")
                    .frame(width: 100, alignment: .leading)
                Text("OWNER")
                    .frame(width: 120, alignment: .leading)
                Text("ENCODING")
                    .frame(width: 100, alignment: .leading)
                Text("SIZE")
                    .frame(width: 90, alignment: .trailing)
                Spacer()
                Text("ACTIONS")
                    .frame(width: 160, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(PostgraceTheme.surfaceElevated.opacity(0.5))
            .overlay(
                Rectangle()
                    .fill(PostgraceTheme.border)
                    .frame(height: PostgraceTheme.hairlineBorder),
                alignment: .bottom
            )

            // Database Rows
            if filteredDatabases.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "cylinder.split.1x2")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(searchText.isEmpty ? "No databases found" : "No databases matching '\(searchText)'")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredDatabases) { db in
                            databaseRow(db)
                            Divider()
                        }
                    }
                }
            }
        }
        .task {
            if schemaViewModel.databases.isEmpty {
                let dbs = await schemaViewModel.loadAvailableDatabases()
                connectionViewModel.availableDatabases = dbs
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateDatabaseSheet()
        }
        .sheet(item: $databaseToDrop) { db in
            let (canDrop, reason) = schemaViewModel.canDropDatabase(db, currentDatabase: currentDatabaseName)
            DestructiveConfirmationSheet(
                title: "Drop Database \"\(db.name)\"?",
                targetName: db.name,
                actionType: .dropDatabase,
                canPerformAction: canDrop,
                permissionWarning: reason,
                allowsCascade: true
            ) { force in
                Task {
                    do {
                        try await schemaViewModel.dropDatabase(
                            name: db.name,
                            force: force,
                            currentDatabase: currentDatabaseName
                        )
                        let dbs = await schemaViewModel.loadAvailableDatabases()
                        connectionViewModel.availableDatabases = dbs
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - Row View

    @ViewBuilder
    private func databaseRow(_ db: DatabaseInfo) -> some View {
        let isActive = (db.name == currentDatabaseName)
        let (canDrop, dropReason) = schemaViewModel.canDropDatabase(db, currentDatabase: currentDatabaseName)

        HStack(spacing: 0) {
            // Name
            HStack(spacing: 8) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.caption)
                    .foregroundColor(isActive ? PostgraceTheme.accentSky : .secondary)

                Text(db.name)
                    .font(.system(size: 12, weight: isActive ? .bold : .regular))
                    .foregroundColor(isActive ? PostgraceTheme.accentSky : .primary)

                if db.isOwner {
                    Text("OWNER")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(PostgraceTheme.purpleSuperMuted)
                        .foregroundColor(PostgraceTheme.purpleSuper)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(minWidth: 180, alignment: .leading)

            // Status Badge
            HStack(spacing: 4) {
                if isActive {
                    Circle()
                        .fill(PostgraceTheme.emeraldRw)
                        .frame(width: 6, height: 6)
                    Text("Connected")
                        .font(.caption2.bold())
                        .foregroundColor(PostgraceTheme.emeraldRw)
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text("Available")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 100, alignment: .leading)

            // Owner
            Text(db.owner.isEmpty ? "—" : db.owner)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)

            // Encoding
            Text(db.encoding.isEmpty ? "—" : db.encoding)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)

            // Size
            Text(db.size.isEmpty ? "—" : db.size)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)

            Spacer()

            // Actions
            HStack(spacing: 6) {
                if !isActive {
                    Button("Switch") {
                        Task {
                            await connectionViewModel.switchDatabase(to: db.name, schemaViewModel: schemaViewModel)
                        }
                    }
                    .controlSize(.small)
                    .help("Switch active connection to '\(db.name)'")
                }

                Button {
                    exportViewModel.startDatabaseExport(database: db.name)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Export Database '\(db.name)'…")

                Button {
                    importViewModel.startDatabaseImport(database: db.name)
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Import Data to Database '\(db.name)'…")

                // Drop Button (guarded)
                Button {
                    databaseToDrop = db
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(canDrop ? PostgraceTheme.destructiveRed : .secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .disabled(!canDrop)
                .help(canDrop ? "Drop database '\(db.name)'…" : (dropReason ?? "Cannot drop database"))
            }
            .frame(width: 160, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isActive ? PostgraceTheme.accentSkyMuted.opacity(0.3) : Color.clear)
        .contentShape(Rectangle())
        .contextMenu {
            if !isActive {
                Button("Switch to '\(db.name)'") {
                    Task {
                        await connectionViewModel.switchDatabase(to: db.name, schemaViewModel: schemaViewModel)
                    }
                }
            }

            Button("Export Database…") {
                exportViewModel.startDatabaseExport(database: db.name)
            }

            Button("Import Data…") {
                importViewModel.startDatabaseImport(database: db.name)
            }

            Divider()

            Button("Copy Database Name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(db.name, forType: .string)
            }

            Divider()

            Button(role: .destructive) {
                databaseToDrop = db
            } label: {
                Label("Drop Database…", systemImage: "trash")
            }
            .disabled(!canDrop)
        }
    }
}
