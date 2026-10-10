import SwiftUI

/// Distinct visual variants for Postgrace bespoke buttons.
public enum PostgraceButtonVariant {
    /// High-contrast signature Emerald Green CTA fill.
    case primary
    /// Elevated graphite card with subtle hairline border.
    case secondary
    /// High-visibility crimson warning/destructive fill.
    case destructive
    /// Transparent background with subtle hover luminance.
    case ghost
}

/// Sizing tiers for Postgrace bespoke buttons.
public enum PostgraceButtonSize {
    case small
    case regular
    case large

    var verticalPadding: CGFloat {
        switch self {
        case .small: return 4
        case .regular: return 6
        case .large: return 9
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .small: return 8
        case .regular: return 12
        case .large: return 16
        }
    }

    var fontSize: CGFloat {
        switch self {
        case .small: return 11
        case .regular: return 12
        case .large: return 13
        }
    }

    var fontWeight: Font.Weight {
        switch self {
        case .small: return .medium
        case .regular: return .semibold
        case .large: return .bold
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .small: return 5
        case .regular: return PostgraceTheme.cornerRadiusButton
        case .large: return 8
        }
    }
}

/// Primary bespoke button component strictly adhering to the Postgrace Design System.
/// Replaces all default macOS native blue push buttons and prominent styles.
public struct PostgraceButton: View {
    private let title: String
    private let icon: String?
    private let variant: PostgraceButtonVariant
    private let size: PostgraceButtonSize
    private let isLoading: Bool
    private let shortcutText: String?
    private let isFullWidth: Bool
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered: Bool = false

    public init(
        _ title: String,
        icon: String? = nil,
        variant: PostgraceButtonVariant = .primary,
        size: PostgraceButtonSize = .regular,
        isLoading: Bool = false,
        shortcutText: String? = nil,
        isFullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.size = size
        self.isLoading = isLoading
        self.shortcutText = shortcutText
        self.isFullWidth = isFullWidth
        self.action = action
    }

    public var body: some View {
        Button(action: {
            guard !isLoading else { return }
            action()
        }) {
            HStack(spacing: 5) {
                if isLoading {
                    PostgraceSpinner(size: .mini, color: foregroundColor)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: size.fontSize, weight: size.fontWeight))
                }

                Text(title)
                    .font(.system(size: size.fontSize, weight: size.fontWeight))

                if let shortcut = shortcutText {
                    Text(shortcut)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(shortcutBackground)
                        .foregroundColor(shortcutForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .foregroundColor(foregroundColor)
            .padding(.vertical, size.verticalPadding)
            .padding(.horizontal, size.horizontalPadding)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(backgroundView)
            .clipShape(RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: PostgraceTheme.hairlineBorder)
            )
            .contentShape(Rectangle())
            .shadow(color: Color.black.opacity(isEnabled && variant != .ghost ? 0.04 : 0), radius: 1, y: 1)
        }
        .buttonStyle(PostgraceTactileButtonStyle())
        .disabled(!isEnabled || isLoading)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    // MARK: - Dynamic Appearance Tokens

    private var foregroundColor: Color {
        guard isEnabled else { return .secondary.opacity(0.6) }
        switch variant {
        case .primary, .destructive:
            return .white
        case .secondary:
            return .primary
        case .ghost:
            return isHovered ? .primary : .secondary
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if !isEnabled {
            PostgraceTheme.surfaceElevated.opacity(0.5)
        } else {
            switch variant {
            case .primary:
                PostgraceTheme.accentSage
                    .brightness(isHovered ? -0.04 : 0)
            case .secondary:
                isHovered ? PostgraceTheme.surfaceHover : PostgraceTheme.surfaceElevated
            case .destructive:
                PostgraceTheme.destructiveRed
                    .brightness(isHovered ? -0.04 : 0)
            case .ghost:
                isHovered ? PostgraceTheme.surfaceHover : Color.clear
            }
        }
    }

    private var borderColor: Color {
        guard isEnabled else { return PostgraceTheme.border.opacity(0.4) }
        switch variant {
        case .primary, .destructive:
            return Color.black.opacity(0.08)
        case .secondary:
            return isHovered ? PostgraceTheme.border.opacity(0.8) : PostgraceTheme.border
        case .ghost:
            return isHovered ? PostgraceTheme.border : Color.clear
        }
    }

    private var glowColor: Color {
        .clear
    }

    private var shortcutBackground: Color {
        switch variant {
        case .primary:
            return Color.black.opacity(0.2)
        case .destructive:
            return Color.black.opacity(0.2)
        case .secondary, .ghost:
            return PostgraceTheme.surfaceHover
        }
    }

    private var shortcutForeground: Color {
        switch variant {
        case .primary, .destructive:
            return Color.white.opacity(0.85)
        case .secondary, .ghost:
            return .secondary
        }
    }
}
