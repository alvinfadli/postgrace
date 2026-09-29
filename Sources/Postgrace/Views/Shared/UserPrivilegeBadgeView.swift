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
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundColor(PostgraceTheme.purpleSuper)
                        Text("Superuser")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(PostgraceTheme.purpleSuper)
                    } else if isReadOnly(privs) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(PostgraceTheme.amberRo)
                        Text("Read-Only")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(PostgraceTheme.amberRo)
                    } else {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(PostgraceTheme.emeraldRw)
                        Text("Read-Write")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(PostgraceTheme.emeraldRw)
                    }

                    Text("(\(privs.username))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(badgeBackgroundColor(privs))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(badgeBorderColor(privs), lineWidth: PostgraceTheme.hairlineBorder)
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
            return PostgraceTheme.purpleSuperMuted
        } else if isReadOnly(privs) {
            return PostgraceTheme.amberRoMuted
        } else {
            return PostgraceTheme.emeraldRwMuted
        }
    }

    private func badgeBorderColor(_ privs: UserPrivilegeInfo) -> Color {
        if privs.isSuperuser {
            return PostgraceTheme.purpleSuper.opacity(0.35)
        } else if isReadOnly(privs) {
            return PostgraceTheme.amberRo.opacity(0.35)
        } else {
            return PostgraceTheme.emeraldRw.opacity(0.35)
        }
    }

    // MARK: - Detailed Privileges Popover

    @ViewBuilder
    private func userPrivilegesPopover(_ privs: UserPrivilegeInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: privs.isSuperuser ? "crown.fill" : (isReadOnly(privs) ? "lock.fill" : "pencil"))
                    .foregroundColor(privs.isSuperuser ? PostgraceTheme.purpleSuper : (isReadOnly(privs) ? PostgraceTheme.amberRo : PostgraceTheme.emeraldRw))
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(privs.username)
                        .font(.headline)
                    Text(privs.isSuperuser ? "PostgreSQL Superuser" : (isReadOnly(privs) ? "Read-Only Analyst (SELECT)" : "Application Developer (CRUD)"))
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
                                            .foregroundColor(PostgraceTheme.accentSky)
                                        Text(schemaName)
                                            .font(.caption)
                                        Spacer()
                                        if perm.canCreate {
                                            Text("CREATE")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(PostgraceTheme.emeraldRw)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(PostgraceTheme.emeraldRwMuted)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }
                                        if perm.canUsage {
                                            Text("USAGE")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(PostgraceTheme.accentSky)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(PostgraceTheme.accentSkyMuted)
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
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(PostgraceTheme.amberRo)
                        .font(.caption)
                    Text("Read-only mode active: Table/schema creation, DDL modifications, drop, and truncation are disabled.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(PostgraceTheme.amberRoMuted)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(PostgraceTheme.surfaceElevated)
    }

    private func capabilityItem(title: String, enabled: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: enabled ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(enabled ? PostgraceTheme.emeraldRw : .secondary)
                .font(.caption)
            Text(title)
                .font(.caption2)
                .foregroundColor(enabled ? .primary : .secondary)
        }
    }
}
