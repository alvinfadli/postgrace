import SwiftUI

/// Main content view with a three-column NavigationSplitView layout.
struct ContentView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel

    var body: some View {
        ZStack(alignment: .top) {
            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 250)
            } content: {
                ContentAreaView()
                    .navigationSplitViewColumnWidth(min: 400, ideal: 600)
            } detail: {
                VStack {
                    Image(systemName: "info.circle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Inspector")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("Coming in v1.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
            }
            .toolbar {
                ToolbarItem(placement: .status) {
                    StatusBarView()
                }
            }

            // Error banner overlay
            if let error = connectionViewModel.connectionError {
                ErrorBannerView(message: error) {
                    connectionViewModel.connectionError = nil
                }
                .padding(.top, 8)
            }
        }
    }
}
