import SwiftUI

/// Popover allowing users to search and toggle column visibility in the table view.
public struct ColumnVisibilityPopoverView: View {
    let allColumns: [ResultColumn]
    let hiddenColumns: Set<String>
    let onToggleColumn: (String) -> Void
    let onShowAll: () -> Void
    let onHideAll: () -> Void

    @State private var searchText: String = ""

    public init(
        allColumns: [ResultColumn],
        hiddenColumns: Set<String>,
        onToggleColumn: @escaping (String) -> Void,
        onShowAll: @escaping () -> Void,
        onHideAll: @escaping () -> Void
    ) {
        self.allColumns = allColumns
        self.hiddenColumns = hiddenColumns
        self.onToggleColumn = onToggleColumn
        self.onShowAll = onShowAll
        self.onHideAll = onHideAll
    }

    private var filteredColumns: [ResultColumn] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return allColumns
        }
        return allColumns.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.dataTypeName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var visibleCount: Int {
        allColumns.count - hiddenColumns.count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PostgraceTheme.accentSky)

                Text("Columns")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                Text("\(visibleCount) of \(allColumns.count) visible")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Column Search Field
            PostgraceSearchField(
                "Search columns…",
                text: $searchText
            )

            // Quick Actions: Show All / Hide All
            HStack(spacing: 8) {
                Button {
                    onShowAll()
                } label: {
                    Text("Show All")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PostgraceTheme.accentSky)
                }
                .buttonStyle(.plain)

                Text("•")
                    .foregroundColor(PostgraceTheme.border)
                    .font(.system(size: 9))

                Button {
                    onHideAll()
                } label: {
                    Text("Hide All")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()
            }

            Divider()

            // Scrollable Column Checkbox List
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredColumns, id: \.name) { col in
                        let isVisible = !hiddenColumns.contains(col.name)
                        HStack(spacing: 6) {
                            PostgraceCheckbox(
                                isOn: Binding(
                                    get: { isVisible },
                                    set: { _ in onToggleColumn(col.name) }
                                )
                            )

                            Text(col.name)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(isVisible ? .primary : .secondary.opacity(0.6))
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            if !col.dataTypeName.isEmpty && col.dataTypeName != "unknown" {
                                Text(col.dataTypeName.lowercased())
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.trailing, 4)
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
        .frame(width: 250)
        .background(PostgraceTheme.surface)
    }
}
