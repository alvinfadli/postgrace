import SwiftUI

/// Catalog view listing all PostgreSQL schemas in the current database with sizes, owners, relation counts, and full CRUD.
struct SchemaListView: View {
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @Environment(WorkspaceTabViewModel.self) private var tabViewModel
    @Environment(ExportViewModel.self) private var exportViewModel

    @State private var showingCreateSheet: Bool = false
    @State private var schemaToRename: SchemaDetail?
    @State private var newSchemaName: String = ""
    @State private var schemaToDrop: SchemaDetail?
    @State private var errorMessage: String?

    private var currentUser: String {
        schemaViewModel.userPrivileges?.username ?? ""
    }

    private var canCreateSchema: Bool {
        guard let privs = schemaViewModel.userPrivileges else { return true }
        return privs.isSuperuser || privs.canCreateSchemaInDb
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.3.layers.3d")
                            .foregroundColor(PostgraceTheme.accentSky)
                            .font(.title3)
                        Text("Schemas")
                            .font(.title3.bold())
                    }
                    Text("\(schemaViewModel.schemaDetails.count) schemas available in active database")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Refresh Button
                Button {
                    Task {
                        await schemaViewModel.loadSchemaDetails()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Schemas")

                // + New Schema Button (guarded by database-level CREATE privilege)
                PostgraceButton(
                    "New Schema",
                    icon: "plus",
                    variant: .primary
                ) {
                    showingCreateSheet = true
                }
                .disabled(!canCreateSchema)
                .help(canCreateSchema ? "Create a new schema" : "User '\(currentUser)' lacks CREATE privilege on this database")
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

            // Error Message Banner if any
            if let error = errorMessage ?? schemaViewModel.crudError {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(PostgraceTheme.destructiveRed)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(PostgraceTheme.destructiveRed)
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
                .background(PostgraceTheme.destructiveRedMuted)
                .overlay(
                    Rectangle()
                        .fill(PostgraceTheme.border)
                        .frame(height: PostgraceTheme.hairlineBorder),
                    alignment: .bottom
                )
            }

            // Schemas Table
            if schemaViewModel.isLoading && schemaViewModel.schemaDetails.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading schemas…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(schemaViewModel.schemaDetails) {
                    TableColumn("Name") { schema in
                        HStack(spacing: 6) {
                            Image(systemName: schema.isSystem ? "folder.badge.gearshape" : "folder.fill")
                                .foregroundColor(schema.isSystem ? .secondary : PostgraceTheme.accentSky)
                            Text(schema.name)
                                .fontWeight(schema.name == "public" ? .bold : .regular)
                            if schema.isSystem {
                                Text("SYSTEM")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(PostgraceTheme.surfaceHover)
                                    .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusBadge, style: .continuous))
                            }
                        }
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Owner") { schema in
                        Text(schema.owner)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .width(min: 90, ideal: 120)

                    TableColumn("Tables") { schema in
                        Text("\(schema.tableCount)")
                            .font(.callout.monospacedDigit())
                    }
                    .width(min: 60, ideal: 80)

                    TableColumn("Disk Size") { schema in
                        Text(schema.totalSize)
                            .font(.callout.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(min: 80, ideal: 100)

                    TableColumn("User Access") { schema in
                        HStack(spacing: 4) {
                            if schema.canCreateTables {
                                Text("CREATE")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(PostgraceTheme.accentSageText)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(PostgraceTheme.accentSageMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusBadge, style: .continuous))
                            }
                            Text("USAGE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(PostgraceTheme.purpleSuperText)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(PostgraceTheme.purpleSuperMuted)
                                .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusBadge, style: .continuous))
                        }
                    }
                    .width(min: 110, ideal: 130)

                    TableColumn("Actions") { schema in
                        HStack(spacing: 8) {
                            Button("Browse") {
                                tabViewModel.openTablesTab(schema: schema.name)
                            }
                            .buttonStyle(.link)
                            .font(.caption)

                            if !schema.isSystem {
                                Menu {
                                    Button("Browse Tables") {
                                        tabViewModel.openTablesTab(schema: schema.name)
                                    }

                                    Button("Export Schema…") {
                                        exportViewModel.startSchemaExport(schema: schema.name)
                                    }

                                    Divider()

                                    Button("Rename Schema…") {
                                        newSchemaName = schema.name
                                        schemaToRename = schema
                                    }
                                    .disabled(!canAlterOrDrop(schema))

                                    Button("Drop Schema…", role: .destructive) {
                                        schemaToDrop = schema
                                    }
                                    .disabled(!canAlterOrDrop(schema))
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.caption)
                                }
                                .menuStyle(.borderlessButton)
                            }
                        }
                    }
                    .width(min: 90, ideal: 110)
                }
            }
        }
        .task {
            if schemaViewModel.schemaDetails.isEmpty {
                await schemaViewModel.loadSchemaDetails()
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreateSchemaSheet()
        }
        .sheet(item: $schemaToDrop) { schema in
            DestructiveConfirmationSheet(
                title: "Drop Schema \"\(schema.name)\"?",
                targetName: schema.name,
                actionType: .dropSchema,
                canPerformAction: canAlterOrDrop(schema),
                permissionWarning: canAlterOrDrop(schema) ? nil : "Only the schema owner ('\(schema.owner)') or a superuser can drop this schema.",
                allowsCascade: true
            ) { cascade in
                Task {
                    do {
                        try await schemaViewModel.dropSchema(name: schema.name, cascade: cascade)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .sheet(item: $schemaToRename) { schema in
            renameSchemaModal(schema)
        }
    }

    private func canAlterOrDrop(_ schema: SchemaDetail) -> Bool {
        guard let privs = schemaViewModel.userPrivileges else { return true }
        if privs.isSuperuser { return true }
        return schema.owner == privs.username
    }

    // MARK: - Rename Schema Modal

    @ViewBuilder
    private func renameSchemaModal(_ schema: SchemaDetail) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.title2)
                    .foregroundColor(PostgraceTheme.accentSky)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rename Schema \"\(schema.name)\"")
                        .font(.headline)
                    Text("Enter a new identifier for this schema")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("New Schema Name")
                    .font(.caption.bold())
                PostgraceTextField("New Name", text: $newSchemaName)
            }

            Spacer()

            HStack {
                PostgraceButton("Cancel", variant: .secondary) {
                    schemaToRename = nil
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                PostgraceButton("Rename Schema", variant: .primary) {
                    let oldName = schema.name
                    let target = newSchemaName.trimmingCharacters(in: .whitespacesAndNewlines)
                    schemaToRename = nil
                    Task {
                        do {
                            try await schemaViewModel.renameSchema(oldName: oldName, newName: target)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newSchemaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newSchemaName == schema.name)
            }
        }
        .padding(20)
        .frame(width: 380, height: 200)
    }
}
