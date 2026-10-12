import SwiftUI

/// Pre-execution confirmation sheet displayed when a dangerous query is executed with Safe Mode active.
struct SafeModeConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    let host: String
    let port: Int
    let database: String
    let isLocalhost: Bool
    let safetyResult: SQLSafetyCheckResult
    let sql: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var formattedSqlPreview: String {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 500 {
            return String(trimmed.prefix(500)) + "\n… [truncated]"
        }
        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                if safetyResult.isUnbounded {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 28))
                        .foregroundColor(PostgraceTheme.destructiveRed)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(PostgraceTheme.amberRo)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(safetyResult.isUnbounded
                         ? "CRITICAL: Unbounded Modification Detected"
                         : (isLocalhost ? "Confirm Execution (Safe Mode)" : "Confirm Execution on Remote Database"))
                        .font(.headline)
                        .foregroundColor(safetyResult.isUnbounded ? PostgraceTheme.destructiveRed : .primary)

                    Text("Target: \(host):\(port) / \(database)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Warning Banner
            if safetyResult.isUnbounded {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title3)
                        .foregroundColor(PostgraceTheme.destructiveRed)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DANGEROUS: No WHERE Clause Detected")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(PostgraceTheme.destructiveRed)
                        Text("Executing this will modify or delete ALL rows in \(safetyResult.targetObject.map { "\"\($0)\"" } ?? "the target table"). This action cannot be easily rolled back.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(10)
                .background(PostgraceTheme.destructiveRedMuted)
                .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                        .stroke(PostgraceTheme.destructiveRed.opacity(0.35), lineWidth: PostgraceTheme.hairlineBorder)
                )
            } else {
                Text("You are about to execute a **\(safetyResult.statementType)** statement on \(isLocalhost ? "local" : "remote") database.")
                    .font(.callout)
            }

            // Statement Preview Box
            VStack(alignment: .leading, spacing: 6) {
                Text("Statement Preview:")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                ScrollView([.horizontal, .vertical]) {
                    Text(formattedSqlPreview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .background(PostgraceTheme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                )
            }

            // Safe Mode policy footnote
            Text(isLocalhost
                 ? "Safe Mode is active for localhost to prevent accidental data loss."
                 : "Safe Mode is permanently locked for remote hosts to prevent accidental data loss.")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            Divider()

            // Action Buttons
            HStack {
                PostgraceButton("Cancel", variant: .secondary) {
                    onCancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                PostgraceButton(
                    "Execute Anyway",
                    variant: .destructive,
                    shortcutText: "⌘↵"
                ) {
                    onConfirm()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .background(PostgraceTheme.surface)
    }
}
