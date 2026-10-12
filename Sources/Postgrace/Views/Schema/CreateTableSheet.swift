import SwiftUI

/// Visual table designer and column builder with live SQL DDL preview and schema CREATE privilege enforcement.
struct CreateTableSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SchemaViewModel.self) private var schemaViewModel

    let initialSchema: String

    @State private var targetSchema: String = "public"
    @State private var tableName: String = ""
    @State private var columns: [EditableColumn] = []
    @State private var isCreating: Bool = false
    @State private var errorMessage: String?

    struct EditableColumn: Identifiable {
        let id = UUID()
        var name: String
        var dataType: String
        var isPrimaryKey: Bool
        var isNullable: Bool
        var defaultValue: String
    }

    private let supportedDataTypes = [
        "bigserial",
        "bigint",
        "serial",
        "integer",
        "smallint",
        "varchar(255)",
        "text",
        "boolean",
        "timestamptz",
        "timestamp",
        "numeric",
        "jsonb",
        "uuid",
        "date",
        "bytea"
    ]

    init(initialSchema: String = "public") {
        self.initialSchema = initialSchema
        _targetSchema = State(initialValue: initialSchema)
        _columns = State(initialValue: [
            EditableColumn(name: "id", dataType: "bigserial", isPrimaryKey: true, isNullable: false, defaultValue: ""),
            EditableColumn(name: "title", dataType: "text", isPrimaryKey: false, isNullable: false, defaultValue: ""),
            EditableColumn(name: "created_at", dataType: "timestamptz", isPrimaryKey: false, isNullable: false, defaultValue: "now()")
        ])
    }

    private var currentUser: String {
        schemaViewModel.userPrivileges?.username ?? ""
    }

    private var canCreateInTargetSchema: Bool {
        guard let privs = schemaViewModel.userPrivileges else { return true }
        if privs.isSuperuser { return true }
        if let schemaPriv = privs.schemaPrivileges[targetSchema] {
            return schemaPriv.canCreate
        }
        return false
    }

    private var isValidTableName: Bool {
        let trimmed = tableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let regex = try? NSRegularExpression(pattern: "^[a-zA-Z_][a-zA-Z0-9_]*$")
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex?.firstMatch(in: trimmed, options: [], range: range) != nil
    }

    private var isValidColumns: Bool {
        guard !columns.isEmpty else { return false }
        for col in columns {
            let trimmed = col.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
        }
        return true
    }

    private var generatedSql: String {
        let trimmedTable = tableName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTable.isEmpty else { return "-- Enter table name to generate DDL" }

        var lines: [String] = []
        for col in columns {
            let colName = col.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if colName.isEmpty { continue }

            var colDef = "    \"\(colName)\" \(col.dataType.uppercased())"
            if col.isPrimaryKey {
                colDef += " PRIMARY KEY"
            } else if !col.isNullable {
                colDef += " NOT NULL"
            }

            let defVal = col.defaultValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !defVal.isEmpty && !col.isPrimaryKey {
                colDef += " DEFAULT \(defVal)"
            }
            lines.append(colDef)
        }

        if lines.isEmpty {
            return "CREATE TABLE \"\(targetSchema)\".\"\(trimmedTable)\" ();"
        }

        return "CREATE TABLE \"\(targetSchema)\".\"\(trimmedTable)\" (\n" + lines.joined(separator: ",\n") + "\n);"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "tablecells.badge.ellipsis")
                    .font(.title2)
                    .foregroundColor(PostgraceTheme.accentSky)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create New Table")
                        .font(.headline)
                    Text("Design schema, columns, constraints, and data types")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Schema & Table Name row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Schema")
                        .font(.caption.bold())
                    PostgracePicker(
                        selection: $targetSchema,
                        items: availableSchemas,
                        titleFor: { $0 }
                    )
                }
                .frame(width: 140)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Table Name")
                        .font(.caption.bold())
                    PostgraceTextField("e.g. orders, users, transactions", text: $tableName)
                }
            }

            // Permission Warning if target schema lacks CREATE
            if !canCreateInTargetSchema {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Permission Limitation")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                        Text("User '\(currentUser)' lacks CREATE privilege on schema '\(targetSchema)'. Table creation will be rejected with PostgreSQL error 42501.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Column Builder Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Columns Definition")
                        .font(.caption.bold())
                    Spacer()
                    Button {
                        columns.append(EditableColumn(
                            name: "column_\(columns.count + 1)",
                            dataType: "text",
                            isPrimaryKey: false,
                            isNullable: true,
                            defaultValue: ""
                        ))
                    } label: {
                        Label("Add Column", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(PostgraceTheme.accentSky)
                }

                // Column Rows Header
                HStack(spacing: 8) {
                    Text("Column Name")
                        .font(.caption2.bold())
                        .frame(width: 130, alignment: .leading)
                    Text("Data Type")
                        .font(.caption2.bold())
                        .frame(width: 130, alignment: .leading)
                    Text("PK")
                        .font(.caption2.bold())
                        .frame(width: 30, alignment: .center)
                    Text("Nullable")
                        .font(.caption2.bold())
                        .frame(width: 55, alignment: .center)
                    Text("Default Value")
                        .font(.caption2.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                        .frame(width: 24)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

                // Scrollable Columns List
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach($columns) { $col in
                            columnRow(col: $col)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 160)
                .background(PostgraceTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                        .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )
            }

            // Live SQL DDL Preview Box
            VStack(alignment: .leading, spacing: 4) {
                Text("Generated SQL DDL")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                ScrollView(.horizontal) {
                    Text(SQLSyntaxHighlighter.attributedString(for: generatedSql, fontSize: 10.5))
                        .padding(8)
                }
                .frame(maxWidth: .infinity, minHeight: 65, maxHeight: 75, alignment: .topLeading)
                .background(PostgraceTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                        .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )
            }

            // Error Banner
            if let error = errorMessage {
                HStack {
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
                PostgraceButton("Cancel", variant: .secondary) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                PostgraceButton("Create Table", variant: .primary, isLoading: isCreating) {
                    createAction()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidTableName || !isValidColumns || !canCreateInTargetSchema || isCreating)
            }
        }
        .padding(20)
        .frame(width: 600, height: 560)
    }

    private var availableSchemas: [String] {
        let nonSystem = schemaViewModel.schemas.filter { !$0.name.hasPrefix("pg_") && $0.name != "information_schema" }.map(\.name)
        return nonSystem.isEmpty ? ["public"] : nonSystem
    }

    @ViewBuilder
    private func columnRow(col: Binding<EditableColumn>) -> some View {
        HStack(spacing: 8) {
            PostgraceTextField("Column name", text: col.name, showsClearButton: false)
                .frame(width: 130)

            PostgracePicker(
                selection: col.dataType,
                items: supportedDataTypes,
                titleFor: { $0 }
            )
            .frame(width: 130)

            PostgraceCheckbox(isOn: col.isPrimaryKey)
                .frame(width: 30)
                .onChange(of: col.isPrimaryKey.wrappedValue) { _, isPK in
                    if isPK {
                        col.isNullable.wrappedValue = false
                    }
                }

            PostgraceCheckbox(isOn: col.isNullable)
                .frame(width: 55)
                .disabled(col.isPrimaryKey.wrappedValue)

            PostgraceTextField("Default (e.g. now())", text: col.defaultValue, showsClearButton: false)
                .frame(maxWidth: .infinity)

            Button {
                columns.removeAll { $0.id == col.id }
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .disabled(columns.count <= 1)
            .frame(width: 24)
        }
        .padding(.horizontal, 4)
    }

    private func createAction() {
        let trimmedTable = tableName.trimmingCharacters(in: .whitespacesAndNewlines)
        let defs = columns.map {
            NewColumnDefinition(
                name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                dataType: $0.dataType,
                isPrimaryKey: $0.isPrimaryKey,
                isNullable: $0.isNullable,
                defaultValue: $0.defaultValue.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                try await schemaViewModel.createTable(schema: targetSchema, name: trimmedTable, columns: defs)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}
