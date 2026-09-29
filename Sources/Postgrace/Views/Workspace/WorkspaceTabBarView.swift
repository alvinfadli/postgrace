import SwiftUI

/// Native macOS document-style tab bar allowing multiple table and query tabs.
struct WorkspaceTabBarView: View {
    @Environment(WorkspaceTabViewModel.self) private var tabViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(tabViewModel.tabs) { tab in
                    tabItem(tab)
                }

                // Add query tab button (+)
                Button {
                    tabViewModel.openQueryTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .help("New Query Tab (⌘T)")
                .keyboardShortcut("t", modifiers: [.command])

                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .border(Color(NSColor.separatorColor), width: 0.5)
    }

    @ViewBuilder
    private func tabItem(_ tab: WorkspaceTab) -> some View {
        let isActive = tabViewModel.activeTabId == tab.id

        HStack(spacing: 6) {
            Image(systemName: iconForTab(tab.type))
                .font(.system(size: 11))
                .foregroundColor(isActive ? .accentColor : .secondary)

            Text(tab.title)
                .font(.caption)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)

            // Close button
            Button {
                tabViewModel.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(2)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isActive ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            tabViewModel.activeTabId = tab.id
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
        case .query: return "bolt.fill"
        case .structure: return "list.bullet.rectangle"
        }
    }
}
