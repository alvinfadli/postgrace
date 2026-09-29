import SwiftUI

/// Dedicated Connection Hub / Launcher window (Sequel Ace style).
struct ConnectionHubView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @State private var selectedConnectionId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Hub Header
            HStack(spacing: 12) {
                Image(systemName: "cylinder.split.1x2.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Postgrace")
                        .font(.title2.bold())
                    Text("Select a database connection to open a workspace")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    connectionViewModel.showingConnectionForm = true
                } label: {
                    Label("New Connection", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 2-Pane Hub Layout
            HSplitView {
                // Left pane: Favorites list
                VStack(spacing: 0) {
                    if connectionViewModel.savedConnections.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "tray")
                                .font(.system(size: 36))
                                .foregroundColor(.secondary)
                            Text("No Saved Connections")
                                .font(.headline)
                            Text("Click '+ New Connection' or ⌘N to configure your first PostgreSQL server.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            Button("Create Connection") {
                                connectionViewModel.showingConnectionForm = true
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 4)
                            Spacer()
                        }
                    } else {
                        List(selection: $selectedConnectionId) {
                            Section("Saved Connections") {
                                ForEach(connectionViewModel.savedConnections) { conn in
                                    ConnectionHubRow(connection: conn)
                                        .tag(conn.id)
                                        .onTapGesture(count: 2) {
                                            connectTo(conn)
                                        }
                                        .contextMenu {
                                            Button("Connect") { connectTo(conn) }
                                            Divider()
                                            Button("Edit") {
                                                connectionViewModel.selectedConnection = conn
                                                connectionViewModel.showingEditForm = true
                                            }
                                            Button("Delete", role: .destructive) {
                                                connectionViewModel.deleteConnection(conn)
                                            }
                                        }
                                }
                            }
                        }
                        .listStyle(.inset)
                    }
                }
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

                // Right pane: Connection details & Connect button
                VStack(spacing: 0) {
                    if let selected = activeSelectedConnection {
                        connectionDetailsView(selected)
                    } else {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "cursorarrow.click.2")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Select a Connection")
                                .font(.title3)
                                .foregroundColor(.secondary)
                            Text("Choose a connection from the list on the left to review settings and launch.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
                .frame(minWidth: 400, maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .onAppear {
            if selectedConnectionId == nil, let first = connectionViewModel.savedConnections.first {
                selectedConnectionId = first.id
            }
        }
    }

    private var activeSelectedConnection: SavedConnection? {
        connectionViewModel.savedConnections.first { $0.id == selectedConnectionId }
    }

    @ViewBuilder
    private func connectionDetailsView(_ conn: SavedConnection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Title & tag
            HStack {
                Circle()
                    .fill(tagColor(conn.colorTag))
                    .frame(width: 14, height: 14)
                Text(conn.name)
                    .font(.title2.bold())
                Spacer()
                Button("Edit") {
                    connectionViewModel.selectedConnection = conn
                    connectionViewModel.showingEditForm = true
                }
            }
            .padding(.horizontal)
            .padding(.top, 20)

            Divider()

            // Key parameters grid
            VStack(alignment: .leading, spacing: 12) {
                Text("Connection Details")
                    .font(.subheadline.bold())
                    .foregroundColor(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        Text("Host:")
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text(conn.host)
                            .font(.system(.body, design: .monospaced))
                    }
                    GridRow {
                        Text("Port:")
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text("\(conn.port)")
                            .font(.system(.body, design: .monospaced))
                    }
                    GridRow {
                        Text("Database:")
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text(conn.database)
                            .font(.system(.body, design: .monospaced))
                    }
                    GridRow {
                        Text("Username:")
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text(conn.username)
                            .font(.system(.body, design: .monospaced))
                    }
                    GridRow {
                        Text("SSL Mode:")
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text(conn.sslMode.rawValue.capitalized)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                .font(.callout)
            }
            .padding(.horizontal)

            Spacer()

            Divider()

            // Launch Bar
            HStack {
                if connectionViewModel.isConnecting {
                    ProgressView()
                        .controlSize(.small)
                    Text("Connecting to \(conn.name)…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    connectTo(conn)
                } label: {
                    HStack(spacing: 8) {
                        Text("Connect & Open Workspace")
                            .fontWeight(.semibold)
                        Image(systemName: "arrow.right")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(connectionViewModel.isConnecting)
            }
            .padding()
        }
    }

    private func connectTo(_ connection: SavedConnection) {
        Task {
            await connectionViewModel.connect(to: connection)
            if connectionViewModel.isConnected {
                await schemaViewModel.refresh()
                let databases = await schemaViewModel.loadAvailableDatabases()
                connectionViewModel.availableDatabases = databases
            }
        }
    }

    private func tagColor(_ tag: ConnectionColor) -> Color {
        switch tag {
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .none: return .gray.opacity(0.4)
        }
    }
}

/// A single row inside the Connection Hub.
struct ConnectionHubRow: View {
    let connection: SavedConnection

    private var tagColor: Color {
        switch connection.colorTag {
        case .red: return .red
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .none: return .gray.opacity(0.4)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tagColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.body)
                    .fontWeight(.medium)
                Text("\(connection.host):\(connection.port)/\(connection.database)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
