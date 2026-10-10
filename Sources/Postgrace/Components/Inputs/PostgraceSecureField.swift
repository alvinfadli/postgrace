import SwiftUI

/// Bespoke secure password field with integrated show/hide toggle.
/// Replaces standard macOS SecureField.
public struct PostgraceSecureField: View {
    @Binding private var text: String
    private let placeholder: String
    private let icon: String?

    @State private var isRevealed: Bool = false
    @FocusState private var isFocused: Bool
    @State private var isHovered: Bool = false

    public init(
        _ placeholder: String = "Password",
        text: Binding<String>,
        icon: String? = "lock.fill"
    ) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 7) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(isFocused ? PostgraceTheme.accentMint : .secondary)
                    .frame(width: 14)
            }

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.65))
                }

                if isRevealed {
                    TextField("", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.primary)
                        .focused($isFocused)
                        .focusEffectDisabled()
                } else {
                    SecureField("", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .focused($isFocused)
                        .focusEffectDisabled()
                }
            }

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(isRevealed ? "Hide password" : "Show password")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(PostgraceTheme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusButton, style: .continuous)
                .stroke(strokeColor, lineWidth: isFocused ? 1.5 : PostgraceTheme.hairlineBorder)
        )
        .shadow(color: isFocused ? PostgraceTheme.accentMint.opacity(0.18) : .clear, radius: 4)
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
            return PostgraceTheme.accentMint
        } else if isHovered {
            return PostgraceTheme.border.opacity(0.85)
        } else {
            return PostgraceTheme.border
        }
    }
}
