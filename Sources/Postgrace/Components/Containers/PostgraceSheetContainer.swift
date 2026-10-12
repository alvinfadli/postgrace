import SwiftUI

/// Standardized studio modal sheet container.
/// Replaces generic macOS sheet chrome with custom header, body, and fixed bottom action bar.
public struct PostgraceSheetContainer<Content: View, Footer: View>: View {
    private let title: String
    private let subtitle: String?
    private let icon: String?
    private let width: CGFloat
    private let height: CGFloat?
    private let onDismiss: (() -> Void)?
    private let content: Content
    private let footer: Footer

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String? = nil,
        width: CGFloat = 480,
        height: CGFloat? = nil,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.width = width
        self.height = height
        self.onDismiss = onDismiss
        self.content = content()
        self.footer = footer()
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            PostgraceModalHeader(
                title: title,
                subtitle: subtitle,
                icon: icon,
                onDismiss: onDismiss
            )

            // Scrollable / Adaptive Body Content
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(16)
            }

            // Fixed Footer
            VStack(spacing: 0) {
                Rectangle()
                    .fill(PostgraceTheme.border)
                    .frame(height: PostgraceTheme.hairlineBorder)

                HStack(spacing: 10) {
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(PostgraceTheme.surface)
            }
        }
        .frame(width: width)
        .frame(height: height)
        .background(PostgraceTheme.surface)
    }
}
