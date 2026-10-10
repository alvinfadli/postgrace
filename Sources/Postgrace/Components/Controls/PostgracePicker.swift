import SwiftUI

/// Bespoke dropdown picker replacing standard macOS popup menus and Cocoa pickers.
public struct PostgracePicker<T: Hashable>: View {
    @Binding private var selection: T
    private let items: [T]
    private let titleFor: (T) -> String
    private let iconFor: ((T) -> String?)?

    @State private var isHovered: Bool = false

    public init(
        selection: Binding<T>,
        items: [T],
        titleFor: @escaping (T) -> String,
        iconFor: ((T) -> String?)? = nil
    ) {
        self._selection = selection
        self.items = items
        self.titleFor = titleFor
        self.iconFor = iconFor
    }

    public var body: some View {
        Menu {
            ForEach(items, id: \.self) { item in
                Button {
                    selection = item
                } label: {
                    HStack {
                        if item == selection {
                            Image(systemName: "checkmark")
                        }
                        if let icon = iconFor?(item) {
                            Image(systemName: icon)
                        }
                        Text(titleFor(item))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let icon = iconFor?(selection) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                        .foregroundColor(PostgraceTheme.accentEmerald)
                }

                Text(titleFor(selection))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5.5)
            .background(isHovered ? PostgraceTheme.surfaceHover : PostgraceTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                    .stroke(isHovered ? PostgraceTheme.accentMint.opacity(0.35) : PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}
