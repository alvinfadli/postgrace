import SwiftUI

/// Top unified titlebar matching the artifact design.
/// Contains Server context badge, In-Connection Database Switcher (⌘⇧D), breadcrumbs,
/// Privilege badge, and Disconnect button.
struct WorkspaceToolbarView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @Environment(WorkspaceTabViewModel.self) private var tabViewModel
    @Environment(ExportViewModel.self) private var exportViewModel
    @Environment(ImportViewModel.self) private var importViewModel

    @State private var showingCreateDatabaseSheet: Bool = false
    @State private var databaseToDrop: DatabaseInfo?
    @State private var dropDatabaseError: String?

    var body: some View {
        HStack(spacing: 8) {
            // Space for macOS native window traffic lights (close, minimize, zoom)
            Spacer()
                .frame(width: 68)

            // Divider separating traffic lights from breadcrumbs
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(width: PostgraceTheme.hairlineBorder, height: 16)

            // Left: Server & Database Breadcrumbs
            if let conn = connectionViewModel.selectedConnection {
                // Server Pill with Quick Switch & Edit
                Menu {
                    Section("Active Server") {
                        Label("\(conn.name) (\(conn.host):\(conn.port))", systemImage: "server.rack")
                        Button {
                            connectionViewModel.openEditConnectionForm(for: conn)
                        } label: {
                            Label("Edit Connection '\(conn.name)'...", systemImage: "pencil")
                        }
                    }

                    if connectionViewModel.savedConnections.count > 1 {
                        Section("Switch Saved Connection") {
                            ForEach(connectionViewModel.savedConnections) { otherConn in
                                if otherConn.id != conn.id {
                                    Button {
                                        Task {
                                            await connectionViewModel.connect(to: otherConn)
                                            if connectionViewModel.isConnected {
                                                await schemaViewModel.refresh()
                                                let databases = await schemaViewModel.loadAvailableDatabases()
                                                connectionViewModel.availableDatabases = databases
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text(otherConn.name)
                                            Spacer()
                                            Text("\(otherConn.host):\(otherConn.port)")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        connectionViewModel.openNewConnectionForm()
                    } label: {
                        Label("New Connection...", systemImage: "plus")
                    }

                    Button {
                        Task {
                            await connectionViewModel.disconnect()
                        }
                    } label: {
                        Label("Manage Connections (Hub)...", systemImage: "rectangle.stack")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(tagColor(conn.colorTag))
                            .frame(width: 7, height: 7)
                        Text(conn.name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .menuStyle(.borderlessButton)
                .help("Active Server: \(conn.name) — Click to Edit or Switch Server")

                Text("/")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(PostgraceTheme.border)

                // DATABASE SWITCHER DROPDOWN (⌘⇧D)
                Menu {
                    Section("Switch Database (⌘⇧D)") {
                        ForEach(connectionViewModel.availableDatabases) { db in
                            Button {
                                Task {
                                    await connectionViewModel.switchDatabase(
                                        to: db.name,
                                        schemaViewModel: schemaViewModel
                                    )
                                }
                            } label: {
                                HStack {
                                    Text(db.name)
                                    if db.name == conn.database {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Section("Database Management") {
                        Button {
                            tabViewModel.openDatabasesTab()
                        } label: {
                            Label("Databases Catalog…", systemImage: "cylinder.split.1x2")
                        }

                        Button {
                            showingCreateDatabaseSheet = true
                        } label: {
                            Label("New Database…", systemImage: "plus")
                        }
                        .disabled(!schemaViewModel.canCreateDatabase)

                        Menu("Drop Database") {
                            ForEach(connectionViewModel.availableDatabases) { db in
                                let (canDrop, reason) = schemaViewModel.canDropDatabase(db, currentDatabase: conn.database)
                                Button(role: .destructive) {
                                    databaseToDrop = db
                                } label: {
                                    if !canDrop, let reason = reason {
                                        Text("\(db.name) (\(reason))")
                                    } else {
                                        Text(db.name)
                                    }
                                }
                                .disabled(!canDrop)
                            }
                        }
                    }

                    Divider()

                    Button("Export Database '\(conn.database)'…") {
                        exportViewModel.startDatabaseExport(database: conn.database)
                    }

                    Button("Import to Database (Restore)…") {
                        importViewModel.startDatabaseImport(database: conn.database)
                    }

                    Divider()

                    Button("Refresh Database List") {
                        Task {
                            let dbs = await schemaViewModel.loadAvailableDatabases()
                            connectionViewModel.availableDatabases = dbs
                            await schemaViewModel.loadSchemas()
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "cylinder.split.1x2")
                            .font(.system(size: 11))
                            .foregroundColor(PostgraceTheme.accentSky)
                        Text(conn.database)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(PostgraceTheme.accentSky)

                        if connectionViewModel.isSwitchingDatabase {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(PostgraceTheme.accentSky.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(PostgraceTheme.accentSkyMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(PostgraceTheme.accentSky.opacity(0.4), lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .menuStyle(.borderlessButton)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help("Switch Database (⌘⇧D)")

                // Active Schema / Relation context
                if let activeTab = tabViewModel.activeTab {
                    Text("/")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(PostgraceTheme.border)

                    switch activeTab.type {
                    case .table(let schema, let table):
                        breadcrumbRelation(schema: schema, table: table)
                    case .structure(let schema, let table):
                        breadcrumbRelation(schema: schema, table: table)
                    case .query:
                        // Keep navigation the same as the data tab (server / db / schema / table)
                        if let selectedTable = schemaViewModel.selectedTable {
                            breadcrumbRelation(schema: selectedTable.schema, table: selectedTable.name)
                        } else if let selectedSchema = schemaViewModel.selectedSchema {
                            breadcrumbRelation(schema: selectedSchema.name, table: "")
                        } else {
                            breadcrumbRelation(schema: "public", table: "")
                        }
                    case .schemas:
                        Label("Schemas Catalog", systemImage: "square.3.layers.3d")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    case .databases:
                        Label("Databases Catalog", systemImage: "cylinder.split.1x2")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    case .tables(let schema):
                        HStack(spacing: 4) {
                            Text(schema)
                                .foregroundColor(.secondary)
                            Text("/")
                                .foregroundColor(PostgraceTheme.border)
                            Text("Tables")
                                .foregroundColor(.primary)
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 11))
                    }
                }
            }

            Spacer()

            // Right: User Privilege Pill Badge
            UserPrivilegeBadgeView()

            // Disconnect Action Button
            Button {
                Task {
                    await connectionViewModel.disconnect()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Disconnect")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(PostgraceTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )
            }
            .buttonStyle(.plain)
            .help("Disconnect from Server")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            ZStack {
                PostgraceTheme.surface
                WindowDragArea()
            }
        )
        .overlay(
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder),
            alignment: .bottom
        )
        .sheet(isPresented: $showingCreateDatabaseSheet) {
            CreateDatabaseSheet()
        }
        .sheet(item: $databaseToDrop) { db in
            let (canDrop, reason) = schemaViewModel.canDropDatabase(db, currentDatabase: connectionViewModel.selectedConnection?.database)
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
                            currentDatabase: connectionViewModel.selectedConnection?.database
                        )
                        let dbs = await schemaViewModel.loadAvailableDatabases()
                        connectionViewModel.availableDatabases = dbs
                    } catch {
                        dropDatabaseError = error.localizedDescription
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func breadcrumbRelation(schema: String, table: String) -> some View {
        HStack(spacing: 4) {
            Text(schema)
                .foregroundColor(.secondary)
            if !table.isEmpty {
                Text("/")
                    .foregroundColor(PostgraceTheme.border)
                Text(table)
                    .foregroundColor(.primary)
                    .fontWeight(.semibold)
            }
        }
        .font(.system(size: 11))
    }

    private func tagColor(_ tag: ConnectionColor) -> Color {
        switch tag {
        case .red: return PostgraceTheme.destructiveRed
        case .blue: return PostgraceTheme.accentSky
        case .green: return PostgraceTheme.emeraldRw
        case .orange: return PostgraceTheme.amberRo
        case .purple: return PostgraceTheme.purpleSuper
        case .none: return PostgraceTheme.emeraldRw
        }
    }
}
