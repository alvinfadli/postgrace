import SwiftUI

/// Unified macOS toolbar header featuring the In-Connection Database Switcher and breadcrumbs.
struct WorkspaceToolbarView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @Environment(WorkspaceTabViewModel.self) private var tabViewModel
    @State private var showingDbMenu = false

    var body: some View {
        HStack(spacing: 8) {
            // Server indicator
            if let conn = connectionViewModel.selectedConnection {
                HStack(spacing: 5) {
                    Circle()
                        .fill(tagColor(conn.colorTag))
                        .frame(width: 8, height: 8)
                    Text(conn.name)
                        .font(.caption.bold())
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("/")
                    .foregroundColor(.secondary)
                    .font(.caption)

                // DATABASE SWITCHER DROPDOWN (⌘⇧D)
                Menu {
                    Section("Switch Database") {
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

                    Button("Refresh Database List") {
                        Task {
                            // Introspect schemas and databases
                            await schemaViewModel.loadSchemas()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cylinder.split.1x2")
                            .foregroundColor(.accentColor)
                        Text(conn.database)
                            .font(.caption.bold())
                        if connectionViewModel.isSwitchingDatabase {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .help("Switch Database (⌘⇧D)")

                // Active Schema / Table context
                // Active Schema / Table context
                if let activeTab = tabViewModel.activeTab {
                    Text("/")
                        .foregroundColor(.secondary)
                        .font(.caption)

                    switch activeTab.type {
                    case .table(let schema, let table):
                        Text(schema)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("/")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text(table)
                            .font(.caption.bold())
                    case .query(_, let title):
                        Label(title, systemImage: "bolt.fill")
                            .font(.caption.bold())
                            .foregroundColor(.accentColor)
                    case .structure(let schema, let table):
                        Label("\(schema).\(table) Structure", systemImage: "list.bullet.rectangle")
                            .font(.caption.bold())
                    case .schemas:
                        Label("Schemas", systemImage: "square.3.layers.3d")
                            .font(.caption.bold())
                    case .tables(let schema):
                        Text(schema)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("/")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Label("Tables", systemImage: "tablecells")
                            .font(.caption.bold())
                    }
                }
            }

            Spacer()

            // User Privilege & Role Indicator
            UserPrivilegeBadgeView()

            // Disconnect Button
            Button {
                Task {
                    await connectionViewModel.disconnect()
                }
            } label: {
                Label("Disconnect", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .help("Disconnect from Server")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func tagColor(_ tag: ConnectionColor) -> Color {
        switch tag {
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .none: return .gray
        }
    }
}
