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
    @State private var showDeleteConfirmation = false

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

    private var isPortValid: Bool {
        guard let p = Int(port.trimmingCharacters(in: .whitespaces)) else { return false }
        return p >= 1 && p <= 65535
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        isPortValid
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: existingConnection == nil ? "plus.circle.fill" : "pencil.circle.fill")
                    .font(.title2)
                    .foregroundColor(PostgraceTheme.accentSky)

                VStack(alignment: .leading, spacing: 2) {
                    Text(existingConnection == nil ? "New Connection" : "Edit Connection")
                        .font(.title3.bold())
                    if let existing = existingConnection {
                        Text(existing.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(PostgraceTheme.surface)

            Divider()

            // Form
            Form {
                Section("Connection Details") {
                    TextField("Display Name (e.g. Local Development)", text: $name)
                        .focused($focusedField, equals: .name)

                    TextField("Host (e.g. localhost, 127.0.0.1)", text: $host)
                        .focused($focusedField, equals: .host)

                    HStack {
                        TextField("Port", text: $port)
                            .focused($focusedField, equals: .port)
                        if !isPortValid {
                            Text("1–65535")
                                .font(.caption2)
                                .foregroundColor(PostgraceTheme.destructiveRed)
                        }
                    }

                    TextField("Default Database", text: $database)
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
                        Text("Require (Strict TLS)").tag(SSLMode.require)
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

            // Test result banner
            if let result = testResult {
                HStack(spacing: 8) {
                    switch result {
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(PostgraceTheme.emeraldRw)
                        Text("Connection test successful! PostgreSQL server is reachable.")
                            .font(.caption)
                            .foregroundColor(PostgraceTheme.emeraldRw)
                    case .failure(let msg):
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(PostgraceTheme.destructiveRed)
                        Text(msg)
                            .font(.caption)
                            .foregroundColor(PostgraceTheme.destructiveRed)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(PostgraceTheme.surfaceElevated)
                .transition(.opacity)
            }

            Divider()

            // Actions Bottom Bar
            HStack(spacing: 12) {
                if let existing = existingConnection {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .font(.caption)
                        .foregroundColor(PostgraceTheme.destructiveRed)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Delete connection '\(existing.name)'?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                        Button("Delete Connection", role: .destructive) {
                            connectionViewModel.deleteConnection(existing)
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will remove '\(existing.name)' and its stored credentials from Postgrace.")
                    }
                }

                Button {
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
                } label: {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text("Test Connection")
                    }
                }
                .disabled(isTesting || !isFormValid)

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
                .buttonStyle(.borderedProminent)
                .tint(PostgraceTheme.accentSky)
                .keyboardShortcut(.defaultAction)
                .disabled(!isFormValid)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(PostgraceTheme.surface)
        }
        .frame(width: 480, height: 540)
        .onAppear {
            if let conn = existingConnection, password.isEmpty {
                if let stored = connectionViewModel.getStoredPassword(for: conn.id) {
                    password = stored
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = .name
            }
        }
    }

    private func buildConnection() -> SavedConnection {
        let cleanPort = Int(port.trimmingCharacters(in: .whitespaces)) ?? 5432
        return SavedConnection(
            id: existingConnection?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            host: host.trimmingCharacters(in: .whitespaces),
            port: cleanPort,
            username: username.trimmingCharacters(in: .whitespaces),
            database: database.trimmingCharacters(in: .whitespaces),
            sslMode: sslMode,
            colorTag: colorTag,
            createdAt: existingConnection?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }
}
