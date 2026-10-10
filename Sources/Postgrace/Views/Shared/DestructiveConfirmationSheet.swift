import SwiftUI

/// Reusable modal sheet for confirming destructive database actions (DROP SCHEMA, DROP TABLE, TRUNCATE TABLE).
struct DestructiveConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let targetName: String
    let actionType: ActionType
    let canPerformAction: Bool
    let permissionWarning: String?
    let allowsCascade: Bool
    let onConfirm: (Bool) -> Void

    @State private var cascade: Bool = false
    @State private var typedConfirmation: String = ""

    enum ActionType {
        case dropSchema
        case dropTable
        case truncateTable
        case dropDatabase

        var buttonTitle: String {
            switch self {
            case .dropSchema: return "Drop Schema"
            case .dropTable: return "Drop Table"
            case .truncateTable: return "Truncate Table"
            case .dropDatabase: return "Drop Database"
            }
        }

        var iconName: String {
            switch self {
            case .dropSchema: return "folder.badge.minus"
            case .dropTable: return "trash"
            case .truncateTable: return "eraser.line.dashed"
            case .dropDatabase: return "cylinder.split.1x2"
            }
        }
    }

    private var isConfirmed: Bool {
        typedConfirmation.trimmingCharacters(in: .whitespacesAndNewlines) == targetName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: actionType.iconName)
                    .font(.title2)
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text("This operation cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Permission Warning
            if !canPerformAction, let warning = permissionWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundColor(PostgraceTheme.destructiveRed)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Permission Notice")
                            .font(.caption.bold())
                            .foregroundColor(PostgraceTheme.destructiveRed)
                        Text(warning)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(PostgraceTheme.destructiveRedMuted)
                .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                        .stroke(PostgraceTheme.destructiveRed.opacity(0.3), lineWidth: PostgraceTheme.hairlineBorder)
                )
            }

            // Description
            VStack(alignment: .leading, spacing: 8) {
                switch actionType {
                case .dropSchema:
                    Text("Dropping schema **\"\(targetName)\"** will permanently delete the schema definition.")
                        .font(.callout)
                case .dropTable:
                    Text("Dropping table **\"\(targetName)\"** will permanently delete the table, its indexes, and all stored rows.")
                        .font(.callout)
                case .truncateTable:
                    Text("Truncating table **\"\(targetName)\"** will instantly erase all rows in the table and reset identity sequences.")
                        .font(.callout)
                case .dropDatabase:
                    Text("Dropping database **\"\(targetName)\"** will permanently delete the entire database, its schemas, tables, and all data stored within it.")
                        .font(.callout)
                }

                if allowsCascade {
                    let toggleLabel = (actionType == .dropDatabase)
                        ? "Force drop (terminate active client connections first)"
                        : "Cascade (automatically drop all dependent objects/foreign keys)"
                    PostgraceCheckbox(toggleLabel, isOn: $cascade)
                        .padding(.top, 4)
                }
            }

            // Confirmation Field
            VStack(alignment: .leading, spacing: 4) {
                Text("Type **\(targetName)** to confirm:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                PostgraceTextField(targetName, text: $typedConfirmation, isMonospaced: true)
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

                PostgraceButton(actionType.buttonTitle, variant: .destructive) {
                    onConfirm(cascade)
                    dismiss()
                }
                .disabled(!isConfirmed || !canPerformAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 350)
    }
}
