import SwiftUI
import AppKit

// MARK: - Postgrace Modern Flat Design System & Color Tokens

public enum PostgraceTheme {
    
    // MARK: - Dynamic Adaptive Colors (Modern Flat)
    
    /// Main application window and full-bleed data canvas background (#111215 Dark / #FFFFFF Light)
    public static let canvas = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#111215") : NSColor(hex: "#FFFFFF")
    }))
    
    /// Sidebar, toolbar chrome, and secondary surfaces (#16181D Dark / #F8FAFC Light)
    public static let surface = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#16181D") : NSColor(hex: "#F8FAFC")
    }))
    
    /// Elevated cards, popovers, active tabs, and modals (#1E2128 Dark / #F1F5F9 Light)
    public static let surfaceElevated = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#1E2128") : NSColor(hex: "#F1F5F9")
    }))
    
    /// Hover surface tint for interactive list items & buttons (#252830 Dark / #E2E8F0 Light)
    public static let surfaceHover = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#252830") : NSColor(hex: "#E2E8F0")
    }))
    
    /// Crisp flat hairline borders and structural dividers (#2B2F38 Dark / #E2E8F0 Light)
    public static let border = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#2B2F38") : NSColor(hex: "#E2E8F0")
    }))
    
    /// Subtle flat sub-dividers (#22252C Dark / #F1F5F9 Light)
    public static let borderSubtle = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#22252C") : NSColor(hex: "#F1F5F9")
    }))
    
    // MARK: - Semantic Modern Flat Accent Tokens
    
    /// Primary Brand Flat Cobalt Blue (#3B82F6 Dark / #2563EB Light)
    public static let accentSky = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#3B82F6") : NSColor(hex: "#2563EB")
    }))
    
    public static let accentSkyMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#3B82F6").withAlphaComponent(0.12) : NSColor(hex: "#2563EB").withAlphaComponent(0.10)
    }))
    
    /// Superuser Flat Indigo Tier (#6366F1 Dark / #4F46E5 Light)
    public static let purpleSuper = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#6366F1") : NSColor(hex: "#4F46E5")
    }))
    
    public static let purpleSuperMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#6366F1").withAlphaComponent(0.12) : NSColor(hex: "#4F46E5").withAlphaComponent(0.10)
    }))
    
    /// Read-Write Flat Emerald Tier (#10B981 Dark / #059669 Light)
    public static let emeraldRw = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#10B981") : NSColor(hex: "#059669")
    }))
    
    public static let emeraldRwMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#10B981").withAlphaComponent(0.12) : NSColor(hex: "#059669").withAlphaComponent(0.10)
    }))
    
    /// Read-Only Flat Amber Tier (#F59E0B Dark / #D97706 Light)
    public static let amberRo = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#F59E0B") : NSColor(hex: "#D97706")
    }))
    
    public static let amberRoMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#F59E0B").withAlphaComponent(0.12) : NSColor(hex: "#D97706").withAlphaComponent(0.10)
    }))
    
    /// Destructive Flat Crimson Tier (#EF4444 Dark / #DC2626 Light)
    public static let destructiveRed = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#EF4444") : NSColor(hex: "#DC2626")
    }))
    
    public static let destructiveRedMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#EF4444").withAlphaComponent(0.12) : NSColor(hex: "#DC2626").withAlphaComponent(0.10)
    }))
    
    // MARK: - Typography & Geometry Tokens
    
    public static let cornerRadiusPill: CGFloat = 9999
    public static let cornerRadiusCard: CGFloat = 10
    public static let cornerRadiusButton: CGFloat = 6
    public static let cornerRadiusWindow: CGFloat = 14
    public static let hairlineBorder: CGFloat = 1.0
    public static let standardBorder: CGFloat = 1.0
}

// MARK: - NSColor & NSAppearance Extensions

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension NSColor {
    convenience init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

// MARK: - Reusable Modern Flat Postgrace View Modifiers

public struct PostgraceCardModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(PostgraceTheme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusCard, style: .continuous)
                    .stroke(PostgraceTheme.border, lineWidth: PostgraceTheme.hairlineBorder)
            )
    }
}

public struct PostgracePillModifier: ViewModifier {
    let background: Color
    let border: Color

    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(border, lineWidth: PostgraceTheme.hairlineBorder)
            )
    }
}

extension View {
    public func postgraceCard() -> some View {
        modifier(PostgraceCardModifier())
    }

    public func postgracePill(background: Color, border: Color) -> some View {
        modifier(PostgracePillModifier(background: background, border: border))
    }
}
