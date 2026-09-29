import SwiftUI

/// Main content view dynamically toggling between Connection Hub and the Tabbed Workspace.
struct ContentView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel

    var body: some View {
        @Bindable var connVM = connectionViewModel

        ZStack(alignment: .top) {
            if connectionViewModel.isConnected {
                // Workspace View (Connected) - Clean 2-pane layout without Inspector
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
                } detail: {
                    ContentAreaView()
                }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        WorkspaceToolbarView()
                    }
                    ToolbarItem(placement: .status) {
                        StatusBarView()
                    }
                }
            } else {
                // Connection Hub / Launcher (Disconnected)
                ConnectionHubView()
            }

            // Error banner overlay
            if let error = connectionViewModel.connectionError {
                ErrorBannerView(message: error) {
                    connectionViewModel.connectionError = nil
                }
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $connVM.showingConnectionForm) {
            ConnectionFormView(connection: nil)
        }
        .sheet(isPresented: $connVM.showingEditForm) {
            ConnectionFormView(connection: connectionViewModel.selectedConnection)
        }
    }
}
