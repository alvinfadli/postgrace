import SwiftUI
import AppKit

// MARK: - Postgrace White-First Pastel Atelier Design System & Color Tokens

public enum PostgraceTheme {
    
    // MARK: - Dynamic Adaptive Colors (White-First Pastel Atelier)
    
    /// Main application window and full-bleed data canvas background (#FFFFFF Light / #181A1E Dark)
    public static let canvas = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#181A1E") : NSColor(hex: "#FFFFFF")
    }))
    
    /// Sidebar, toolbar chrome, and secondary surfaces (#F8FAFC Light / #1E2127 Dark)
    public static let surface = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#1E2127") : NSColor(hex: "#F8FAFC")
    }))
    
    /// Elevated cards, popovers, active tabs, and modals (#FFFFFF Light / #262A32 Dark)
    public static let surfaceElevated = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#262A32") : NSColor(hex: "#FFFFFF")
    }))
    
    /// Hover surface tint for interactive list items & buttons (#F1F5F9 Light / #2D323C Dark)
    public static let surfaceHover = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#2D323C") : NSColor(hex: "#F1F5F9")
    }))
    
    /// Crisp flat hairline borders and structural dividers (#E2E8F0 Light / #333844 Dark)
    public static let border = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#333844") : NSColor(hex: "#E2E8F0")
    }))
    
    /// Subtle flat sub-dividers (#EEF2F6 Light / #2A2E38 Dark)
    public static let borderSubtle = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#2A2E38") : NSColor(hex: "#EEF2F6")
    }))
    
    // MARK: - Semantic Crisp Pastel Accent Tokens (Zero Neon, Confident & Sharp)
    
    /// Signature Crisp Botanical Sage Green Accent (#3B7A57 Light / #5E9E7A Dark)
    public static let accentSage = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#5E9E7A") : NSColor(hex: "#3B7A57")
    }))
    
    public static let accentSageMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#5E9E7A").withAlphaComponent(0.20) : NSColor(hex: "#E6F4EC")
    }))
    
    public static let accentSageText = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#6DB28B") : NSColor(hex: "#1D5333")
    }))
    
    /// Backward-compatible primary brand aliases pointing cleanly to Crisp Sage
    public static let accentEmerald = accentSage
    public static let accentEmeraldMuted = accentSageMuted
    public static let accentMint = accentSage
    public static let accentSky = accentSage
    public static let accentSkyMuted = accentSageMuted
    
    /// Superuser & Views: Crisp Slate Lavender (#5B589C Light / #8582C9 Dark)
    public static let purpleSuper = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#8582C9") : NSColor(hex: "#5B589C")
    }))
    
    public static let purpleSuperMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#8582C9").withAlphaComponent(0.20) : NSColor(hex: "#EEEDF9")
    }))
    
    public static let purpleSuperText = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#9F9CE0") : NSColor(hex: "#3C3A78")
    }))
    
    /// Read-Write Tier (Crisp Sage)
    public static let emeraldRw = accentSage
    public static let emeraldRwMuted = accentSageMuted
    
    /// Read-Only & Warnings: Crisp Warm Apricot (#C06A1C Light / #E58E45 Dark)
    public static let amberRo = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#E58E45") : NSColor(hex: "#C06A1C")
    }))
    
    public static let amberRoMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#E58E45").withAlphaComponent(0.20) : NSColor(hex: "#FDF2E7")
    }))
    
    public static let amberRoText = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#F2A15E") : NSColor(hex: "#7D3E08")
    }))
    
    /// Destructive & Errors: Crisp Soft Coral Crimson (#C54444 Light / #E26666 Dark)
    public static let destructiveRed = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#E26666") : NSColor(hex: "#C54444")
    }))
    
    public static let destructiveRedMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#E26666").withAlphaComponent(0.20) : NSColor(hex: "#FDECEC")
    }))
    
    public static let destructiveRedText = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#F08282") : NSColor(hex: "#842323")
    }))
    
    /// External FDW & Remote Tables: Crisp Slate Sky (#2F7B9E Light / #5BA8CE Dark)
    public static let pastelSky = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#5BA8CE") : NSColor(hex: "#2F7B9E")
    }))
    
    public static let pastelSkyMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#5BA8CE").withAlphaComponent(0.20) : NSColor(hex: "#E6F3F9")
    }))
    
    public static let pastelSkyText = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#72BFEC") : NSColor(hex: "#1B4F68")
    }))
    
    // MARK: - SQL Syntax Highlighting Tokens (FR-2.2 Pastel Theme Mapping)
    
    /// SQL Keywords (`SELECT`, `FROM`, `WHERE`, `JOIN`, `GROUP BY`, etc.): Royal Blue (#2563EB Light) / Pastel Sky Blue (#93C5FD Dark)
    public static let sqlKeywordNSColor = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#93C5FD") : NSColor(hex: "#2563EB")
    })
    public static let sqlKeyword = Color(nsColor: sqlKeywordNSColor)
    
    /// DDL/DML Commands (`INSERT`, `UPDATE`, `DELETE`, `CREATE`, `ALTER`, `DROP`, `TRUNCATE`): Crimson (#DC2626 Light) / Pastel Coral (#FCA5A5 Dark)
    public static let sqlCommandNSColor = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#FCA5A5") : NSColor(hex: "#DC2626")
    })
    public static let sqlCommand = Color(nsColor: sqlCommandNSColor)
    
    /// Data Types (`INT`, `BIGINT`, `VARCHAR`, `TEXT`, `BOOLEAN`, `TIMESTAMPTZ`, `JSONB`, `UUID`): Forest Mint (#059669 Light) / Pastel Mint (#A7F3D0 Dark)
    public static let sqlDataTypeNSColor = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#A7F3D0") : NSColor(hex: "#059669")
    })
    public static let sqlDataType = Color(nsColor: sqlDataTypeNSColor)
    
    /// Built-in Functions (`COUNT`, `SUM`, `AVG`, `NOW`, `COALESCE`, `DATE_TRUNC`): Warm Ochre (#D97706 Light) / Pastel Amber (#FDE047 Dark)
    public static let sqlFunctionNSColor = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#FDE047") : NSColor(hex: "#D97706")
    })
    public static let sqlFunction = Color(nsColor: sqlFunctionNSColor)
    
    /// String Literals (`'...'`, `$$...$$`): Rust Orange (#C2410C Light) / Pastel Peach (#FDBA74 Dark)
    public static let sqlStringNSColor = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#FDBA74") : NSColor(hex: "#C2410C")
    })
    public static let sqlString = Color(nsColor: sqlStringNSColor)
    
    /// Numeric, Boolean & Null Literals (`42`, `3.14`, `TRUE`, `FALSE`, `NULL`): Deep Violet (#7C3AED Light) / Pastel Lavender (#C4B5FD Dark)
    public static let sqlNumberNSColor = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#C4B5FD") : NSColor(hex: "#7C3AED")
    })
    public static let sqlNumber = Color(nsColor: sqlNumberNSColor)
    
    /// Identifiers (Schema, Table, Column names, `"quoted"`, `` `backtick` ``): Dark Slate (#1E293B Light) / Soft Slate (#E2E8F0 Dark)
    public static let sqlIdentifierNSColor = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#E2E8F0") : NSColor(hex: "#1E293B")
    })
    public static let sqlIdentifier = Color(nsColor: sqlIdentifierNSColor)
    
    /// Comments (`-- ...`, `# ...`, `/* ... */`): Cool Grey (#94A3B8 Light) / Muted Slate (#64748B Dark)
    public static let sqlCommentNSColor = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#64748B") : NSColor(hex: "#94A3B8")
    })
    public static let sqlComment = Color(nsColor: sqlCommentNSColor)
    
    /// Operators & Type Casts (`=`, `!=`, `<=`, `>=`, `::`, `->`, `->>`): Deep Magenta (#DB2777 Light) / Pastel Pink (#F472B6 Dark)
    public static let sqlOperatorNSColor = NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#F472B6") : NSColor(hex: "#DB2777")
    })
    public static let sqlOperator = Color(nsColor: sqlOperatorNSColor)
    
    // MARK: - Typography & Geometry Tokens
    
    /// Option B Architectural Micro-Box badge corner radius (4.0pt)
    public static let cornerRadiusBadge: CGFloat = 4.0
    /// Legacy alias pointing to Option B micro-box to automatically fix legacy pills
    public static let cornerRadiusPill: CGFloat = 4.0
    public static let cornerRadiusCard: CGFloat = 8.0
    public static let cornerRadiusButton: CGFloat = 6.0
    public static let cornerRadiusInput: CGFloat = 6.0
    public static let cornerRadiusWindow: CGFloat = 14.0
    public static let hairlineBorder: CGFloat = 1.0
    public static let standardBorder: CGFloat = 1.0
    public static let badgeBorderWidth: CGFloat = 0.0
}

// MARK: - NSColor & NSAppearance Extensions

extension NSAppearance {
    var isDark: Bool {
        if bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return true
        }
        return name.rawValue.lowercased().contains("dark")
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

/// Option B Borderless Micro-Box badge modifier
public struct PostgraceBadgeModifier: ViewModifier {
    let background: Color
    let foreground: Color

    public func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusBadge, style: .continuous))
    }
}

public struct PostgracePillModifier: ViewModifier {
    let background: Color
    let border: Color

    public func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusBadge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusBadge, style: .continuous)
                    .stroke(border == .clear ? Color.clear : border, lineWidth: border == .clear ? 0 : PostgraceTheme.hairlineBorder)
            )
    }
}

extension View {
    public func postgraceCard() -> some View {
        modifier(PostgraceCardModifier())
    }

    public func postgraceBadge(bg: Color, fg: Color) -> some View {
        modifier(PostgraceBadgeModifier(background: bg, foreground: fg))
    }

    public func postgracePill(background: Color, border: Color) -> some View {
        modifier(PostgracePillModifier(background: background, border: border))
    }
}
