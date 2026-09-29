import SwiftUI

public struct StatusBarView: View {
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(QueryViewModel.self) private var queryViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel
    
    public init() {}
    
    public var body: some View {
        HStack {
            Circle()
                .fill(connectionViewModel.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(connectionViewModel.isConnected ? "Connected" : "Disconnected")
                .font(.caption)
            
            if connectionViewModel.isConnected, let conn = connectionViewModel.selectedConnection {
                Text("-")
                Text(conn.database)
                    .font(.caption)
                    .bold()
            }
            
            Spacer()
            
            if let table = schemaViewModel.selectedTable {
                Text("Table: \(table.name)")
                    .font(.caption)
            }
            
            if let result = queryViewModel.result {
                Text("•")
                Text("\(result.rowsAffected) rows")
                    .font(.caption)
                Text("•")
                Text(String(format: "%.2f s", result.executionTime))
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(Color(NSColor.windowBackgroundColor))
        .border(Color(NSColor.separatorColor), width: 1)
    }
}
