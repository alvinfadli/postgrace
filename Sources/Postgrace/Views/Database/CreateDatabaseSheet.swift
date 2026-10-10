import SwiftUI

/// Modal sheet for creating a new PostgreSQL database.
/// Performs identifier validation, checks role eligibility (CREATEDB or SUPERUSER), and previews SQL DDL.
struct CreateDatabaseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionViewModel.self) private var connectionViewModel
    @Environment(SchemaViewModel.self) private var schemaViewModel

    @State private var dbName: String = ""
    @State private var customOwner: String = ""
    @State private var selectedEncoding: String = "UTF8"
    @State private var template: String = ""
    @State private var connectionLimit: String = ""
    @State private var switchAfterCreation: Bool = true
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?

    private let standardEncodings = ["UTF8", "LATIN1", "SQL_ASCII", "WIN1252", "EUC_JP"]

    private var currentUser: String {
        schemaViewModel.userPrivileges?.username ?? ""
    }

    private var canCreateDatabase: Bool {
        schemaViewModel.canCreateDatabase
    }

    private var existingDatabases: Set<String> {
        let fromSchema = schemaViewModel.databases.map(\.name)
        let fromConn = connectionViewModel.availableDatabases.map(\.name)
        return Set(fromSchema + fromConn)
    }

    private var nameAlreadyExists: Bool {
        let trimmed = dbName.trimmingCharacters(in: .whitespacesAndNewlines)
        return existingDatabases.contains(trimmed)
    }

    private var isValidIdentifier: Bool {
        let trimmed = dbName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // PostgreSQL identifiers start with letter/underscore and contain letters/digits/underscores
        let regex = try? NSRegularExpression(pattern: "^[a-zA-Z_][a-zA-Z0-9_]*$")
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex?.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    private var canSubmit: Bool {
        isValidIdentifier && !nameAlreadyExists && canCreateDatabase && !isCreating
    }

    private var generatedSql: String {
        let trimmed = dbName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-- Enter database name to preview SQL" }
        var clauses: [String] = []

        let owner = customOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty {
            clauses.append("OWNER \"\(owner)\"")
        }

        if !selectedEncoding.isEmpty {
            clauses.append("ENCODING '\(selectedEncoding)'")
        }

        let templ = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if !templ.isEmpty {
            clauses.append("TEMPLATE \"\(templ)\"")
        }

        if let limit = Int(connectionLimit.trimmingCharacters(in: .whitespacesAndNewlines)) {
            clauses.append("CONNECTION LIMIT \(limit)")
        }

        if clauses.isEmpty {
            return "CREATE DATABASE \"\(trimmed)\";"
        } else {
            return "CREATE DATABASE \"\(trimmed)\"\n  " + clauses.joined(separator: "\n  ") + ";"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.title2)
                    .foregroundColor(PostgraceTheme.accentSky)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create New Database")
                        .font(.headline)
                    Text("Create a new PostgreSQL database on server '\(connectionViewModel.selectedConnection?.name ?? "Server")'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Permission Warning if user lacks CREATEDB or SUPERUSER
            if !canCreateDatabase {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundColor(PostgraceTheme.amberRo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Role Ineligible")
                            .font(.caption.bold())
                            .foregroundColor(PostgraceTheme.amberRo)
                        Text("Current role '\(currentUser)' does not possess CREATEDB or SUPERUSER privileges. PostgreSQL will reject this request with error 42501.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(PostgraceTheme.amberRoMuted)
                .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                        .stroke(PostgraceTheme.amberRo.opacity(0.3), lineWidth: PostgraceTheme.hairlineBorder)
                )
            }

            // Form Fields
            VStack(alignment: .leading, spacing: 12) {
                // Database Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Database Name *")
                        .font(.caption.bold())
                    PostgraceTextField("e.g. analytics_staging, billing_prod", text: $dbName)

                    if !dbName.isEmpty && !isValidIdentifier {
                        Text("Database name must start with a letter/underscore and contain only letters, numbers, and underscores.")
                            .font(.caption2)
                            .foregroundColor(PostgraceTheme.destructiveRed)
                    } else if nameAlreadyExists {
                        Text("A database named '\(dbName)' already exists on this server.")
                            .font(.caption2)
                            .foregroundColor(PostgraceTheme.destructiveRed)
                    }
                }

                // Owner & Encoding Row
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Owner (optional)")
                            .font(.caption.bold())
                        PostgraceTextField("Defaults to \(currentUser.isEmpty ? "current user" : currentUser)", text: $customOwner)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Encoding")
                            .font(.caption.bold())
                        PostgracePicker(
                            selection: $selectedEncoding,
                            items: standardEncodings,
                            titleFor: { $0 }
                        )
                    }
                }

                // Template & Connection Limit Row
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Template Database (optional)")
                            .font(.caption.bold())
                        PostgraceTextField("e.g. template1", text: $template)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connection Limit (optional)")
                            .font(.caption.bold())
                        PostgraceTextField("e.g. -1 for unlimited", text: $connectionLimit)
                    }
                }

                PostgraceToggle("Switch to new database immediately after creation", isOn: $switchAfterCreation)
                    .padding(.top, 4)
            }

            // DDL SQL Preview
            VStack(alignment: .leading, spacing: 4) {
                Text("SQL Preview")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(generatedSql)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(PostgraceTheme.accentSky)
                        .padding(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PostgraceTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                        .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )
            }

            // Error Display
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(PostgraceTheme.destructiveRed)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(PostgraceTheme.destructiveRed)
                }
            }

            // Footer / Actions
            HStack {
                PostgraceButton("Cancel", variant: .ghost) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                PostgraceButton(
                    "Create Database",
                    variant: .primary,
                    isLoading: isCreating
                ) {
                    createDatabase()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func createDatabase() {
        let trimmedName = dbName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let owner = customOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let templ = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = Int(connectionLimit.trimmingCharacters(in: .whitespacesAndNewlines))

        isCreating = true
        errorMessage = nil

        Task {
            do {
                try await schemaViewModel.createDatabase(
                    name: trimmedName,
                    owner: owner.isEmpty ? nil : owner,
                    encoding: selectedEncoding.isEmpty ? nil : selectedEncoding,
                    template: templ.isEmpty ? nil : templ,
                    connectionLimit: limit
                )

                // Sync connectionViewModel available databases
                let updatedDatabases = await schemaViewModel.loadAvailableDatabases()
                connectionViewModel.availableDatabases = updatedDatabases

                if switchAfterCreation {
                    await connectionViewModel.switchDatabase(to: trimmedName, schemaViewModel: schemaViewModel)
                }

                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}
