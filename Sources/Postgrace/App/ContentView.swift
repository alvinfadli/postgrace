import SwiftUI

/// Main content view dynamically toggling between Connection Hub and the Tabbed Workspace.
/// Uses a custom, precision-crafted 2-pane layout (matching the design artifact exactly,
/// free from native macOS NavigationSplitView chrome and translucency).
struct ContentView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(ExportViewModel.self) private var exportViewModel
    @Environment(ImportViewModel.self) private var importViewModel
    @Environment(ZoomManager.self) private var zoomManager

    var body: some View {
        @Bindable var connVM = connectionViewModel
        @Bindable var exportVM = exportViewModel
        @Bindable var importVM = importViewModel

        ZStack(alignment: .top) {
            GeometryReader { proxy in
                let scale = zoomManager.scale
                let safeW = max(1, proxy.size.width)
                let safeH = max(1, proxy.size.height)
                let layoutW = safeW / scale
                let layoutH = safeH / scale

                Group {
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
                }
                .frame(width: layoutW, height: layoutH)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: safeW, height: safeH, alignment: .topLeading)
                .clipped()
            }

            // Error banner overlay
            if let error = connectionViewModel.connectionError {
                ErrorBannerView(message: error) {
                    connectionViewModel.connectionError = nil
                }
                .padding(.top, 50)
            }

            // Floating Zoom Indicator HUD Toast
            if zoomManager.showZoomToast {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Zoom \(zoomManager.zoomPercentageString)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.85))
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
                )
                .padding(.top, 52)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: connectionViewModel.isConnected)
        .animation(.easeInOut(duration: 0.15), value: zoomManager.scale)
        .animation(.easeInOut(duration: 0.15), value: zoomManager.showZoomToast)
        .background(
            Group {
                // Background shortcut catches for ⌘= and fallback keys
                Button("") { zoomManager.zoomIn() }
                    .keyboardShortcut("=", modifiers: .command)
                Button("") { zoomManager.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("") { zoomManager.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("") { zoomManager.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
        )
        .background(
            WindowAccessor { window in
                window.appearance = nil
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
