import SwiftUI

/// Bespoke modal header with title, icon, subtitle badge, and close button.
public struct PostgraceModalHeader: View {
    private let title: String
    private let subtitle: String?
    private let icon: String?
    private let onDismiss: (() -> Void)?

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(PostgraceTheme.accentEmerald)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let dismiss = onDismiss {
                PostgraceIconButton(
                    icon: "xmark",
                    tooltip: "Close",
                    variant: .ghost,
                    size: 22,
                    action: dismiss
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(PostgraceTheme.surface)
        .overlay(
            Rectangle()
                .fill(PostgraceTheme.border)
                .frame(height: PostgraceTheme.hairlineBorder),
            alignment: .bottom
        )
    }
}
