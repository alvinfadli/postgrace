import SwiftUI

/// Compact studio toggle switch strictly adhering to the Postgrace Design System.
/// Replaces standard macOS sliding toggles.
public struct PostgraceToggle: View {
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
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                if let title = title {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isEnabled ? .primary : .secondary.opacity(0.6))

                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }

                // Studio Switch Element
                switchElement
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var switchElement: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            // Pill track (34 x 18)
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(trackBackground)
                .frame(width: 34, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(trackBorder, lineWidth: PostgraceTheme.hairlineBorder)
                )

            // Circle Thumb (14 x 14)
            Circle()
                .fill(Color.white)
                .frame(width: 14, height: 14)
                .padding(.horizontal, 2)
                .shadow(color: Color.black.opacity(0.08), radius: 1.5, y: 1)
        }
        .frame(width: 34, height: 18)
    }

    private var trackBackground: Color {
        guard isEnabled else { return PostgraceTheme.surfaceElevated.opacity(0.5) }
        if isOn {
            return isHovered ? PostgraceTheme.accentSage.opacity(0.9) : PostgraceTheme.accentSage
        } else {
            return isHovered ? PostgraceTheme.surfaceHover : PostgraceTheme.surfaceElevated
        }
    }

    private var trackBorder: Color {
        guard isEnabled else { return PostgraceTheme.border.opacity(0.4) }
        if isOn {
            return Color.black.opacity(0.08)
        } else {
            return isHovered ? PostgraceTheme.border.opacity(0.9) : PostgraceTheme.border
        }
    }
}
