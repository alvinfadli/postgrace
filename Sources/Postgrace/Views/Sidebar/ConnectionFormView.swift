import SwiftUI

/// Connection form presented as a sheet for creating or editing connections.
struct ConnectionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionViewModel.self) private var connectionViewModel

    @State private var engine: DatabaseEngine
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var password = ""
    @State private var database: String
    @State private var sslMode: SSLMode
    @State private var colorTag: ConnectionColor
    @State private var isSafeModeEnabled: Bool
    @State private var testResult: TestResult?
    @State private var isTesting = false
    @State private var showPassword = false
    @State private var showDeleteConfirmation = false
    @State private var connectionMethod: ConnectionInputMode = .parameters
    @State private var connectionStringInput: String

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
        _engine = State(initialValue: connection?.engine ?? .postgresql)
        _name = State(initialValue: connection?.name ?? "")
        _host = State(initialValue: connection?.host ?? "localhost")
        _port = State(initialValue: String(connection?.port ?? (connection?.engine ?? .postgresql).defaultPort))
        _username = State(initialValue: connection?.username ?? "")
        _database = State(initialValue: connection?.database ?? "")
        _sslMode = State(initialValue: connection?.sslMode ?? .disable)
        _colorTag = State(initialValue: connection?.colorTag ?? .none)
        _isSafeModeEnabled = State(initialValue: connection?.isSafeModeEnabled ?? false)
        _connectionStringInput = State(initialValue: connection?.connectionString(includePassword: false) ?? "")
    }

    private var parsedConnectionString: (connection: SavedConnection, password: String)? {
        SavedConnection.parse(connectionString: connectionStringInput)
    }

    private var effectivePassword: String {
        if connectionMethod == .connectionString, let p = parsedConnectionString, !p.password.isEmpty {
            return p.password
        }
        return password
    }

    private var isHostLocalhost: Bool {
        let h = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return h == "localhost" || h == "127.0.0.1" || h == "::1" || h.hasSuffix(".local")
    }

    private var isPortValid: Bool {
        guard let p = Int(port.trimmingCharacters(in: .whitespaces)) else { return false }
        return p >= 1 && p <= 65535
    }

    private var isFormValid: Bool {
        if connectionMethod == .connectionString {
            return parsedConnectionString != nil
        }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !host.trimmingCharacters(in: .whitespaces).isEmpty &&
            !username.trimmingCharacters(in: .whitespaces).isEmpty &&
            isPortValid
    }

    private func parseAndApply(_ raw: String) {
        if let (p, pwd) = SavedConnection.parse(connectionString: raw) {
            engine = p.engine
            host = p.host
            port = "\(p.port)"
            username = p.username
            database = p.database
            sslMode = p.sslMode
            if !pwd.isEmpty {
                password = pwd
            }
            if name.trimmingCharacters(in: .whitespaces).isEmpty || name.contains(" on ") {
                name = p.name
            }
        }
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
                        Text("\(existing.name) (\(existing.engine.rawValue))")
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
                Section("Database Engine") {
                    PostgraceSegmentedControl(
                        selection: $engine,
                        items: DatabaseEngine.allCases,
                        titleFor: { $0.rawValue },
                        iconFor: { $0.iconName }
                    )
                    .onChange(of: engine) { oldEngine, newEngine in
                        if port.isEmpty || port == String(oldEngine.defaultPort) {
                            port = String(newEngine.defaultPort)
                        }
                        if database.isEmpty || database == oldEngine.defaultDatabase {
                            database = newEngine.defaultDatabase
                        }
                        if username.isEmpty || username == oldEngine.defaultUsername {
                            username = newEngine.defaultUsername
                        }
                        if connectionMethod == .connectionString && connectionStringInput.isEmpty {
                            let current = buildConnection()
                            connectionStringInput = current.connectionString(includePassword: true, password: effectivePassword)
                        }
                    }
                }

                Section("Connection Method") {
                    PostgraceSegmentedControl(
                        selection: $connectionMethod,
                        items: ConnectionInputMode.allCases,
                        titleFor: { $0.rawValue },
                        iconFor: { $0.iconName }
                    )
                    .onChange(of: connectionMethod) { oldVal, newVal in
                        if newVal == .connectionString {
                            if connectionStringInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let current = buildConnection()
                                connectionStringInput = current.connectionString(includePassword: true, password: effectivePassword)
                            }
                        } else if oldVal == .connectionString {
                            if let p = parsedConnectionString {
                                engine = p.connection.engine
                                host = p.connection.host
                                port = "\(p.connection.port)"
                                username = p.connection.username
                                database = p.connection.database
                                sslMode = p.connection.sslMode
                                if !p.password.isEmpty {
                                    password = p.password
                                }
                            }
                        }
                    }
                }

                if connectionMethod == .connectionString {
                    Section("Connection String") {
                        HStack {
                            Text("Paste URI or PostgreSQL Key-Value format")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Paste") {
                                if let clip = NSPasteboard.general.string(forType: .string) {
                                    connectionStringInput = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                    parseAndApply(connectionStringInput)
                                }
                            }
                            .font(.caption2)
                            .buttonStyle(.borderless)
                        }

                        TextEditor(text: $connectionStringInput)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 70)
                            .padding(4)
                            .background(PostgraceTheme.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                            )
                            .onChange(of: connectionStringInput) { _, newVal in
                                parseAndApply(newVal)
                            }

                        if let p = parsedConnectionString {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(PostgraceTheme.emeraldRw)
                                    Text("Valid \(p.connection.engine.rawValue) String")
                                        .font(.caption.bold())
                                        .foregroundColor(PostgraceTheme.emeraldRw)
                                Spacer()
                                Text(p.connection.sslMode.displayName)
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(PostgraceTheme.surfaceElevated)
                                    .clipShape(Capsule())
                                }

                                Divider().padding(.vertical, 2)

                                Text("Host: \(p.connection.host):\(p.connection.port)")
                                    .font(.caption)
                                Text("Database: \(p.connection.database)")
                                    .font(.caption)
                                Text("User: \(p.connection.username)")
                                    .font(.caption)
                            }
                            .padding(8)
                            .background(PostgraceTheme.accentEmeraldMuted.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        } else if !connectionStringInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Invalid format. Examples:\n• postgresql://user:password@host:5432/dbname?sslmode=require\n• host=localhost port=5432 dbname=mydb user=postgres password=secret")
                                .font(.caption2)
                                .foregroundColor(PostgraceTheme.destructiveRed)
                        }
                    }

                    Section("General") {
                        TextField("Display Name", text: $name)
                            .focused($focusedField, equals: .name)

                        Picker("Color Tag", selection: $colorTag) {
                            Label("None", systemImage: "circle").tag(ConnectionColor.none)
                            Label("Red", systemImage: "circle.fill").foregroundColor(.red).tag(ConnectionColor.red)
                            Label("Blue", systemImage: "circle.fill").foregroundColor(.blue).tag(ConnectionColor.blue)
                            Label("Green", systemImage: "circle.fill").foregroundColor(.green).tag(ConnectionColor.green)
                            Label("Orange", systemImage: "circle.fill").foregroundColor(.orange).tag(ConnectionColor.orange)
                            Label("Purple", systemImage: "circle.fill").foregroundColor(.purple).tag(ConnectionColor.purple)
                        }

                        if isHostLocalhost {
                            PostgraceToggle("Safe Mode (Guard against dangerous queries)", isOn: $isSafeModeEnabled)
                                .help("When ON, dangerous queries on localhost require confirmation.")
                        } else {
                            HStack {
                                Label("Safe Mode: Enforced (Locked ON)", systemImage: "lock.shield.fill")
                                    .foregroundColor(PostgraceTheme.destructiveRed)
                                Spacer()
                                Text("Remote Host")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .help("Safe Mode is permanently locked for remote connections to protect against accidental changes.")
                        }
                    }
                } else {
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
                            ForEach(SSLMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }

                        Picker("Color Tag", selection: $colorTag) {
                            Label("None", systemImage: "circle").tag(ConnectionColor.none)
                            Label("Red", systemImage: "circle.fill").foregroundColor(.red).tag(ConnectionColor.red)
                            Label("Blue", systemImage: "circle.fill").foregroundColor(.blue).tag(ConnectionColor.blue)
                            Label("Green", systemImage: "circle.fill").foregroundColor(.green).tag(ConnectionColor.green)
                            Label("Orange", systemImage: "circle.fill").foregroundColor(.orange).tag(ConnectionColor.orange)
                            Label("Purple", systemImage: "circle.fill").foregroundColor(.purple).tag(ConnectionColor.purple)
                        }

                        if isHostLocalhost {
                            PostgraceToggle("Safe Mode (Guard against dangerous queries)", isOn: $isSafeModeEnabled)
                                .help("When ON, dangerous queries on localhost require confirmation.")
                        } else {
                            HStack {
                                Label("Safe Mode: Enforced (Locked ON)", systemImage: "lock.shield.fill")
                                    .foregroundColor(PostgraceTheme.destructiveRed)
                                Spacer()
                                Text("Remote Host")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .help("Safe Mode is permanently locked for remote connections to protect against accidental changes.")
                        }
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
                        Text("Connection test successful! \(engine.rawValue) server is reachable.")
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

                PostgraceButton(
                    "Test Connection",
                    variant: .secondary,
                    isLoading: isTesting
                ) {
                    testResult = nil
                    isTesting = true
                    Task {
                        let conn = buildConnection()
                        let cleanPassword = effectivePassword.trimmingCharacters(in: .newlines)
                        let success = await connectionViewModel.testConnection(conn, password: cleanPassword)
                        withAnimation {
                            testResult = success
                                ? .success
                                : .failure(connectionViewModel.connectionError ?? "Connection failed")
                        }
                        isTesting = false
                    }
                }
                .disabled(isTesting || !isFormValid)

                Spacer()

                PostgraceButton("Cancel", variant: .secondary) {
                    dismiss()
                }
                .keyboardShortcut(.escape)

                PostgraceButton("Save", variant: .primary) {
                    let conn = buildConnection()
                    let cleanPassword = effectivePassword.trimmingCharacters(in: .newlines)
                    connectionViewModel.saveConnection(conn, password: cleanPassword)
                    dismiss()
                }
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
        if connectionMethod == .connectionString, let p = parsedConnectionString {
            let connName = name.trimmingCharacters(in: .whitespaces).isEmpty ? p.connection.name : name.trimmingCharacters(in: .whitespaces)
            return SavedConnection(
                id: existingConnection?.id ?? UUID(),
                name: connName,
                engine: p.connection.engine,
                host: p.connection.host,
                port: p.connection.port,
                username: p.connection.username,
                database: p.connection.database,
                sslMode: p.connection.sslMode,
                colorTag: colorTag,
                isSafeModeEnabled: p.connection.isSafeModeLocked ? true : isSafeModeEnabled,
                caCertPath: p.connection.caCertPath,
                createdAt: existingConnection?.createdAt ?? Date(),
                updatedAt: Date()
            )
        }

        let cleanPort = Int(port.trimmingCharacters(in: .whitespaces)) ?? engine.defaultPort
        return SavedConnection(
            id: existingConnection?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            engine: engine,
            host: host.trimmingCharacters(in: .whitespaces),
            port: cleanPort,
            username: username.trimmingCharacters(in: .whitespaces),
            database: database.trimmingCharacters(in: .whitespaces),
            sslMode: sslMode,
            colorTag: colorTag,
            isSafeModeEnabled: isHostLocalhost ? isSafeModeEnabled : true,
            createdAt: existingConnection?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }
}
