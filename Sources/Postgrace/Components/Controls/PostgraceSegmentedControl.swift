import SwiftUI

/// Bespoke segmented control replacing default macOS `pickerStyle(.segmented)`.
/// Renders a dark graphite track with smooth item highlights and hover transitions.
public struct PostgraceSegmentedControl<T: Hashable>: View {
    @Binding private var selection: T
    private let items: [T]
    private let titleFor: (T) -> String
    private let iconFor: ((T) -> String?)?

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
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                SegmentButton(
                    item: item,
                    isSelected: selection == item,
                    title: titleFor(item),
                    icon: iconFor?(item)
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selection = item
                    }
                }
            }
        }
        .padding(2)
        .background(PostgraceTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
        )
    }

    private struct SegmentButton: View {
        let item: T
        let isSelected: Bool
        let title: String
        let icon: String?
        let onSelect: () -> Void

        @State private var isHovered: Bool = false

        var body: some View {
            Button(action: onSelect) {
                HStack(spacing: 4) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    }
                    Text(title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                }
                .foregroundColor(isSelected ? PostgraceTheme.accentEmerald : (isHovered ? .primary : .secondary))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(
                    isSelected
                        ? PostgraceTheme.surfaceElevated
                        : (isHovered ? PostgraceTheme.surfaceHover : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? PostgraceTheme.border : Color.clear, lineWidth: PostgraceTheme.hairlineBorder)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
}
