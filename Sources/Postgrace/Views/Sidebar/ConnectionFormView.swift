import SwiftUI

public struct ConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password = ""
    @State private var database: String
    @State private var sslMode: SSLMode
    @State private var colorTag: ConnectionColor
    @State private var testResult: Bool?
    
    let existingConnection: SavedConnection?
    
    public init(connection: SavedConnection?) {
        self.existingConnection = connection
        _name = State(initialValue: connection?.name ?? "")
        _host = State(initialValue: connection?.host ?? "localhost")
        _port = State(initialValue: String(connection?.port ?? 5432))
        _username = State(initialValue: connection?.username ?? "")
        _database = State(initialValue: connection?.database ?? "")
        _sslMode = State(initialValue: connection?.sslMode ?? .disable)
        _colorTag = State(initialValue: connection?.colorTag ?? .none)
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            Text(existingConnection == nil ? "New Connection" : "Edit Connection")
                .font(.title2)
                .bold()
            
            Form {
                TextField("Name", text: $name)
                TextField("Host", text: $host)
                TextField("Port", text: $port)
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
                TextField("Database", text: $database)
                
                Picker("SSL Mode", selection: $sslMode) {
                    Text("Disable").tag(SSLMode.disable)
                    Text("Require").tag(SSLMode.require)
                }
                
                Picker("Color Tag", selection: $colorTag) {
                    Text("None").tag(ConnectionColor.none)
                    Text("Red").tag(ConnectionColor.red)
                    Text("Blue").tag(ConnectionColor.blue)
                    Text("Green").tag(ConnectionColor.green)
                    Text("Orange").tag(ConnectionColor.orange)
                    Text("Purple").tag(ConnectionColor.purple)
                }
            }
            .padding()
            
            if let result = testResult {
                Text(result ? "Connection successful!" : (connectionViewModel.connectionError ?? "Connection failed"))
                    .foregroundColor(result ? .green : .red)
                    .animation(.easeInOut, value: testResult)
            }
            
            HStack {
                Button("Test Connection") {
                    Task {
                        let conn = buildConnection()
                        testResult = await connectionViewModel.testConnection(conn, password: password)
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Save") {
                    let conn = buildConnection()
                    connectionViewModel.saveConnection(conn, password: password)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || host.isEmpty || username.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
    
    private func buildConnection() -> SavedConnection {
        return SavedConnection(
            id: existingConnection?.id ?? UUID(),
            name: name,
            host: host,
            port: Int(port) ?? 5432,
            username: username,
            database: database,
            sslMode: sslMode,
            colorTag: colorTag,
            createdAt: existingConnection?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }
}
