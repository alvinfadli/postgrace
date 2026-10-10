import SwiftUI

/// Bespoke single-line text input adhering to the Postgrace Design System.
/// Replaces standard macOS TextField, eliminating default grey inset bezels and system blue focus rings.
public struct PostgraceTextField: View {
    @Binding private var text: String
    private let placeholder: String
    private let icon: String?
    private let isMonospaced: Bool
    private let showsClearButton: Bool

    @FocusState private var isFieldFocused: Bool
    @State private var isHovered: Bool = false

    public init(
        _ placeholder: String,
        text: Binding<String>,
        icon: String? = nil,
        isMonospaced: Bool = false,
        showsClearButton: Bool = true
    ) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
        self.isMonospaced = isMonospaced
        self.showsClearButton = showsClearButton
    }

    public var body: some View {
        HStack(spacing: 7) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(isFieldFocused ? PostgraceTheme.accentSage : .secondary)
                    .frame(width: 14)
            }

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
                        .foregroundColor(.secondary.opacity(0.65))
                }

                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(isMonospaced ? .system(size: 12, design: .monospaced) : .system(size: 12))
                    .foregroundColor(.primary)
                    .focused($isFieldFocused)
                    .focusEffectDisabled()
            }

            if showsClearButton && !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Clear")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(PostgraceTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                .stroke(strokeColor, lineWidth: isFieldFocused ? 1.5 : PostgraceTheme.hairlineBorder)
        )
        .shadow(color: Color.black.opacity(0.02), radius: 1, y: 1)
        .contentShape(Rectangle())
        .onTapGesture {
            isFieldFocused = true
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var strokeColor: Color {
        if isFieldFocused {
            return PostgraceTheme.accentSage
        } else if isHovered {
            return PostgraceTheme.border.opacity(0.85)
        } else {
            return PostgraceTheme.border
        }
    }
}
