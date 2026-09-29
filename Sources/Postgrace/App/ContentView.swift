import SwiftUI

/// Main content view dynamically toggling between Connection Hub and the Tabbed Workspace.
struct ContentView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel

    var body: some View {
        @Bindable var connVM = connectionViewModel

        ZStack(alignment: .top) {
            if connectionViewModel.isConnected {
                // Workspace View (Connected)
                NavigationSplitView {
                    SidebarView()
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
                } content: {
                    ContentAreaView()
                        .navigationSplitViewColumnWidth(min: 500, ideal: 750)
                } detail: {
                    VStack {
                        Image(systemName: "info.circle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Inspector")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Active session details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260)
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
