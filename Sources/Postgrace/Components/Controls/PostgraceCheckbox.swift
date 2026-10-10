import SwiftUI

/// Bespoke checkbox control with pastel sage fill and sharp vector checkmark.
/// Replaces standard macOS checkboxes.
public struct PostgraceCheckbox: View {
    @Binding private var isOn: Bool
    private let title: String?
    private let subtitle: String?

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered: Bool = false

    public init(
        _ title: String? = nil,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        Button {
            guard isEnabled else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.75)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                // Square Checkbox box (16 x 16)
                checkboxBox

                if let title = title {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.6))

                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var checkboxBox: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(boxBackground)
                .frame(width: 16, height: 16)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(boxBorder, lineWidth: PostgraceTheme.hairlineBorder)
                )

            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 16, height: 16)
    }

    private var boxBackground: Color {
        guard isEnabled else { return PostgraceTheme.surfaceElevated.opacity(0.5) }
        if isOn {
            return isHovered ? PostgraceTheme.accentSage.opacity(0.9) : PostgraceTheme.accentSage
        } else {
            return isHovered ? PostgraceTheme.surfaceHover : PostgraceTheme.surfaceElevated
        }
    }

    private var boxBorder: Color {
        guard isEnabled else { return PostgraceTheme.border.opacity(0.4) }
        if isOn {
            return Color.black.opacity(0.08)
        } else if isHovered {
            return PostgraceTheme.border.opacity(0.85)
        } else {
            return PostgraceTheme.border
        }
    }
}
