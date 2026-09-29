import SwiftUI

/// Connection form presented as a sheet for creating or editing connections.
struct ConnectionFormView: View {
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
    @State private var testResult: TestResult?
    @State private var isTesting = false
    @State private var showPassword = false

    enum FormField: Hashable {
        case name, host, port, database, username, password
    }
    @FocusState private var focusedField: FormField?

    let existingConnection: SavedConnection?

    enum TestResult {
        case success
        case failure(String)
    }

    init(connection: SavedConnection?) {
        self.existingConnection = connection
        _name = State(initialValue: connection?.name ?? "")
        _host = State(initialValue: connection?.host ?? "localhost")
        _port = State(initialValue: String(connection?.port ?? 5432))
        _username = State(initialValue: connection?.username ?? "")
        _database = State(initialValue: connection?.database ?? "")
        _sslMode = State(initialValue: connection?.sslMode ?? .disable)
        _colorTag = State(initialValue: connection?.colorTag ?? .none)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: existingConnection == nil ? "plus.circle.fill" : "pencil.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text(existingConnection == nil ? "New Connection" : "Edit Connection")
                    .font(.title2.bold())
                Spacer()
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("Connection") {
                    TextField("Display Name", text: $name)
                        .focused($focusedField, equals: .name)
                    TextField("Host", text: $host)
                        .focused($focusedField, equals: .host)
                    TextField("Port", text: $port)
                        .focused($focusedField, equals: .port)
                    TextField("Database", text: $database)
                        .focused($focusedField, equals: .database)
                }

                Section("Authentication") {
                    TextField("Username", text: $username)
                        .focused($focusedField, equals: .username)

                    HStack {
                        Group {
                            if showPassword {
                                TextField("Password", text: $password)
                                    .focused($focusedField, equals: .password)
                            } else {
                                SecureField("Password", text: $password)
                                    .focused($focusedField, equals: .password)
                            }
                        }
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }

                Section("Options") {
                    Picker("SSL Mode", selection: $sslMode) {
                        Text("Disable").tag(SSLMode.disable)
                        Text("Require").tag(SSLMode.require)
                    }

                    Picker("Color Tag", selection: $colorTag) {
                        Label("None", systemImage: "circle").tag(ConnectionColor.none)
                        Label("Red", systemImage: "circle.fill").foregroundColor(.red).tag(ConnectionColor.red)
                        Label("Blue", systemImage: "circle.fill").foregroundColor(.blue).tag(ConnectionColor.blue)
                        Label("Green", systemImage: "circle.fill").foregroundColor(.green).tag(ConnectionColor.green)
                        Label("Orange", systemImage: "circle.fill").foregroundColor(.orange).tag(ConnectionColor.orange)
                        Label("Purple", systemImage: "circle.fill").foregroundColor(.purple).tag(ConnectionColor.purple)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            // Test result
            if let result = testResult {
                HStack {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Connection successful!")
                            .foregroundColor(.green)
                    case .failure(let msg):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text(msg)
                            .foregroundColor(.red)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .font(.subheadline)
                .padding(.horizontal)
                .padding(.vertical, 4)
                .transition(.opacity)
            }

            Divider()

            // Actions
            HStack {
                Button("Test Connection") {
                    testResult = nil
                    isTesting = true
                    Task {
                        let conn = buildConnection()
                        let success = await connectionViewModel.testConnection(conn, password: password)
                        withAnimation {
                            testResult = success
                                ? .success
                                : .failure(connectionViewModel.connectionError ?? "Connection failed")
                        }
                        isTesting = false
                    }
                }
                .disabled(isTesting || host.isEmpty || username.isEmpty)

                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                Button("Save") {
                    let conn = buildConnection()
                    connectionViewModel.saveConnection(conn, password: password)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || host.isEmpty || username.isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 520)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .name
            }
        }
    }

    private func buildConnection() -> SavedConnection {
        SavedConnection(
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
