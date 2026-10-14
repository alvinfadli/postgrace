import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Full-Page Connection Hub matching the 3-pane master-detail architecture
/// from the Postgrace Connection Hub Redesign BRD.
///
/// Features:
/// 1. Seamless Integrated macOS Titlebar (`#16181D`) with traffic lights offset, WindowDragArea,
///    global search (`⌘K`), view switcher (cards/table), Import URI (`⌘U`), and New Connection (`⌘N`).
/// 2. Left Filter Sidebar (240px fixed): Environments (Remote locked safe vs Localhost),
///    Engine filters (PostgreSQL, MySQL, MariaDB), and Apple Keychain encrypted footer.
/// 3. Center Master Explorer: Responsive card grid or compact table with live latency pings.
/// 4. Right Collapsible Inspector & Editor (380px): Mode switcher (Inspect vs Edit),
///    subsections (Overview, SSL, SSH Bastion, Guardrails), and zero-modal inline workflow.
public struct FullPageConnectionHubView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel

    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    // Import URI Sheet State
    @State private var isShowingImportSheet: Bool = false
    @State private var backupToastMessage: String? = nil

    private var activeConnections: [SavedConnection] {
        connectionViewModel.filteredConnections(searchText: searchText)
    }

    private var selectedConnection: SavedConnection? {
        if let id = connectionViewModel.selectedConnectionId {
            return connectionViewModel.savedConnections.first { $0.id == id }
        }
        return connectionViewModel.savedConnections.first
    }

    public init() {}

    public var body: some View {
        @Bindable var connVM = connectionViewModel

        ZStack {
            PostgraceTheme.canvas
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 1. Top Integrated Titlebar
                hubTitlebar

                // Hairline Divider
                Rectangle()
                    .fill(PostgraceTheme.border)
                    .frame(height: PostgraceTheme.hairlineBorder)

                // MARK: - 2. 3-Pane Body
                HStack(spacing: 0) {
                    // Left Filter Sidebar (240px)
                    HubSidebarView(searchText: $searchText)
                        .frame(width: 240)

                    Rectangle()
                        .fill(PostgraceTheme.border)
                        .frame(width: PostgraceTheme.hairlineBorder)

                    // Center Master Explorer (Fluid)
                    HubExplorerView(
                        searchText: $searchText,
                        onConnect: { conn in connectTo(conn) }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Right Collapsible Inspector & Editor (380px)
                    if connectionViewModel.isInspectorVisible {
                        Rectangle()
                            .fill(PostgraceTheme.border)
                            .frame(width: PostgraceTheme.hairlineBorder)

                        HubInspectorView(
                            onConnect: { conn in connectTo(conn) }
                        )
                        .frame(width: 380)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }

            // Toast feedback
            if let toast = backupToastMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(PostgraceTheme.emeraldRw)
                        Text(toast)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $isShowingImportSheet) {
            HubImportURISheet { newConn, password in
                connectionViewModel.saveConnection(newConn, password: password)
                connectionViewModel.selectConnection(id: newConn.id)
                Task {
                    await connectionViewModel.runTestPing(for: newConn, password: password)
                }
            } onConnectImmediately: { newConn, password in
                connectionViewModel.saveConnection(newConn, password: password)
                connectTo(newConn)
            }
        }
        .onAppear {
            if connectionViewModel.selectedConnectionId == nil,
               let first = connectionViewModel.savedConnections.first {
                connectionViewModel.selectedConnectionId = first.id
            }
        }
        .onKeyPress(.downArrow) {
            guard connectionViewModel.inspectorMode == .inspect else { return .ignored }
            selectNext()
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard connectionViewModel.inspectorMode == .inspect else { return .ignored }
            selectPrevious()
            return .handled
        }
        .onKeyPress(.return) {
            guard connectionViewModel.inspectorMode == .inspect else { return .ignored }
            guard !connectionViewModel.isConnecting else { return .handled }
            if let target = selectedConnection {
                connectTo(target)
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Titlebar Chrome
    private var hubTitlebar: some View {
        ZStack {
            // Background Window Drag Area
            WindowDragArea()

            HStack(spacing: 12) {
                // Leading Traffic Lights Spacing (76px) + App Logo
                HStack(spacing: 10) {
                    Spacer().frame(width: 68)

                    if let imagePath = Bundle.module.path(forResource: "AppIcon", ofType: "png"),
                       let nsImage = NSImage(contentsOfFile: imagePath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    } else {
                        Image(systemName: "cylinder.split.1x2")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(PostgraceTheme.accentEmerald)
                    }

                    Text("Postgrace")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)

                    Text("Hub")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(PostgraceTheme.accentEmerald)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PostgraceTheme.accentEmeraldMuted)
                        .clipShape(Capsule())
                }

                Spacer()

                // Global Search Bar (⌘K)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    TextField("Search instances, hosts, tags… (⌘K)", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isSearchFocused)
                        .frame(width: 240)

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("⌘K")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(PostgraceTheme.surfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(PostgraceTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )

                Spacer()

                // Trailing Global Actions
                HStack(spacing: 8) {
                    // View Mode Switcher (Cards vs Table)
                    HStack(spacing: 2) {
                        Button {
                            connectionViewModel.viewMode = .cards
                        } label: {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 11))
                                .foregroundColor(connectionViewModel.viewMode == .cards ? PostgraceTheme.accentEmerald : .secondary)
                                .padding(5)
                                .background(connectionViewModel.viewMode == .cards ? PostgraceTheme.surfaceHover : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help("Card Grid View")

                        Button {
                            connectionViewModel.viewMode = .table
                        } label: {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 11))
                                .foregroundColor(connectionViewModel.viewMode == .table ? PostgraceTheme.accentEmerald : .secondary)
                                .padding(5)
                                .background(connectionViewModel.viewMode == .table ? PostgraceTheme.surfaceHover : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help("Compact Table View")
                    }
                    .padding(2)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )

                    // Connection String Button (⌘U)
                    Button {
                        isShowingImportSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 11))
                            Text("Connection String")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(PostgraceTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                        )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("u", modifiers: [.command])
                    .help("Connect using connection string (⌘U)")

                    // + New Connection (⌘N)
                    Button {
                        connectionViewModel.openNewConnectionForm()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("New Connection")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(PostgraceTheme.accentEmerald)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("n", modifiers: [.command])
                    .help("Create new connection (⌘N)")

                    // Inspector Toggle Button (⌘I)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            connectionViewModel.isInspectorVisible.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 12))
                            .foregroundColor(connectionViewModel.isInspectorVisible ? PostgraceTheme.accentEmerald : .secondary)
                            .padding(6)
                            .background(PostgraceTheme.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("i", modifiers: [.command])
                    .help("Toggle Inspector Pane (⌘I)")
                }
                .padding(.trailing, 14)
            }
        }
        .frame(height: 48)
        .background(PostgraceTheme.surface)
    }

    // MARK: - Keyboard Selection Navigation
    private func selectNext() {
        let list = activeConnections
        guard let currentId = connectionViewModel.selectedConnectionId,
              let currentIndex = list.firstIndex(where: { $0.id == currentId }) else {
            connectionViewModel.selectConnection(id: list.first?.id ?? UUID())
            return
        }
        if currentIndex < list.count - 1 {
            connectionViewModel.selectConnection(id: list[currentIndex + 1].id)
        }
    }

    private func selectPrevious() {
        let list = activeConnections
        guard let currentId = connectionViewModel.selectedConnectionId,
              let currentIndex = list.firstIndex(where: { $0.id == currentId }) else {
            connectionViewModel.selectConnection(id: list.first?.id ?? UUID())
            return
        }
        if currentIndex > 0 {
            connectionViewModel.selectConnection(id: list[currentIndex - 1].id)
        }
    }

    private func connectTo(_ connection: SavedConnection) {
        guard !connectionViewModel.isConnecting else { return }
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

// MARK: - Left Filter Sidebar (240px Fixed)
struct HubSidebarView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // WORKSPACE SECTION
                    VStack(alignment: .leading, spacing: 3) {
                        sidebarSectionHeader("WORKSPACE")

                        HubSidebarRowItem(
                            title: "All Instances",
                            icon: "server.rack",
                            count: connectionViewModel.savedConnections.count,
                            isSelected: connectionViewModel.activeGroupFilter == .all && connectionViewModel.activeEngineFilter == nil
                        ) {
                            connectionViewModel.activeGroupFilter = .all
                            connectionViewModel.activeEngineFilter = nil
                        }

                        HubSidebarRowItem(
                            title: "Favorites",
                            icon: "star.fill",
                            iconColor: .yellow,
                            count: connectionViewModel.savedConnections.filter { $0.isFavorite }.count,
                            isSelected: connectionViewModel.activeGroupFilter == .favorites && connectionViewModel.activeEngineFilter == nil
                        ) {
                            connectionViewModel.activeGroupFilter = .favorites
                            connectionViewModel.activeEngineFilter = nil
                        }

                        HubSidebarRowItem(
                            title: "Recent Connects",
                            icon: "clock.arrow.circlepath",
                            count: connectionViewModel.savedConnections.filter { $0.lastConnectedAt != nil }.count,
                            isSelected: connectionViewModel.activeGroupFilter == .recent && connectionViewModel.activeEngineFilter == nil
                        ) {
                            connectionViewModel.activeGroupFilter = .recent
                            connectionViewModel.activeEngineFilter = nil
                        }
                    }

                    // ENVIRONMENTS SECTION
                    VStack(alignment: .leading, spacing: 3) {
                        sidebarSectionHeader("ENVIRONMENTS")

                        // Remote Host Segment (Locked Safe Mode)
                        HubSidebarRowItem(
                            title: "Remote",
                            dotColor: PostgraceTheme.destructiveRed,
                            badge: "LOCKED",
                            count: connectionViewModel.savedConnections.filter { !$0.isLocalhost }.count,
                            isSelected: connectionViewModel.activeGroupFilter == .remote && connectionViewModel.activeEngineFilter == nil
                        ) {
                            connectionViewModel.activeGroupFilter = .remote
                            connectionViewModel.activeEngineFilter = nil
                        }

                        // Localhost Segment
                        HubSidebarRowItem(
                            title: "Localhost",
                            dotColor: PostgraceTheme.emeraldRw,
                            badge: "DEV",
                            count: connectionViewModel.savedConnections.filter { $0.isLocalhost }.count,
                            isSelected: connectionViewModel.activeGroupFilter == .localhost && connectionViewModel.activeEngineFilter == nil
                        ) {
                            connectionViewModel.activeGroupFilter = .localhost
                            connectionViewModel.activeEngineFilter = nil
                        }
                    }

                    // DATABASES SECTION
                    VStack(alignment: .leading, spacing: 3) {
                        sidebarSectionHeader("DATABASES")

                        HubSidebarRowItem(
                            title: "PostgreSQL",
                            icon: DatabaseEngine.postgresql.iconName,
                            count: connectionViewModel.savedConnections.filter { $0.engine == .postgresql }.count,
                            isSelected: connectionViewModel.activeGroupFilter == .postgresql || connectionViewModel.activeEngineFilter == .postgresql
                        ) {
                            connectionViewModel.activeGroupFilter = .postgresql
                            connectionViewModel.activeEngineFilter = nil
                        }

                        HubSidebarRowItem(
                            title: "MySQL",
                            icon: DatabaseEngine.mysql.iconName,
                            count: connectionViewModel.savedConnections.filter { $0.engine == .mysql }.count,
                            isSelected: connectionViewModel.activeGroupFilter == .mysql || connectionViewModel.activeEngineFilter == .mysql
                        ) {
                            connectionViewModel.activeGroupFilter = .mysql
                            connectionViewModel.activeEngineFilter = nil
                        }

                        HubSidebarRowItem(
                            title: "MariaDB",
                            icon: DatabaseEngine.mariadb.iconName,
                            count: connectionViewModel.savedConnections.filter { $0.engine == .mariadb }.count,
                            isSelected: connectionViewModel.activeGroupFilter == .mariadb || connectionViewModel.activeEngineFilter == .mariadb
                        ) {
                            connectionViewModel.activeGroupFilter = .mariadb
                            connectionViewModel.activeEngineFilter = nil
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 14)
            }

            Spacer()

            // SECURITY & KEYCHAIN FOOTER
            sidebarSecurityFooter
        }
        .background(PostgraceTheme.surface)
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
            .tracking(0.6)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }

    private var sidebarSecurityFooter: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder)

            // Keychain Status
            HStack(spacing: 7) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 12))
                    .foregroundColor(PostgraceTheme.accentEmerald)

                Text("Apple Keychain")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Text("ENCRYPTED")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(PostgraceTheme.accentEmerald)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(PostgraceTheme.accentEmeraldMuted)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)

            // Export & Import Settings Buttons
            HStack(spacing: 8) {
                Button {
                    exportBackup()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10))
                        Text("Export")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .buttonStyle(.plain)
                .help("Export all saved connection profiles as JSON backup")

                Button {
                    importBackup()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 10))
                        Text("Import")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .buttonStyle(.plain)
                .help("Import connection profiles from JSON file")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private func exportBackup() {
        guard let data = connectionViewModel.exportBackup() else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        savePanel.nameFieldStringValue = "postgrace-connections-backup.json"
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                try? data.write(to: url)
            }
        }
    }

    private func importBackup() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url, let data = try? Data(contentsOf: url) {
                _ = try? connectionViewModel.importBackup(from: data)
            }
        }
    }
}

