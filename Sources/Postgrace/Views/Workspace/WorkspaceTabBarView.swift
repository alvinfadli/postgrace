import SwiftUI

/// Custom document-style tab bar matching the design artifact.
/// Features top accent line on active tab, dark canvas background, and smooth hover states.
struct WorkspaceTabBarView: View {
    @Environment(WorkspaceTabViewModel.self) private var tabViewModel
    @State private var hoveredTabId: UUID? = nil

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(tabViewModel.tabs) { tab in
                        tabItemView(tab)
                    }

                    // New query tab (+) action
                    Button {
                        tabViewModel.openQueryTab()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .help("New Query Tab (⌘T)")
                    .keyboardShortcut("t", modifiers: [.command])

                    Spacer(minLength: 0)
                }
                .padding(.leading, 4)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .background(PostgraceTheme.surface)
        .overlay(
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder),
            alignment: .bottom
        )
    }

    // MARK: - Tab Item

    @ViewBuilder
    private func tabItemView(_ tab: WorkspaceTab) -> some View {
        let isActive = tabViewModel.activeTabId == tab.id
        let isHovered = hoveredTabId == tab.id

        HStack(spacing: 0) {
            Button {
                tabViewModel.activeTabId = tab.id
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: iconForTab(tab.type))
                        .font(.system(size: 10))
                        .foregroundColor(isActive ? PostgraceTheme.accentSky : .secondary)

                    Text(tab.title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .frame(height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Close button (xmark)
            Button {
                tabViewModel.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isActive ? .secondary : .secondary.opacity(0.6))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .opacity(isActive || isHovered ? 1.0 : 0.0)
        }
        .frame(height: 34)
        .background(isActive ? PostgraceTheme.canvas : (isHovered ? PostgraceTheme.surfaceElevated : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            // Top Accent Line on Active Tab (matching artifact border-t-2 border-t-sky-500)
            Rectangle()
                .fill(isActive ? PostgraceTheme.accentSky : Color.clear)
                .frame(height: 2),
            alignment: .top
        )
        .onHover { hovering in
            hoveredTabId = hovering ? tab.id : nil
        }
        .contextMenu {
            Button("Close Tab") {
                tabViewModel.closeTab(id: tab.id)
            }
            Button("Close Other Tabs") {
                tabViewModel.closeOtherTabs(id: tab.id)
            }
        }
    }

    private func iconForTab(_ type: TabType) -> String {
        switch type {
        case .table: return "tablecells"
        case .query: return "terminal"
        case .structure: return "list.bullet.rectangle"
        case .schemas: return "square.3.layers.3d"
        case .tables: return "tablecells"
        }
    }
}
