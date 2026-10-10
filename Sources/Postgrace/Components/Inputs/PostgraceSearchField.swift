import SwiftUI

/// Bespoke search field with integrated search icon, clear button, and shortcut badge.
public struct PostgraceSearchField: View {
    @Binding private var text: String
    private let placeholder: String
    private let shortcutText: String?

    @FocusState private var isFocused: Bool
    @State private var isHovered: Bool = false

    public init(
        _ placeholder: String = "Search…",
        text: Binding<String>,
        shortcutText: String? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.shortcutText = shortcutText
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(isFocused ? PostgraceTheme.accentSage : .secondary)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.65))
                }

                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .focused($isFocused)
                    .focusEffectDisabled()
            }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            } else if let shortcut = shortcutText {
                Text(shortcut)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(PostgraceTheme.surfaceHover)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(PostgraceTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                .stroke(strokeColor, lineWidth: isFocused ? 1.5 : PostgraceTheme.hairlineBorder)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 1, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var strokeColor: Color {
        if isFocused {
            return PostgraceTheme.accentSage
        } else if isHovered {
            return PostgraceTheme.border.opacity(0.85)
        } else {
            return PostgraceTheme.border
        }
    }
}
