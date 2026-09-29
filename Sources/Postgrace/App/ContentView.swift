import SwiftUI

/// Main content view dynamically toggling between Connection Hub and the Tabbed Workspace.
/// Uses a custom, precision-crafted 2-pane layout (matching the design artifact exactly,
/// free from native macOS NavigationSplitView chrome and translucency).
struct ContentView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel

    var body: some View {
        @Bindable var connVM = connectionViewModel

        ZStack(alignment: .top) {
            if connectionViewModel.isConnected {
                VStack(spacing: 0) {
                    // 1. TOP UNIFIED TITLEBAR (Traffic Lights + DB Switcher + Privilege Badge)
                    WorkspaceToolbarView()

                    // 2. 2-PANE WORKSPACE BODY (220px Sidebar + Edge-to-Edge Document View)
                    HStack(spacing: 0) {
                        SidebarView()
                            .frame(width: 220)

                        // 1px Vertical Divider
                        Rectangle()
                            .fill(PostgraceTheme.border)
                            .frame(width: PostgraceTheme.hairlineBorder)

                        ContentAreaView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    // 3. BOTTOM METRICS STATUS BAR
                    StatusBarView()
                }
                .background(PostgraceTheme.canvas)
            } else {
                // Connection Hub / Launcher (Disconnected)
                ConnectionHubView()
                    .background(PostgraceTheme.canvas)
            }

            // Error banner overlay
            if let error = connectionViewModel.connectionError {
                ErrorBannerView(message: error) {
                    connectionViewModel.connectionError = nil
                }
                .padding(.top, 50)
            }
        }
        .background(
            WindowAccessor { window in
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = false
                window.minSize = NSSize(width: 960, height: 620)
            }
        )
        .ignoresSafeArea()
        .sheet(isPresented: $connVM.showingConnectionForm) {
            ConnectionFormView(connection: nil)
        }
        .sheet(isPresented: $connVM.showingEditForm) {
            ConnectionFormView(connection: connectionViewModel.selectedConnection)
        }
    }
}