// MARK: - Reusable Full-Width Clickable Sidebar Row Item
struct HubSidebarRowItem: View {
    let title: String
    var icon: String? = nil
    var iconColor: Color? = nil
    var dotColor: Color? = nil
    var badge: String? = nil
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let dotColor = dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(iconColor ?? (isSelected ? PostgraceTheme.accentEmerald : .secondary))
                        .frame(width: 16)
                }

                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : (isHovered ? .primary : .secondary))

                if let badge = badge, let dotColor = dotColor {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(dotColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(dotColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                Text("\(count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? PostgraceTheme.accentEmerald : .secondary.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(isSelected ? PostgraceTheme.accentEmeraldMuted : PostgraceTheme.surfaceElevated)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? PostgraceTheme.surfaceElevated : (isHovered ? PostgraceTheme.surfaceHover : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Center Master Explorer
struct HubExplorerView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Binding var searchText: String
    let onConnect: (SavedConnection) -> Void

    private var connections: [SavedConnection] {
        connectionViewModel.filteredConnections(searchText: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Explorer Top Bar
            HStack {
                HStack(spacing: 8) {
                    Text(categoryTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)

                    Text("\(connections.count)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(PostgraceTheme.accentEmerald)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(PostgraceTheme.accentEmeraldMuted)
                        .clipShape(Capsule())
                }

                Spacer()

                // Test All Connections Button
                Button {
                    Task {
                        await connectionViewModel.testAllConnections()
                    }
                } label: {
                    HStack(spacing: 5) {
                        if connectionViewModel.isTestingAll {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10))
                        }
                        Text("Test All Pings")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(PostgraceTheme.accentEmerald)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .buttonStyle(.plain)
                .disabled(connectionViewModel.isTestingAll || connections.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(PostgraceTheme.canvas)

            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder)

            // Content Area (Grid or Table)
            if connections.isEmpty {
                emptyExplorerView
            } else if connectionViewModel.viewMode == .cards {
                cardGridView
            } else {
                HubTableView(
                    connections: connections,
                    onConnect: onConnect
                )
            }
        }
        .background(PostgraceTheme.canvas)
    }

    private var categoryTitle: String {
        if !searchText.isEmpty {
            return "Search Results"
        }
        if let engine = connectionViewModel.activeEngineFilter {
            return "\(engine.rawValue) Instances"
        }
        switch connectionViewModel.activeGroupFilter {
        case .all: return "All Instances"
        case .favorites: return "Favorites"
        case .recent: return "Recent Connects"
        case .remote: return "Remote Instances"
        case .localhost: return "Localhost Instances"
        case .postgresql: return "PostgreSQL Instances"
        case .mysql: return "MySQL Instances"
        case .mariadb: return "MariaDB Instances"
        }
    }

    private var emptyExplorerView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "server.rack")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.4))

            Text("No Database Instances Found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)

            if !searchText.isEmpty {
                Text("No servers match \"\(searchText)\".")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                PostgraceButton("Clear Search", variant: .secondary) {
                    searchText = ""
                }
            } else {
                Text("Get started by adding your first local or cloud database connection.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                PostgraceButton("New Connection", icon: "plus", variant: .primary) {
                    connectionViewModel.openNewConnectionForm()
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cardGridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 14)],
                spacing: 14
            ) {
                ForEach(connections) { conn in
                    HubConnectionCard(
                        connection: conn,
                        onConnect: { onConnect(conn) }
                    )
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Center Explorer Card Item
struct HubConnectionCard: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    let connection: SavedConnection
    let onConnect: () -> Void

    @State private var lastClickTime: Date = .distantPast

    private var isSelected: Bool {
        connectionViewModel.selectedConnectionId == connection.id
    }

    private var health: ConnectionHealth? {
        connectionViewModel.connectionHealthMap[connection.id]
    }

    private var isTesting: Bool {
        connectionViewModel.isTestingMap[connection.id] ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Card Header: Engine badge, Favorite star, Color dot
            HStack(spacing: 6) {
                // Engine pill
                HStack(spacing: 4) {
                    Image(systemName: connection.engine.iconName)
                        .font(.system(size: 10))
                    Text(connection.engine.rawValue)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(PostgraceTheme.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )

                if connection.colorTag != .none {
                    Circle()
                        .fill(connection.colorTag.color)
                        .frame(width: 7, height: 7)
                }

                Spacer()

                // Star Button
                Button {
                    connectionViewModel.toggleFavorite(for: connection)
                } label: {
                    Image(systemName: connection.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundColor(connection.isFavorite ? .yellow : .secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help(connection.isFavorite ? "Unfavorite" : "Favorite")
            }

            // Connection Name & Host
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isSelected ? PostgraceTheme.accentEmerald : .primary)
                    .lineLimit(1)

                Text("\(connection.host):\(connection.port)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Latency / Status & Safe Mode Pills
            HStack(spacing: 6) {
                // Latency pill
                statusPill

                Spacer()

                // Safe Mode Pill
                if connection.isSafeModeLocked {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 8))
                        Text("LOCKED")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(PostgraceTheme.destructiveRed)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(PostgraceTheme.destructiveRedMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                } else if connection.isSafeModeEffective {
                    HStack(spacing: 3) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 8))
                        Text("SAFE")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(PostgraceTheme.emeraldRw)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(PostgraceTheme.emeraldRwMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }

            // Specs Footer
            HStack(spacing: 6) {
                Text("\(connection.database) • \(connection.username)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(1)

                Spacer()

                // Hover Actions
                HStack(spacing: 4) {
                    // Quick ping
                    Button {
                        Task {
                            await connectionViewModel.runTestPing(for: connection)
                        }
                    } label: {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .padding(4)
                            .background(PostgraceTheme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help("Ping test (⌘T)")

                    // Quick connect
                    Button {
                        onConnect()
                    } label: {
                        HStack(spacing: 3) {
                            Text("Connect")
                                .font(.system(size: 10, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(PostgraceTheme.accentEmerald)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(isSelected ? PostgraceTheme.accentEmeraldMuted.opacity(0.4) : PostgraceTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? PostgraceTheme.accentEmerald : PostgraceTheme.border,
                        lineWidth: isSelected ? 1.5 : PostgraceTheme.hairlineBorder)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let now = Date()
            let isDouble = (connectionViewModel.selectedConnectionId == connection.id && now.timeIntervalSince(lastClickTime) < 0.35)
            lastClickTime = now
            connectionViewModel.selectConnection(id: connection.id)
            if isDouble {
                onConnect()
            }
        }
        .contextMenu {
            Button("Connect") { onConnect() }
            Button(connection.isFavorite ? "Unfavorite" : "Favorite") {
                connectionViewModel.toggleFavorite(for: connection)
            }
            Divider()
            Button("Test Ping") {
                Task { await connectionViewModel.runTestPing(for: connection) }
            }
            Button("Edit Connection...") {
                connectionViewModel.openEditConnectionForm(for: connection)
            }
            Button("Duplicate Connection") {
                connectionViewModel.duplicateConnection(connection)
            }
            Divider()
            Button("Copy Sanitized URI") {
                let str = connection.connectionString(includePassword: false)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
            }
            Button("Copy Full URI") {
                let pwd = connectionViewModel.getStoredPassword(for: connection.id) ?? ""
                let str = connection.connectionString(includePassword: true, password: pwd)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
            }
            Divider()
            Button("Delete Connection", role: .destructive) {
                connectionViewModel.deleteConnection(connection)
            }
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if isTesting {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Testing…")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(PostgraceTheme.surface)
            .clipShape(Capsule())
        } else if let h = health {
            if h.isReachable {
                HStack(spacing: 4) {
                    Circle()
                        .fill(PostgraceTheme.accentMint)
                        .frame(width: 5, height: 5)
                    Text("\(h.latencyMs ?? 0)ms")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(PostgraceTheme.accentMint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(PostgraceTheme.accentEmeraldMuted)
                .clipShape(Capsule())
            } else {
                HStack(spacing: 4) {
                    Circle()
                        .fill(PostgraceTheme.destructiveRed)
                        .frame(width: 5, height: 5)
                    Text("Offline")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(PostgraceTheme.destructiveRed)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(PostgraceTheme.destructiveRedMuted)
                .clipShape(Capsule())
                .help(h.errorMessage ?? "Offline")
            }
        } else {
            HStack(spacing: 3) {
                Image(systemName: "circle")
                    .font(.system(size: 6))
                Text("Untested")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.secondary.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(PostgraceTheme.surface)
            .clipShape(Capsule())
        }
    }
}

// MARK: - Center Explorer Compact Table View
struct HubTableView: View {
    let connections: [SavedConnection]
    let onConnect: (SavedConnection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Table Header
            HStack(spacing: 12) {
                Text("STATUS").frame(width: 70, alignment: .leading)
                Text("NAME").frame(width: 140, alignment: .leading)
                Text("ENGINE").frame(width: 80, alignment: .leading)
                Text("HOST & PORT").frame(width: 160, alignment: .leading)
                Text("DATABASE").frame(width: 100, alignment: .leading)
                Text("USER").frame(width: 90, alignment: .leading)
                Text("SAFE MODE").frame(width: 80, alignment: .leading)
                Spacer()
                Text("ACTIONS").frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(PostgraceTheme.surface)

            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder)

            // Table Rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(connections) { conn in
                        HubTableRowView(conn: conn, onConnect: onConnect)
                        Rectangle()
                            .fill(PostgraceTheme.border.opacity(0.5))
                            .frame(height: PostgraceTheme.hairlineBorder)
                    }
                }
            }
        }
    }
}

struct HubTableRowView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    let conn: SavedConnection
    let onConnect: (SavedConnection) -> Void

    @State private var lastClickTime: Date = .distantPast

    private var isSelected: Bool {
        connectionViewModel.selectedConnectionId == conn.id
    }

    private var health: ConnectionHealth? {
        connectionViewModel.connectionHealthMap[conn.id]
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status/Latency
            Group {
                if let h = health {
                    if h.isReachable {
                        Text("\(h.latencyMs ?? 0)ms")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(PostgraceTheme.accentMint)
                    } else {
                        Text("Offline")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(PostgraceTheme.destructiveRed)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 70, alignment: .leading)

            // Name
            Text(conn.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isSelected ? PostgraceTheme.accentEmerald : .primary)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            // Engine
            Text(conn.engine.rawValue)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            // Host & Port
            Text("\(conn.host):\(conn.port)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 160, alignment: .leading)

            // Database
            Text(conn.database)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            // Username
            Text(conn.username)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            // Safe Mode
            Group {
                if conn.isSafeModeLocked {
                    Text("LOCKED")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(PostgraceTheme.destructiveRed)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(PostgraceTheme.destructiveRedMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Text(conn.isSafeModeEffective ? "SAFE" : "OFF")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(conn.isSafeModeEffective ? PostgraceTheme.emeraldRw : .secondary)
                }
            }
            .frame(width: 80, alignment: .leading)

            Spacer()

            // Actions
            HStack(spacing: 6) {
                Button {
                    Task { await connectionViewModel.runTestPing(for: conn) }
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .help("Test Ping")

                Button {
                    onConnect(conn)
                } label: {
                    Text("Connect")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(PostgraceTheme.accentEmerald)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(isSelected ? PostgraceTheme.surfaceElevated : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            let now = Date()
            let isDouble = (connectionViewModel.selectedConnectionId == conn.id && now.timeIntervalSince(lastClickTime) < 0.35)
            lastClickTime = now
            connectionViewModel.selectConnection(id: conn.id)
            if isDouble {
                onConnect(conn)
            }
        }
        .contextMenu {
            Button("Connect") { onConnect(conn) }
            Button(conn.isFavorite ? "Unfavorite" : "Favorite") {
                connectionViewModel.toggleFavorite(for: conn)
            }
            Divider()
            Button("Test Ping") {
                Task { await connectionViewModel.runTestPing(for: conn) }
            }
            Button("Edit Connection...") {
                connectionViewModel.openEditConnectionForm(for: conn)
            }
            Button("Duplicate Connection") {
                connectionViewModel.duplicateConnection(conn)
            }
            Divider()
            Button("Copy Sanitized URI") {
                let str = conn.connectionString(includePassword: false)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
            }
            Button("Copy Full URI") {
                let pwd = connectionViewModel.getStoredPassword(for: conn.id) ?? ""
                let str = conn.connectionString(includePassword: true, password: pwd)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
            }
            Divider()
            Button("Delete Connection", role: .destructive) {
                connectionViewModel.deleteConnection(conn)
            }
        }
    }
}

// MARK: - Right Inspector & Inline Editor Pane (380px)
struct HubInspectorView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    let onConnect: (SavedConnection) -> Void

    private var selectedConnection: SavedConnection? {
        if let id = connectionViewModel.selectedConnectionId {
            return connectionViewModel.savedConnections.first { $0.id == id }
        }
        return connectionViewModel.savedConnections.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Inspector Header
            inspectorHeader

            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder)

            // Body: Inspection Mode vs Edit Mode
            if connectionViewModel.inspectorMode == .inspect {
                if let conn = selectedConnection {
                    HubInspectionDetailView(
                        connection: conn,
                        onConnect: { onConnect(conn) }
                    )
                } else {
                    emptyInspectorPlaceholder
                }
            } else {
                HubEditorFormView()
            }
        }
        .background(PostgraceTheme.surface)
    }

    private var emptyInspectorPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sidebar.right")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No Connection Selected")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            Text("Select an instance from the list to view its configuration, credentials, and diagnostics.")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorHeader: some View {
        HStack {
            if connectionViewModel.inspectorMode == .create {
                Text("New Connection")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
            } else if connectionViewModel.inspectorMode == .edit {
                Text("Edit Configuration")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
            } else {
                Text("Inspector")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
            }

            Spacer()

            if connectionViewModel.inspectorMode != .create && selectedConnection != nil {
                // Segmented Inspect / Edit Switch
                PostgraceSegmentedControl(
                    selection: Binding<HubInspectorMode>(
                        get: { connectionViewModel.inspectorMode },
                        set: { newMode in
                            if newMode == .edit, let conn = selectedConnection {
                                connectionViewModel.startEditingConnection(conn)
                            } else {
                                connectionViewModel.inspectorMode = .inspect
                            }
                        }
                    ),
                    items: [HubInspectorMode.inspect, HubInspectorMode.edit],
                    titleFor: { mode in
                        switch mode {
                        case .inspect: return "Inspect"
                        case .edit: return "Edit"
                        case .create: return "Create"
                        }
                    }
                )
                .frame(width: 140)
            }

            // Close Inspector Button
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    connectionViewModel.isInspectorVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(5)
            }
            .buttonStyle(.plain)
            .help("Close Inspector")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Inspection Mode (Read-Only Diagnostics & Parameter Grid)
struct HubInspectionDetailView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    let connection: SavedConnection
    let onConnect: () -> Void

    @State private var isPasswordRevealed: Bool = false
    @State private var copiedItem: String? = nil

    private var health: ConnectionHealth? {
        connectionViewModel.connectionHealthMap[connection.id]
    }

    private var isTesting: Bool {
        connectionViewModel.isTestingMap[connection.id] ?? false
    }

    private var storedPassword: String {
        connectionViewModel.getStoredPassword(for: connection.id) ?? ""
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Diagnostics Card
                diagnosticsCard

                // Specs Breakdown
                VStack(alignment: .leading, spacing: 10) {
                    Text("CONFIGURATION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.6)

                    specRow(label: "Engine", value: connection.engine.rawValue, icon: connection.engine.iconName)
                    specRow(label: "Host", value: connection.host, copyable: true)
                    specRow(label: "Port", value: "\(connection.port)", copyable: true)
                    specRow(label: "Database", value: connection.database, copyable: true)
                    specRow(label: "Username", value: connection.username, copyable: true)

                    // Password row with Keychain & eye toggle
                    HStack {
                        Text("Password")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Text(isPasswordRevealed ? (storedPassword.isEmpty ? "(none)" : storedPassword) : "••••••••••••")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)

                        Spacer()

                        Button {
                            isPasswordRevealed.toggle()
                        } label: {
                            Image(systemName: isPasswordRevealed ? "eye.slash" : "eye")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isPasswordRevealed ? "Hide Password" : "Show Password")

                        if !storedPassword.isEmpty {
                            copyButton(value: storedPassword, label: "Password")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    specRow(label: "SSL Mode", value: connection.sslMode.displayName)
                }

                // Safe Mode & Guardrails Card
                safeModeCard

                // Connection String Export Box
                connectionStringBox

                // Actions Bottom
                VStack(spacing: 8) {
                    Button {
                        onConnect()
                    } label: {
                        HStack(spacing: 6) {
                            if connectionViewModel.isConnecting {
                                ProgressView().controlSize(.mini)
                            }
                            Text("Connect Now →")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(PostgraceTheme.accentEmerald)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(connectionViewModel.isConnecting)

                    HStack(spacing: 8) {
                        Button("Edit Settings") {
                            connectionViewModel.startEditingConnection(connection)
                        }
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(PostgraceTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6).stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                        )
                        .buttonStyle(.plain)

                        Button("Duplicate") {
                            connectionViewModel.duplicateConnection(connection)
                        }
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(PostgraceTheme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6).stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                        )
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
            .padding(16)
        }
    }

    private var diagnosticsCard: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(health?.isReachable == true ? PostgraceTheme.accentMint : (health != nil ? PostgraceTheme.destructiveRed : Color.secondary))
                        .frame(width: 8, height: 8)

                    Text(health?.isReachable == true ? "Online" : (health != nil ? "Offline" : "Untested"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(health?.isReachable == true ? PostgraceTheme.accentMint : (health != nil ? PostgraceTheme.destructiveRed : .secondary))
                }

                Spacer()

                Button {
                    Task { await connectionViewModel.runTestPing(for: connection) }
                } label: {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.fill").font(.system(size: 9))
                        }
                        Text("Test Connection")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(PostgraceTheme.accentEmerald)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(PostgraceTheme.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5).stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("t", modifiers: [.command])
                .disabled(isTesting)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ROUND TRIP")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(health?.latencyMs != nil ? "\(health!.latencyMs!) ms" : "—")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(health?.latencyMs != nil ? PostgraceTheme.accentMint : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SSL / TLS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(health?.sslCipher ?? (connection.sslMode == .disable ? "Disabled" : "TLS Required"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let err = health?.errorMessage {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(PostgraceTheme.destructiveRed)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PostgraceTheme.destructiveRedMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(12)
        .background(PostgraceTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
        )
    }

    private func specRow(label: String, value: String, icon: String? = nil, copyable: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            HStack(spacing: 4) {
                if let ic = icon {
                    Image(systemName: ic)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Spacer()

            if copyable {
                copyButton(value: value, label: label)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PostgraceTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func copyButton(value: String, label: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copiedItem = label
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedItem == label { copiedItem = nil }
            }
        } label: {
            Image(systemName: copiedItem == label ? "checkmark" : "doc.on.doc")
                .font(.system(size: 10))
                .foregroundColor(copiedItem == label ? PostgraceTheme.emeraldRw : .secondary)
        }
        .buttonStyle(.plain)
        .help("Copy \(label)")
    }

    private var safeModeCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: connection.isSafeModeLocked ? "lock.shield.fill" : "shield.fill")
                    .font(.system(size: 12))
                    .foregroundColor(connection.isSafeModeLocked ? PostgraceTheme.destructiveRed : PostgraceTheme.emeraldRw)

                Text(connection.isSafeModeLocked ? "Safe Mode: Enforced (Remote Host)" : "Localhost Guardrails")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
            }

            Text(connection.isSafeModeLocked
                 ? "Remote host detected. Destructive commands (DROP, TRUNCATE, unbounded UPDATE/DELETE) are strictly guarded."
                 : "Local development server. Guardrails can be toggled on or off.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            if !connection.isSafeModeLocked {
                PostgraceToggle("Enable Safe Mode on Localhost", isOn: Binding(
                    get: { connection.isSafeModeEffective },
                    set: { _ in connectionViewModel.toggleSafeMode() }
                ))
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(connection.isSafeModeLocked ? PostgraceTheme.destructiveRedMuted.opacity(0.3) : PostgraceTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
        )
    }

    private var connectionStringBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONNECTION STRING")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.6)

            Text(connection.connectionString(includePassword: false))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PostgraceTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            HStack(spacing: 8) {
                Button("Copy Sanitized") {
                    let str = connection.connectionString(includePassword: false)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(str, forType: .string)
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered)

                Button("Copy Full URI") {
                    let str = connection.connectionString(includePassword: true, password: storedPassword)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(str, forType: .string)
                }
                .font(.system(size: 10))
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Edit & Create Inline Editor Form
struct HubEditorFormView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel

    @State private var engine: DatabaseEngine = .postgresql
    @State private var name: String = ""
    @State private var host: String = "localhost"
    @State private var port: String = "5432"
    @State private var username: String = "postgres"
    @State private var database: String = "postgres"
    @State private var password: String = ""
    @State private var sslMode: SSLMode = .disable
    @State private var colorTag: ConnectionColor = .none
    @State private var isSafeModeEnabled: Bool = false
    @State private var isSSHActive: Bool = false
    @State private var sshHost: String = ""
    @State private var sshPort: String = "22"
    @State private var sshUser: String = ""
    @State private var sshKeyPath: String = ""
    @State private var caCertPath: String = ""

    @State private var connectionMethod: ConnectionInputMode = .parameters
    @State private var connectionStringInput: String = ""

    @State private var activeTab: EditorTab = .overview
    @State private var isTesting = false
    @State private var testOutcome: String? = nil
    @State private var isOutcomeSuccess = false

    enum EditorTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case security = "SSL & TLS"
        case ssh = "SSH Tunnel"
        case guardrails = "Guardrails"
        var id: String { rawValue }
    }

    private var isLocalhost: Bool {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return h == "localhost" || h == "127.0.0.1" || h == "::1" || h.hasSuffix(".local")
    }

    private var parsedConnectionString: (connection: SavedConnection, password: String)? {
        SavedConnection.parse(connectionString: connectionStringInput)
    }

    private var effectivePassword: String {
        if connectionMethod == .connectionString, let p = parsedConnectionString, !p.password.isEmpty {
            return p.password
        }
        return password
    }

    private var isValid: Bool {
        if connectionMethod == .connectionString {
            return parsedConnectionString != nil
        }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !host.trimmingCharacters(in: .whitespaces).isEmpty &&
            !username.trimmingCharacters(in: .whitespaces).isEmpty &&
            (Int(port) ?? 0) > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Form Sub-tabs
            PostgraceSegmentedControl(
                selection: $activeTab,
                items: EditorTab.allCases,
                titleFor: { $0.rawValue }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder)

            // Form Tab Body
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch activeTab {
                    case .overview:
                        overviewSection
                    case .security:
                        securitySection
                    case .ssh:
                        sshSection
                    case .guardrails:
                        guardrailsSection
                    }
                }
                .padding(16)
            }

            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder)

            // Test Feedback
            if let outcome = testOutcome {
                HStack(spacing: 6) {
                    Image(systemName: isOutcomeSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isOutcomeSuccess ? PostgraceTheme.emeraldRw : PostgraceTheme.destructiveRed)
                    Text(outcome)
                        .font(.system(size: 11))
                        .foregroundColor(isOutcomeSuccess ? PostgraceTheme.emeraldRw : PostgraceTheme.destructiveRed)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(PostgraceTheme.surfaceElevated)
            }

            // Bottom Buttons
            HStack(spacing: 10) {
                PostgraceButton(
                    "Test",
                    icon: "bolt.fill",
                    variant: .secondary,
                    isLoading: isTesting
                ) {
                    runTest()
                }
                .disabled(isTesting || !isValid)

                Spacer()

                PostgraceButton("Cancel", variant: .secondary) {
                    if connectionViewModel.savedConnections.isEmpty {
                        connectionViewModel.openNewConnectionForm()
                    } else {
                        connectionViewModel.inspectorMode = .inspect
                    }
                }

                PostgraceButton("Save", variant: .primary) {
                    save()
                }
                .disabled(!isValid)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear {
            loadDraft()
        }
        .onChange(of: connectionViewModel.draftConnection?.id) { _, _ in
            loadDraft()
        }
        .onChange(of: connectionViewModel.inspectorMode) { _, _ in
            loadDraft()
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Engine Selector
            VStack(alignment: .leading, spacing: 4) {
                Text("ENGINE").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                PostgraceSegmentedControl(
                    selection: $engine,
                    items: DatabaseEngine.allCases,
                    titleFor: { $0.rawValue },
                    iconFor: { $0.iconName }
                )
                .onChange(of: engine) { _, newEngine in
                    if port == "5432" || port == "3306" {
                        port = "\(newEngine.defaultPort)"
                    }
                    if database == "postgres" || database == "mysql" {
                        database = newEngine.defaultDatabase
                    }
                    if username == "postgres" || username == "root" {
                        username = newEngine.defaultUsername
                    }
                    if connectionMethod == .connectionString && connectionStringInput.isEmpty {
                        let temp = buildConnection()
                        connectionStringInput = temp.connectionString(includePassword: true, password: effectivePassword)
                    }
                }
            }

            // Connection Method (Parameters vs Connection String)
            VStack(alignment: .leading, spacing: 4) {
                Text("CONNECTION METHOD").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                PostgraceSegmentedControl(
                    selection: $connectionMethod,
                    items: ConnectionInputMode.allCases,
                    titleFor: { $0.rawValue },
                    iconFor: { $0.iconName }
                )
                .onChange(of: connectionMethod) { oldVal, newVal in
                    if newVal == .connectionString {
                        if connectionStringInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let temp = buildConnection()
                            connectionStringInput = temp.connectionString(includePassword: true, password: effectivePassword)
                        }
                    } else if oldVal == .connectionString {
                        if let p = parsedConnectionString {
                            applyParsedConnection(p.connection, pwd: p.password)
                        }
                    }
                }
            }

            if connectionMethod == .connectionString {
                // Connection String Input View
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("CONNECTION STRING (URI OR KEY-VALUE)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Paste") {
                            if let clip = NSPasteboard.general.string(forType: .string) {
                                connectionStringInput = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                parseAndApplyConnectionString(connectionStringInput)
                            }
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                    }

                    TextEditor(text: $connectionStringInput)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 72)
                        .padding(6)
                        .background(PostgraceTheme.canvas)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                        )
                        .onChange(of: connectionStringInput) { _, newVal in
                            parseAndApplyConnectionString(newVal)
                        }

                    if let p = parsedConnectionString {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(PostgraceTheme.emeraldRw)
                                Text("Valid \(p.connection.engine.rawValue) Connection String")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(PostgraceTheme.emeraldRw)
                                Spacer()
                                Text(p.connection.sslMode.displayName)
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(PostgraceTheme.surfaceElevated)
                                    .clipShape(Capsule())
                            }

                            Divider().padding(.vertical, 2)

                            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                                GridRow {
                                    Text("Host:").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                                    Text("\(p.connection.host):\(p.connection.port)").font(.system(size: 10, design: .monospaced))
                                }
                                GridRow {
                                    Text("Database:").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                                    Text(p.connection.database).font(.system(size: 10, design: .monospaced))
                                }
                                GridRow {
                                    Text("User:").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                                    Text(p.connection.username).font(.system(size: 10, design: .monospaced))
                                }
                            }
                        }
                        .padding(8)
                        .background(PostgraceTheme.accentEmeraldMuted.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if !connectionStringInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Invalid format. Examples:\n• postgresql://user:password@host:5432/dbname?sslmode=require\n• host=localhost port=5432 dbname=mydb user=postgres password=secret")
                            .font(.system(size: 10))
                            .foregroundColor(PostgraceTheme.destructiveRed)
                    } else {
                        Text("Example: postgresql://postgres:password@localhost:5432/postgres?sslmode=disable")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("NAME").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    TextField(parsedConnectionString?.connection.name ?? "e.g. Production Replica", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // Color Tag
                VStack(alignment: .leading, spacing: 4) {
                    Text("COLOR TAG").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    Picker("", selection: $colorTag) {
                        Text("None").tag(ConnectionColor.none)
                        Text("Red (Production)").tag(ConnectionColor.red)
                        Text("Blue (Staging)").tag(ConnectionColor.blue)
                        Text("Green (Local)").tag(ConnectionColor.green)
                        Text("Orange").tag(ConnectionColor.orange)
                        Text("Purple").tag(ConnectionColor.purple)
                    }
                }
            } else {
                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("NAME").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    TextField("e.g. Production Replica", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                // Host & Port
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("HOST").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                        TextField("localhost", text: $host)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PORT").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                        TextField("5432", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }

                // Database
                VStack(alignment: .leading, spacing: 4) {
                    Text("DEFAULT DATABASE").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    TextField("postgres", text: $database)
                        .textFieldStyle(.roundedBorder)
                }

                // Username
                VStack(alignment: .leading, spacing: 4) {
                    Text("USERNAME").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    TextField("postgres", text: $username)
                        .textFieldStyle(.roundedBorder)
                }

                // Password
                VStack(alignment: .leading, spacing: 4) {
                    Text("PASSWORD").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    PostgraceSecureField("Stored safely in Apple Keychain", text: $password, icon: nil)
                }

                // Color Tag
                VStack(alignment: .leading, spacing: 4) {
                    Text("COLOR TAG").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    Picker("", selection: $colorTag) {
                        Text("None").tag(ConnectionColor.none)
                        Text("Red (Production)").tag(ConnectionColor.red)
                        Text("Blue (Staging)").tag(ConnectionColor.blue)
                        Text("Green (Local)").tag(ConnectionColor.green)
                        Text("Orange").tag(ConnectionColor.orange)
                        Text("Purple").tag(ConnectionColor.purple)
                    }
                }
            }
        }
    }

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SSL / TLS MODE").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                Picker("", selection: $sslMode) {
                    ForEach(SSLMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("CUSTOM CA CERTIFICATE PATH").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                HStack {
                    TextField("/path/to/ca.crt", text: $caCertPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse…") {
                        let openPanel = NSOpenPanel()
                        openPanel.allowsMultipleSelection = false
                        openPanel.begin { res in
                            if res == .OK, let url = openPanel.url {
                                caCertPath = url.path
                            }
                        }
                    }
                }
            }
        }
    }

    private var sshSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PostgraceToggle("Enable SSH Bastion Tunnel", isOn: $isSSHActive)

            if isSSHActive {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(PostgraceTheme.amberRo)
                    Text("SSH Bastion Tunneling is in technical preview. Direct socket connections will be used by the active driver until local port forwarding is enabled.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(PostgraceTheme.amberRo.opacity(0.1))
                .cornerRadius(6)

                VStack(alignment: .leading, spacing: 4) {
                    Text("SSH HOST").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    TextField("bastion.example.com", text: $sshHost)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SSH USER").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                        TextField("ubuntu", text: $sshUser)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SSH PORT").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                        TextField("22", text: $sshPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("PRIVATE KEY FILE").font(.system(size: 9, weight: .bold)).foregroundColor(.secondary)
                    HStack {
                        TextField("~/.ssh/id_rsa", text: $sshKeyPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse…") {
                            let openPanel = NSOpenPanel()
                            openPanel.allowsMultipleSelection = false
                            openPanel.begin { res in
                                if res == .OK, let url = openPanel.url {
                                    sshKeyPath = url.path
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var guardrailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLocalhost {
                PostgraceToggle("Enable Safe Mode on Localhost", isOn: $isSafeModeEnabled)

                Text("When active, Postgrace will prompt for confirmation before executing DROP, TRUNCATE, or unbounded UPDATE / DELETE.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(PostgraceTheme.destructiveRed)
                    Text("Safe Mode Enforced (Locked ON)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(PostgraceTheme.destructiveRed)
                }
                Text("Remote database host detected (\(host)). To prevent accidental data loss in production, Safe Mode is permanently locked.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func parseAndApplyConnectionString(_ raw: String) {
        if let (parsedConn, parsedPassword) = SavedConnection.parse(connectionString: raw) {
            applyParsedConnection(parsedConn, pwd: parsedPassword)
        }
    }

    private func applyParsedConnection(_ parsedConn: SavedConnection, pwd: String) {
        engine = parsedConn.engine
        host = parsedConn.host
        port = "\(parsedConn.port)"
        username = parsedConn.username
        database = parsedConn.database
        sslMode = parsedConn.sslMode
        if !pwd.isEmpty {
            password = pwd
        }
        if let ca = parsedConn.caCertPath, !ca.isEmpty {
            caCertPath = ca
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty || name.contains(" on ") {
            name = parsedConn.name
        }
    }

    private func loadDraft() {
        if let draft = connectionViewModel.draftConnection {
            engine = draft.engine
            name = draft.name
            host = draft.host
            port = "\(draft.port)"
            username = draft.username
            database = draft.database
            sslMode = draft.sslMode
            colorTag = draft.colorTag
            isSafeModeEnabled = draft.isSafeModeEffective
            password = connectionViewModel.draftPassword
            isSSHActive = draft.sshEnabled ?? false
            sshHost = draft.sshHost ?? ""
            sshPort = "\(draft.sshPort ?? 22)"
            sshUser = draft.sshUser ?? ""
            sshKeyPath = draft.sshKeyPath ?? ""
            caCertPath = draft.caCertPath ?? ""
            connectionStringInput = draft.connectionString(includePassword: true, password: password)
        }
    }

    private func buildConnection() -> SavedConnection {
        let currentId = (connectionViewModel.inspectorMode == .edit ? connectionViewModel.draftConnection?.id : nil) ?? UUID()
        let sPort = Int(sshPort.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 22

        if connectionMethod == .connectionString, let p = parsedConnectionString {
            let connName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? p.connection.name : name.trimmingCharacters(in: .whitespacesAndNewlines)
            return SavedConnection(
                id: currentId,
                name: connName,
                engine: p.connection.engine,
                host: p.connection.host,
                port: p.connection.port,
                username: p.connection.username,
                database: p.connection.database,
                sslMode: p.connection.sslMode,
                colorTag: colorTag,
                isSafeModeEnabled: p.connection.isSafeModeLocked ? true : isSafeModeEnabled,
                isFavorite: connectionViewModel.draftConnection?.isFavorite ?? false,
                sshHost: isSSHActive ? sshHost.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                sshPort: isSSHActive ? sPort : nil,
                sshUser: isSSHActive ? sshUser.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                sshKeyPath: isSSHActive ? sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                caCertPath: caCertPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? p.connection.caCertPath : caCertPath.trimmingCharacters(in: .whitespacesAndNewlines),
                sshEnabled: isSSHActive
            )
        }

        let p = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? engine.defaultPort
        return SavedConnection(
            id: currentId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            engine: engine,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: p,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            database: database.trimmingCharacters(in: .whitespacesAndNewlines),
            sslMode: sslMode,
            colorTag: colorTag,
            isSafeModeEnabled: isLocalhost ? isSafeModeEnabled : true,
            isFavorite: connectionViewModel.draftConnection?.isFavorite ?? false,
            sshHost: isSSHActive ? sshHost.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            sshPort: isSSHActive ? sPort : nil,
            sshUser: isSSHActive ? sshUser.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            sshKeyPath: isSSHActive ? sshKeyPath.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            caCertPath: caCertPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : caCertPath.trimmingCharacters(in: .whitespacesAndNewlines),
            sshEnabled: isSSHActive
        )
    }

    private func runTest() {
        isTesting = true
        testOutcome = nil
        Task {
            let conn = buildConnection()
            let cleanPassword = effectivePassword.trimmingCharacters(in: .newlines)
            let success = await connectionViewModel.testConnection(conn, password: cleanPassword)
            isOutcomeSuccess = success
            testOutcome = success ? "Connection successful!" : (connectionViewModel.connectionError ?? "Connection failed.")
            isTesting = false
        }
    }

    private func save() {
        let conn = buildConnection()
        let cleanPassword = effectivePassword.trimmingCharacters(in: .newlines)
        connectionViewModel.saveConnection(conn, password: cleanPassword)
        connectionViewModel.selectConnection(id: conn.id)
    }
}

// MARK: - Connection String Modal Sheet (⌘U)
struct HubImportURISheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (SavedConnection, String) -> Void
    let onConnectImmediately: (SavedConnection, String) -> Void

    @State private var uriText: String = ""

    private var parsed: (connection: SavedConnection, password: String)? {
        SavedConnection.parse(connectionString: uriText)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 18))
                    .foregroundColor(PostgraceTheme.accentEmerald)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect via Connection String")
                        .font(.system(size: 14, weight: .bold))
                    Text("Paste a PostgreSQL, MySQL, or MariaDB connection string (URI or key-value format).")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(18)
            .background(PostgraceTheme.surface)

            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder)

            // Input Text Field
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("CONNECTION STRING (URI OR KEY-VALUE)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Paste") {
                        if let clip = NSPasteboard.general.string(forType: .string) {
                            uriText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.borderless)
                }

                TextEditor(text: $uriText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 70)
                    .padding(6)
                    .background(PostgraceTheme.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                    )

                // Live Preview Card
                if let p = parsed {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("DETECTED PARAMETERS")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(PostgraceTheme.accentEmerald)
                            Spacer()
                            Text(p.connection.sslMode.displayName)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(PostgraceTheme.surfaceElevated)
                                .clipShape(Capsule())
                        }

                        HStack {
                            Text("Engine: \(p.connection.engine.rawValue)").bold()
                            Spacer()
                            Text("Host: \(p.connection.host):\(p.connection.port)")
                        }
                        .font(.system(size: 11))

                        HStack {
                            Text("Database: \(p.connection.database)")
                            Spacer()
                            Text("User: \(p.connection.username)")
                        }
                        .font(.system(size: 11))
                    }
                    .padding(10)
                    .background(PostgraceTheme.accentEmeraldMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if !uriText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Invalid format. Examples:\n• postgresql://user:password@host:5432/database?sslmode=require\n• host=localhost port=5432 dbname=mydb user=postgres password=secret")
                        .font(.system(size: 10))
                        .foregroundColor(PostgraceTheme.destructiveRed)
                }
            }
            .padding(18)

            Spacer()

            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder)

            // Bottom Actions
            HStack(spacing: 10) {
                PostgraceButton("Cancel", variant: .secondary) {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Spacer()

                if let p = parsed {
                    PostgraceButton("Save Profile", variant: .secondary) {
                        onSave(p.connection, p.password)
                        dismiss()
                    }

                    PostgraceButton("Connect", variant: .primary) {
                        onConnectImmediately(p.connection, p.password)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
            .background(PostgraceTheme.surface)
        }
        .frame(width: 520, height: 350)
    }
}
