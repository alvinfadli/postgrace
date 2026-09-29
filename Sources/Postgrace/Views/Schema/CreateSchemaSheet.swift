import SwiftUI

/// Modal sheet for creating a new PostgreSQL schema.
/// Performs identifier validation, checks database-level CREATE privilege, and previews SQL DDL.
struct CreateSchemaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SchemaViewModel.self) private var schemaViewModel

    @State private var schemaName: String = ""
    @State private var customOwner: String = ""
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?

    private var currentUser: String {
        schemaViewModel.userPrivileges?.username ?? ""
    }

    private var canCreateSchema: Bool {
        guard let privs = schemaViewModel.userPrivileges else { return true }
        return privs.isSuperuser || privs.canCreateSchemaInDb
    }

    private var isValidIdentifier: Bool {
        let trimmed = schemaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Identifier validation: starts with letter/underscore, followed by letters/digits/underscores
        let regex = try? NSRegularExpression(pattern: "^[a-zA-Z_][a-zA-Z0-9_]*$")
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex?.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    private var generatedSql: String {
        let trimmed = schemaName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "-- Enter schema name to preview SQL" }
        var sql = "CREATE SCHEMA \"\(trimmed)\""
        let owner = customOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        if !owner.isEmpty {
            sql += " AUTHORIZATION \"\(owner)\""
        }
        sql += ";"
        return sql
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create New Schema")
                        .font(.headline)
                    Text("Add a new PostgreSQL schema namespace to the active database")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Permission Warning if user lacks CREATE on database
            if !canCreateSchema {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Permission Limitation")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                        Text("User '\(currentUser)' does not have CREATE privilege on this database. Creating a schema will likely result in PostgreSQL error 42501.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Form Fields
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Schema Name")
                        .font(.caption.bold())
                    TextField("e.g. billing, analytics, app_v2", text: $schemaName)
                        .textFieldStyle(.roundedBorder)

                    if !schemaName.isEmpty && !isValidIdentifier {
                        Text("Schema name must start with a letter/underscore and contain only letters, numbers, and underscores.")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Authorization Owner (Optional)")
                        .font(.caption.bold())
                    TextField(currentUser.isEmpty ? "Owner role" : "Default: \(currentUser)", text: $customOwner)
                        .textFieldStyle(.roundedBorder)
                    Text("Leave blank to default to the current login role.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Live SQL Preview
                VStack(alignment: .leading, spacing: 4) {
                    Text("SQL DDL Preview")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(generatedSql)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }

            // Error display
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(6)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            Divider()

            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isCreating {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Create Schema") {
                    createAction()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidIdentifier || isCreating)
            }
        }
        .padding(20)
        .frame(width: 440, height: 380)
    }

    private func createAction() {
        let name = schemaName.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = customOwner.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedOwner = owner.isEmpty ? nil : owner

        isCreating = true
        errorMessage = nil

        Task {
            do {
                try await schemaViewModel.createSchema(name: name, owner: resolvedOwner)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}
