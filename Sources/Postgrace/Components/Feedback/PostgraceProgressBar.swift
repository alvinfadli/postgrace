import SwiftUI

/// Flat studio progress bar adhering strictly to Postgrace theme tokens.
public struct PostgraceProgressBar: View {
    private let progress: Double // 0.0 ... 1.0
    private let height: CGFloat
    private let showPercentLabel: Bool

    public init(progress: Double, height: CGFloat = 4, showPercentLabel: Bool = false) {
        self.progress = max(0.0, min(1.0, progress))
        self.height = height
        self.showPercentLabel = showPercentLabel
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(PostgraceTheme.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: height / 2)
                                .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
                        )

                    // Fill
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(PostgraceTheme.accentEmerald)
                        .frame(width: geo.size.width * CGFloat(progress))
                        .animation(.easeOut(duration: 0.2), value: progress)
                }
            }
            .frame(height: height)

            if showPercentLabel {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
}
