import SwiftUI

public struct StatusBarView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(QueryViewModel.self) private var queryViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @Environment(ZoomManager.self) private var zoomManager

    public init() {}
    
    public var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionViewModel.isConnected ? PostgraceTheme.emeraldRw : PostgraceTheme.destructiveRed)
                .frame(width: 7, height: 7)
            
            Text(connectionViewModel.isConnected ? "Connected" : "Disconnected")
                .font(.caption)
            
            if connectionViewModel.isConnected, let conn = connectionViewModel.selectedConnection {
                Text("/")
                    .font(.caption.bold())
                    .foregroundColor(PostgraceTheme.border)
                Text(conn.database)
                    .font(.caption.bold())
                    .foregroundColor(PostgraceTheme.accentSky)
            }
            
            Spacer()
            
            if let table = schemaViewModel.selectedTable {
                HStack(spacing: 4) {
                    Image(systemName: "tablecells")
                        .font(.caption2)
                    Text("\(table.schema).\(table.name)")
                        .font(.caption.monospaced())
                }
                .foregroundColor(.secondary)
            }
            
            if let result = queryViewModel.result {
                Text("•")
                    .foregroundColor(PostgraceTheme.border)
                Text("\(result.rowsAffected) rows")
                    .font(.caption.monospacedDigit())
                Text("•")
                    .foregroundColor(PostgraceTheme.border)
                Text(String(format: "%.3f s", result.executionTime))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            if !zoomManager.isDefaultZoom {
                Text("•")
                    .foregroundColor(PostgraceTheme.border)
                Button {
                    zoomManager.resetZoom()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 8))
                        Text(zoomManager.zoomPercentageString)
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundColor(PostgraceTheme.accentSky)
                }
                .buttonStyle(.plain)
                .help("Current zoom (Click to reset to 100%, ⌘+ / ⌘- to adjust)")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(PostgraceTheme.surface)
        .overlay(
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder),
            alignment: .top
        )
    }
}
