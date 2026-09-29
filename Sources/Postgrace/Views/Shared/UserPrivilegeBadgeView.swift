import SwiftUI

/// Toolbar badge indicating the connected user's PostgreSQL role & privilege tier.
/// Displays an interactive popover with fine-grained schema and object grants.
struct UserPrivilegeBadgeView: View {
    @Environment(SchemaViewModel.self) private var schemaViewModel
    @State private var showingDetailsPopover: Bool = false

    var body: some View {
        if let privs = schemaViewModel.userPrivileges {
            Button {
                showingDetailsPopover.toggle()
            } label: {
                HStack(spacing: 5) {
                    if privs.isSuperuser {
                        Text("👑")
                            .font(.system(size: 11))
                        Text("Superuser")
                            .font(.caption.bold())
                            .foregroundColor(.purple)
                    } else if isReadOnly(privs) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("Read-Only")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 10))
                            .foregroundColor(.accentColor)
                        Text("Read-Write")
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                    }

                    Text("(\(privs.username))")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(badgeBackgroundColor(privs))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(badgeBorderColor(privs), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDetailsPopover, arrowEdge: .bottom) {
                userPrivilegesPopover(privs)
            }
            .help("User Privileges: \(privs.username)")
        }
    }

    private func isReadOnly(_ privs: UserPrivilegeInfo) -> Bool {
        if privs.isSuperuser { return false }
        if privs.canCreateSchemaInDb { return false }
        let hasAnyCreate = privs.schemaPrivileges.values.contains { $0.canCreate }
        return !hasAnyCreate
    }

    private func badgeBackgroundColor(_ privs: UserPrivilegeInfo) -> Color {
        if privs.isSuperuser {
            return Color.purple.opacity(0.12)
        } else if isReadOnly(privs) {
            return Color.orange.opacity(0.12)
        } else {
            return Color.blue.opacity(0.10)
        }
    }

    private func badgeBorderColor(_ privs: UserPrivilegeInfo) -> Color {
        if privs.isSuperuser {
            return Color.purple.opacity(0.3)
        } else if isReadOnly(privs) {
            return Color.orange.opacity(0.3)
        } else {
            return Color.blue.opacity(0.25)
        }
    }

    // MARK: - Detailed Privileges Popover

    @ViewBuilder
    private func userPrivilegesPopover(_ privs: UserPrivilegeInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: privs.isSuperuser ? "crown.fill" : "person.badge.shield.checkmark")
                    .foregroundColor(privs.isSuperuser ? .purple : .accentColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(privs.username)
                        .font(.headline)
                    Text(privs.isSuperuser ? "PostgreSQL Superuser" : "Standard Database Role")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Role Capabilities")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                HStack {
                    capabilityItem(title: "Superuser", enabled: privs.isSuperuser)
                    Spacer()
                    capabilityItem(title: "Create DB", enabled: privs.canCreateDb)
                    Spacer()
                    capabilityItem(title: "Create Schema", enabled: privs.canCreateSchemaInDb)
                }
            }

            if !privs.schemaPrivileges.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Schema Permissions")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(privs.schemaPrivileges.keys.sorted(), id: \.self) { schemaName in
                                if let perm = privs.schemaPrivileges[schemaName] {
                                    HStack {
                                        Image(systemName: "folder")
                                            .font(.caption)
                                            .foregroundColor(.accentColor)
                                        Text(schemaName)
                                            .font(.caption)
                                        Spacer()
                                        if perm.canCreate {
                                            Text("CREATE")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.green)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.15))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                        if perm.canUsage {
                                            Text("USAGE")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.blue)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.blue.opacity(0.15))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            if isReadOnly(privs) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Read-only role: Table and schema creation, modification, drop, and truncation are disabled.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func capabilityItem(title: String, enabled: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(enabled ? .green : .secondary)
                .font(.caption)
            Text(title)
                .font(.caption2)
                .foregroundColor(enabled ? .primary : .secondary)
        }
    }
}
