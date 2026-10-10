import SwiftUI

/// Preset sizes for Postgrace continuous loading spinners.
public enum PostgraceSpinnerSize: CGFloat {
    case mini = 12
    case small = 16
    case medium = 24
    case large = 36

    var strokeWidth: CGFloat {
        switch self {
        case .mini: return 1.75
        case .small: return 2.0
        case .medium: return 2.5
        case .large: return 3.2
        }
    }
}

/// Continuous rotating emerald arc loader replacing default macOS spinning gear / flower.
public struct PostgraceSpinner: View {
    private let size: PostgraceSpinnerSize
    private let color: Color?

    @State private var isAnimating = false

    public init(size: PostgraceSpinnerSize = .small, color: Color? = nil) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        ZStack {
            // Background guide track (18% opacity)
            Circle()
                .stroke(
                    (color ?? PostgraceTheme.accentSage).opacity(0.18),
                    lineWidth: size.strokeWidth
                )

            // Active rotating sweep arc (90 degrees)
            Circle()
                .trim(from: 0.0, to: 0.3)
                .stroke(
                    color ?? PostgraceTheme.accentSage,
                    style: StrokeStyle(lineWidth: size.strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(isAnimating ? 360 : 0))
        }
        .frame(width: size.rawValue, height: size.rawValue)
        .onAppear {
            withAnimation(
                .linear(duration: 0.85)
                .repeatForever(autoreverses: false)
            ) {
                isAnimating = true
            }
        }
    }
}
