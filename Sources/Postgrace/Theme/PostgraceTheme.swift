import SwiftUI
import AppKit

// MARK: - Postgrace Brand Design System & Color Tokens

public enum PostgraceTheme {
    
    // MARK: - Dynamic Adaptive Colors
    
    /// Main application window and full-bleed data canvas background (#0D0F12 Dark / #FFFFFF Light)
    public static let canvas = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#0D0F12") : NSColor(hex: "#FFFFFF")
    }))
    
    /// Sidebar, toolbar chrome, and secondary surfaces (#14171D Dark / #F8FAFC Light)
    public static let surface = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#14171D") : NSColor(hex: "#F8FAFC")
    }))
    
    /// Elevated cards, popovers, active tabs, and modals (#1B1F27 Dark / #F1F5F9 Light)
    public static let surfaceElevated = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#1B1F27") : NSColor(hex: "#F1F5F9")
    }))
    
    /// Hover surface tint for interactive list items & buttons (#222733 Dark / #E2E8F0 Light)
    public static let surfaceHover = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#222733") : NSColor(hex: "#E2E8F0")
    }))
    
    /// Crisp micro-borders and structural dividers (#262C36 Dark / #E2E8F0 Light)
    public static let border = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#262C36") : NSColor(hex: "#E2E8F0")
    }))
    
    /// Subtle sub-dividers (#1E232B Dark / #F1F5F9 Light)
    public static let borderSubtle = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#1E232B") : NSColor(hex: "#F1F5F9")
    }))
    
    // MARK: - Semantic Accent Tokens
    
    /// Primary Brand Sky Cyan (#0284C7 / #38BDF8)
    public static let accentSky = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#38BDF8") : NSColor(hex: "#0284C7")
    }))
    
    public static let accentSkyMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#0284C7").withAlphaComponent(0.18) : NSColor(hex: "#0284C7").withAlphaComponent(0.12)
    }))
    
    /// Superuser Purple Tier (#A78BFA Dark / #8B5CF6 Light)
    public static let purpleSuper = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#A78BFA") : NSColor(hex: "#8B5CF6")
    }))
    
    public static let purpleSuperMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#8B5CF6").withAlphaComponent(0.18) : NSColor(hex: "#8B5CF6").withAlphaComponent(0.12)
    }))
    
    /// Read-Write Emerald Tier (#34D399 Dark / #10B981 Light)
    public static let emeraldRw = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#34D399") : NSColor(hex: "#10B981")
    }))
    
    public static let emeraldRwMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#10B981").withAlphaComponent(0.18) : NSColor(hex: "#10B981").withAlphaComponent(0.12)
    }))
    
    /// Read-Only Amber Tier (#FBBF24 Dark / #F59E0B Light)
    public static let amberRo = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#FBBF24") : NSColor(hex: "#F59E0B")
    }))
    
    public static let amberRoMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#F59E0B").withAlphaComponent(0.18) : NSColor(hex: "#F59E0B").withAlphaComponent(0.12)
    }))
    
    /// Destructive Red Tier (#F87171 Dark / #EF4444 Light)
    public static let destructiveRed = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#F87171") : NSColor(hex: "#EF4444")
    }))
    
    public static let destructiveRedMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#EF4444").withAlphaComponent(0.18) : NSColor(hex: "#EF4444").withAlphaComponent(0.12)
    }))
    
    // MARK: - Typography & Geometry Tokens
    
    public static let cornerRadiusPill: CGFloat = 9999
    public static let cornerRadiusCard: CGFloat = 12
    public static let cornerRadiusButton: CGFloat = 6
    public static let cornerRadiusWindow: CGFloat = 16
    public static let hairlineBorder: CGFloat = 0.5
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

// MARK: - Reusable Modern Postgrace View Modifiers

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
