import SwiftUI

/// Distinct shapes and visual weights for icon buttons.
public enum PostgraceIconButtonVariant {
    case standard
    case prominent
    case destructive
    case ghost
}

/// Compact bespoke icon button strictly adhering to Postgrace Design Tokens.
public struct PostgraceIconButton: View {
    private let icon: String
    private let tooltip: String?
    private let variant: PostgraceIconButtonVariant
    private let size: CGFloat
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered: Bool = false

    public init(
        icon: String,
        tooltip: String? = nil,
        variant: PostgraceIconButtonVariant = .standard,
        size: CGFloat = 26,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.tooltip = tooltip
        self.variant = variant
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .background(backgroundView)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(borderColor, lineWidth: PostgraceTheme.hairlineBorder)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PostgraceTactileButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip ?? "")
    }

    private var foregroundColor: Color {
        guard isEnabled else { return .secondary.opacity(0.5) }
        switch variant {
        case .standard:
            return isHovered ? .primary : .secondary
        case .prominent:
            return .white
        case .destructive:
            return isHovered ? PostgraceTheme.destructiveRed : .secondary
        case .ghost:
            return isHovered ? .primary : .secondary
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch variant {
        case .standard:
            isHovered ? PostgraceTheme.surfaceHover : PostgraceTheme.surfaceElevated
        case .prominent:
            PostgraceTheme.accentEmerald
                .brightness(isHovered ? 0.05 : 0)
        case .destructive:
            isHovered ? PostgraceTheme.destructiveRedMuted : Color.clear
        case .ghost:
            isHovered ? PostgraceTheme.surfaceHover : Color.clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .standard:
            return isHovered ? PostgraceTheme.accentMint.opacity(0.3) : PostgraceTheme.border
        case .prominent:
            return PostgraceTheme.accentMint.opacity(0.3)
        case .destructive:
            return isHovered ? PostgraceTheme.destructiveRed.opacity(0.4) : Color.clear
        case .ghost:
            return isHovered ? PostgraceTheme.border : Color.clear
        }
    }
}
