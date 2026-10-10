import SwiftUI

/// Main content view dynamically toggling between Connection Hub and the Tabbed Workspace.
/// Uses a custom, precision-crafted 2-pane layout (matching the design artifact exactly,
/// free from native macOS NavigationSplitView chrome and translucency).
struct ContentView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(ExportViewModel.self) private var exportViewModel
    @Environment(ImportViewModel.self) private var importViewModel

    var body: some View {
        @Bindable var connVM = connectionViewModel
        @Bindable var exportVM = exportViewModel
        @Bindable var importVM = importViewModel

        ZStack(alignment: .top) {
            if connectionViewModel.isConnected {
                VStack(spacing: 0) {
                    // 1. TOP UNIFIED TITLEBAR (Traffic Lights + DB Switcher + Privilege Badge)
                    WorkspaceToolbarView()

                    // 2. 2-PANE WORKSPACE BODY (240px Sidebar + Edge-to-Edge Document View)
                    HStack(spacing: 0) {
                        SidebarView()
                            .frame(width: 240)

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
                .transition(.opacity)
            } else {
                // Full-Page Connection Hub (Disconnected)
                FullPageConnectionHubView()
                    .background(PostgraceTheme.canvas)
                    .transition(.opacity)
            }

            // Error banner overlay
            if let error = connectionViewModel.connectionError {
                ErrorBannerView(message: error) {
                    connectionViewModel.connectionError = nil
                }
                .padding(.top, 50)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: connectionViewModel.isConnected)
        .background(
            WindowAccessor { window in
                window.appearance = NSAppearance(named: .darkAqua)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = false
                window.minSize = NSSize(width: 960, height: 620)
            }
        )
        .ignoresSafeArea()
        .sheet(isPresented: Binding(
            get: { connVM.isConnected && connVM.showingConnectionForm },
            set: { connVM.showingConnectionForm = $0 }
        )) {
            ConnectionFormView(connection: nil)
        }
        .sheet(isPresented: Binding(
            get: { connVM.isConnected && connVM.showingEditForm },
            set: { connVM.showingEditForm = $0 }
        )) {
            ConnectionFormView(connection: connectionViewModel.connectionToEdit)
        }
        .sheet(isPresented: $exportVM.isShowingSheet) {
            ExportSheet()
        }
        .sheet(isPresented: $importVM.isShowingSheet) {
            ImportSheet()
        }
    }
}
