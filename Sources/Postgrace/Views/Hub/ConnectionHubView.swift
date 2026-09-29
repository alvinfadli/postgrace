import SwiftUI

/// Dedicated Connection Hub / Launcher window matching the design artifact.
/// Features a centered card on canvas `#0D0F12`, favorite instances list, specs subtitle, and fast launch.
struct ConnectionHubView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @State private var selectedConnectionId: UUID?
    @State private var searchText: String = ""

    private var filteredConnections: [SavedConnection] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return connectionViewModel.savedConnections }
        return connectionViewModel.savedConnections.filter { conn in
            conn.name.lowercased().contains(trimmed) ||
            conn.host.lowercased().contains(trimmed) ||
            conn.database.lowercased().contains(trimmed) ||
            conn.username.lowercased().contains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            PostgraceTheme.canvas
                .ignoresSafeArea()

            WindowDragArea()
                .ignoresSafeArea()

            // Centered Hub Card (max-w-2xl, background #14171D, border #262C36, rounded-2xl)
            VStack(spacing: 20) {
                // Card Header
                HStack(spacing: 12) {
                    if let imagePath = Bundle.module.path(forResource: "AppIcon", ofType: "png"),
                       let nsImage = NSImage(contentsOfFile: imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 42, height: 42)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: PostgraceTheme.accentSky.opacity(0.3), radius: 8, x: 0, y: 2)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(PostgraceTheme.accentSky)
                                .frame(width: 40, height: 40)
                            Image(systemName: "cylinder.split.1x2")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Postgrace Connection Hub")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Choose or configure a database server")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        connectionViewModel.showingConnectionForm = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("New Server")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(PostgraceTheme.accentSky)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PostgraceTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("n", modifiers: [.command])
                }
                .padding(.bottom, 8)
                .overlay(
                    Rectangle()
                        .fill(PostgraceTheme.border)
                        .frame(height: PostgraceTheme.hairlineBorder),
                    alignment: .bottom
                )

                // Favorite Instances Section
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("FAVORITE INSTANCES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .tracking(0.5)

                        Spacer()

                        // Quick Search Field
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)

                            TextField("Search servers…", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .frame(width: 120)

                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(PostgraceTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                        )
                    }

                    if connectionViewModel.savedConnections.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tray")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No Saved Instances")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Button("Create First Connection") {
                                connectionViewModel.showingConnectionForm = true
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(PostgraceTheme.accentSky)
                        }
                        .frame(maxWidth: .infinity, minHeight: 140)
                    } else if filteredConnections.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No servers match \"\(searchText)\"")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 140)
                    } else {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(filteredConnections) { conn in
                                    instanceCard(conn)
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                    }
                }

                // Card Bottom Action Bar
                HStack {
                    Text("Press ⌘Return to connect immediately")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let selected = activeSelectedConnection {
                        Button {
                            connectTo(selected)
                        } label: {
                            HStack(spacing: 6) {
                                if connectionViewModel.isConnecting {
                                    ProgressView()
                                        .controlSize(.mini)
                                }
                                Text("Open Active Workspace →")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(PostgraceTheme.accentSky)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)
                        .disabled(connectionViewModel.isConnecting)
                    }
                }
                .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: 640)
            .background(PostgraceTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusCard, style: .continuous)
                    .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.standardBorder)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 12)
        }
        .onAppear {
            if selectedConnectionId == nil, let first = connectionViewModel.savedConnections.first {
                selectedConnectionId = first.id
            }
        }
    }

    private var activeSelectedConnection: SavedConnection? {
        filteredConnections.first { $0.id == selectedConnectionId }
            ?? filteredConnections.first
    }

    // MARK: - Instance Card Row

    @ViewBuilder
    private func instanceCard(_ conn: SavedConnection) -> some View {
        let isSelected = selectedConnectionId == conn.id

        HStack(spacing: 12) {
            // Status Dot
            Circle()
                .fill(conn.name.lowercased().contains("prod") ? PostgraceTheme.amberRo : PostgraceTheme.emeraldRw)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(conn.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isSelected ? PostgraceTheme.accentSky : .primary)

                Text("\(conn.host):\(conn.port) / \(conn.database) • user: \(conn.username)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSelected {
                Text("Selected")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(PostgraceTheme.accentSky)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(PostgraceTheme.accentSkyMuted)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? PostgraceTheme.accentSkyMuted.opacity(0.6) : PostgraceTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? PostgraceTheme.accentSky : PostgraceTheme.border, lineWidth: isSelected ? 1.5 : PostgraceTheme.hairlineBorder)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedConnectionId = conn.id
        }
        .onTapGesture(count: 2) {
            selectedConnectionId = conn.id
            connectTo(conn)
        }
        .contextMenu {
            Button("Connect") { connectTo(conn) }
            Divider()
            Button("Duplicate Connection") {
                let copy = connectionViewModel.duplicateConnection(conn)
                selectedConnectionId = copy.id
            }
            Button("Edit") {
                connectionViewModel.selectedConnection = conn
                connectionViewModel.showingEditForm = true
            }
            Divider()
            Button("Delete", role: .destructive) {
                connectionViewModel.deleteConnection(conn)
            }
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
}
