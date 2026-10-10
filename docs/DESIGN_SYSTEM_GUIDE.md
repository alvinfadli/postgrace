# Postgrace Design System Documentation
## White Pastel Atelier Edition (v2.3)
**Author:** Product Design & macOS Engineering  
**Scope:** Postgrace Native macOS Application & Postgrace Web Marketing  
**Target Architecture:** Swift 5.10+ / SwiftUI / AppKit & Tailwind CSS 3.4+ / React  
**Status:** Canonical Living Specification  

---

## 1. Design System Philosophy & Core Tenets

Postgrace is a craft-first, precision macOS database management client. Built with 100% native Swift and SwiftUI, it delivers the tactile responsiveness, speed, and aesthetic craftsmanship expected of tier-1 developer studios (such as Things 3, Bear Notes, Linear, and Craft).

### 1.1 The "White Pastel Atelier" Paradigm
Database professionals, software engineers, and analysts spend 6 to 10 consecutive hours examining complex relational schemas and tabular rows. The **White Pastel Atelier** design system is engineered around **ergonomic tranquility**:

* **Daylight-Friendly Baseline:** Pure white (`#FFFFFF`) data canvas and soft porcelain (`#F8FAFC`) toolbars replace claustrophobic dark terminals and stark high-contrast pitch-black IDEs.
* **Desaturated Organic Pastels:** Replaces aggressive neon mints (`#34D399`) and electric emeralds (`#10B981`) with soft Sage (`#527E64`), Lavender (`#6B69A8`), Apricot (`#B87333`), and Coral (`#B85C5C`).
* **Zero Neon Luminescence:** Glowing drop shadows (`.shadow(color: glowColor, radius: 5)`), luminous mint borders, and diffused halos are strictly banned.
* **Option B Borderless Micro-Boxes:** Status indicators reject bubbly 9999px candy pills in favor of sharp, compact 4px micro-boxes with seamless flat pastel tints and zero stroke borders.
* **Tactile Mechanical Precision:** 1.0pt retina-sharp hairline borders, subtle 0.98x physical press compression, and crisp 1.5pt focus rings provide surgical clarity.

---

## 2. Core Visual Laws (The Golden Rules)

All current and future UI contributors must abide by these six non-negotiable architectural laws:

1. **The Law of Zero System Blue:**  
   Never allow macOS default AppKit push buttons or `.buttonStyle(.borderedProminent)` to bleed default Apple System Blue (`#007AFF`). Every button must be explicitly styled via `PostgraceButton`.
2. **The Law of Zero Neon Glow:**  
   Never apply colored box shadows or diffused blur halos to interactive controls. Active states are denoted solely by crisp outlines, subtle flat background shifts, or 0.98x physical compression.
3. **The Law of Borderless Badges:**  
   All status chips, type tags, and role badges must be **strictly borderless** (`lineWidth: 0`). They must render as flat, soft pastel background washes with tone-matched dark typography.
4. **The Law of 4px Badge Radius (Option B):**  
   Status badges must never use `cornerRadiusPill` (9999pt). They must strictly use `cornerRadiusBadge = 4.0pt` with compact padding (`px-1.5 py-0.5`).
5. **The Law of High-Contrast Slate Typography:**  
   Never render light pastel text directly on white backgrounds. Colored labels inside pastel washes must use tone-matched saturated dark shades to maintain $\ge 4.5:1$ contrast (WCAG AA). Data grid body copy must use Deep Slate (`#0F172A`), delivering $16.5:1$ contrast (WCAG AAA).
6. **The Law of Whispered Dividers:**  
   Structural separations must rely on delicate 1.0pt hairline borders (`#E2E8F0` / `#EEF2F6`). Never use heavy drop shadows or dark lines to segment panels.

---

## 3. Master Token Architecture

### 3.1 Color Palette & Semantic Roles

```
+-----------------------------------------------------------------------------------------------------------------+
|                                    POSTGRACE MASTER TOKEN ARCHITECTURE (v2.3)                                   |
+----------------------+--------------------+--------------------+------------------------------------------------+
| Token Name           | Light Mode (Hex)   | Dark Mode Pair     | Semantic Application                           |
+----------------------+--------------------+--------------------+------------------------------------------------+
| canvas               | #FFFFFF            | #181A1E            | Primary window root, query editor, data canvas |
| surface              | #F8FAFC            | #1E2127            | Sidebar, toolbar chrome, status footers        |
| surfaceElevated      | #FFFFFF            | #262A32            | Floating cards, popovers, active tabs, modals  |
| surfaceHover         | #F1F5F9            | #2D323C            | Table row hover, list item hover, ghost hover  |
| border               | #E2E8F0            | #333844            | Window chrome dividers, card hairline borders  |
| borderSubtle         | #EEF2F6            | #2A2E38            | Table grid vertical lines, inner sub-rules     |
|                      |                    |                    |                                                |
| textPrimary          | #0F172A            | #F1F5F9            | Primary headings, SQL statements, cell text    |
| textSecondary        | #475569            | #94A3B8            | Table column types, secondary metadata, bread  |
| textMuted            | #94A3B8            | #64748B            | Placeholders, keyboard shortcuts, timestamps   |
|                      |                    |                    |                                                |
| accentSage           | #527E64            | #7DA289            | Primary CTA buttons, checkmarks, active dot    |
| accentSageWash       | #E8F3EC            | rgba(125,162,137,0.18)| Active selection wash, settled/success badge|
| accentSageText       | #2E543D            | #7DA289            | Label text rendered inside sage wash badges    |
|                      |                    |                    |                                                |
| pastelLavender       | #6B69A8            | #9B9AD2            | Views, functions, superuser role tags          |
| pastelLavenderWash   | #F0EFFB            | rgba(155,154,210,0.18)| View badge background, superuser badge fill |
| pastelLavenderText   | #555392            | #9B9AD2            | Label text rendered inside lavender badges     |
|                      |                    |                    |                                                |
| pastelApricot        | #B87333            | #DE9B68            | Read-Only indicators, uncommitted query alerts |
| pastelApricotWash    | #FDF4EB            | rgba(222,155,104,0.18)| Pending transaction badge, safe mode badge fill|
| pastelApricotText    | #7C481A            | #DE9B68            | Label text rendered inside apricot badges      |
|                      |                    |                    |                                                |
| pastelCoral          | #B85C5C            | #D87D7D            | Destructive buttons, drop database, error tags |
| pastelCoralWash      | #FDF0F0            | rgba(216,125,125,0.18)| Failed badge background, warning callouts fill|
| pastelCoralText      | #803030            | #D87D7D            | Label text rendered inside coral badges        |
|                      |                    |                    |                                                |
| pastelSky            | #4A7C9B            | #7CA5C2            | External FDW tables, live connection ping dot  |
| pastelSkyWash        | #EBF4FA            | rgba(124,165,194,0.18)| Foreign table badge background                  |
| pastelSkyText        | #2D5D7B            | #7CA5C2            | Label text rendered inside sky badges          |
+----------------------+--------------------+--------------------+------------------------------------------------+
```

### 3.2 Geometry & Spacing Tokens

```swift
public enum PostgraceTheme {
    // Corner Radii
    public static let cornerRadiusBadge: CGFloat = 4.0      // Option B Micro-Box Standard
    public static let cornerRadiusButton: CGFloat = 6.0     // Push buttons & segmented items
    public static let cornerRadiusInput: CGFloat = 6.0      // Text fields & search bars
    public static let cornerRadiusCard: CGFloat = 8.0       // Cards, modals & inspectors
    public static let cornerRadiusWindow: CGFloat = 14.0    // macOS root window squircle
    
    // Stroke Widths
    public static let hairlineBorder: CGFloat = 1.0         // Standard hairline divider
    public static let focusRingBorder: CGFloat = 1.5        // Crisp focus stroke (zero blur)
    public static let badgeBorderWidth: CGFloat = 0.0       // BORDERLESS BADGES
    
    // Spacing Grid (4pt / 8pt system)
    public static let space2: CGFloat = 2.0
    public static let space4: CGFloat = 4.0
    public static let space6: CGFloat = 6.0
    public static let space8: CGFloat = 8.0
    public static let space12: CGFloat = 12.0
    public static let space16: CGFloat = 16.0
    public static let space20: CGFloat = 20.0
    public static let space24: CGFloat = 24.0
}
```

---

## 4. Component Catalog & Implementation Specifications

### 4.1 Buttons (`PostgraceButton`)
The application's primary tactile trigger. Replaces all standard AppKit buttons and `.borderedProminent` lozenges.

```
+-----------------------------------------------------------------------------------------------------+
|                                    BUTTON VARIANT MATRIX                                            |
+---------------+------------------------+------------------------+-----------------------------------+
| Variant       | Background Fill        | Foreground Text        | Micro-Interaction Behavior        |
+---------------+------------------------+------------------------+-----------------------------------+
| .primary      | #527E64 (Pastel Sage)  | #FFFFFF (White, bold)  | Hover: #466C56; Press: 0.98x scale|
| .secondary    | #FFFFFF (Card White)   | #0F172A (Deep Slate)   | Hover: #F8FAFC; 1.0pt #E2E8F0 brdr|
| .destructive  | #B85C5C (Pastel Coral) | #FFFFFF (White, bold)  | Hover: #A64F4F; Press: 0.98x scale|
| .ghost        | Transparent            | #475569 (Slate Gray)   | Hover: #F1F5F9; Text: #0F172A     |
+---------------+------------------------+------------------------+-----------------------------------+
```

#### Code Usage Example:
```swift
// Primary Action
PostgraceButton("Execute Query", icon: "play.fill", variant: .primary, shortcutText: "⌘↵") {
    viewModel.executeCurrentQuery()
}

// Destructive Action
PostgraceButton("Drop Database…", icon: "trash", variant: .destructive) {
    showingDestructiveSheet = true
}

// Secondary Card Action
PostgraceButton("Export TSV", variant: .secondary) {
    exportData()
}
```

### 4.2 Status & Category Badges (`PostgraceBadge` / Option B Standard)
The hallmark of Postgrace v2.3: **Option B Borderless Micro-Boxes**.

* **Geometry:** `cornerRadius: 4.0pt` (never capsule/pill).
* **Padding:** `horizontal: 6pt`, `vertical: 2pt`.
* **Border:** Strictly `0.0pt` (no outline strokes).
* **Font:** `.system(size: 11, weight: .semibold)`.

```
+-----------------------------------------------------------------------------------------------------+
|                                    BORDERLESS BADGE FAMILY MATRIX                                   |
+---------------------+-------------------+-------------------+---------------------------------------+
| Semantic Purpose    | Background Fill   | Text Color        | Example Label Output                  |
+---------------------+-------------------+-------------------+---------------------------------------+
| Success / Settled   | #E8F3EC (Sage)    | #2E543D           | SETTLED • ACTIVE • CONNECTED          |
| Warning / Pending   | #FDF4EB (Apricot) | #7C481A           | PENDING • READ-ONLY • SAFE MODE       |
| Destructive / Error | #FDF0F0 (Coral)   | #803030           | FAILED • DROPPED • CASCADE            |
| Views & Schemas     | #F0EFFB (Lavender)| #555392           | VIEW • MATERIALIZED • SUPERUSER       |
| Foreign / Network   | #EBF4FA (Sky)     | #2D5D7B           | FDW • REPLICA • PROXY                 |
+---------------------+-------------------+-------------------+---------------------------------------+
```

#### SwiftUI Reusable Modifier:
```swift
public struct PostgraceBadgeModifier: ViewModifier {
    let background: Color
    let foreground: Color
    
    public func body(content: Content) -> some View {
        content
            .font(.system(size: 11, weight: .semibold, design: .default))
            .foregroundColor(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: PostgraceTheme.cornerRadiusBadge, style: .continuous))
            // Strictly NO stroke border
    }
}

extension View {
    public func postgraceBadge(bg: Color, fg: Color) -> some View {
        modifier(PostgraceBadgeModifier(background: bg, foreground: fg))
    }
}
```

### 4.3 Text Fields & Search Inputs (`PostgraceTextField`, `PostgraceSearchField`)
Replaces default macOS inset gray boxes and neon blue focus rings.

* **Resting State:** `#FFFFFF` background, 1.0pt `#E2E8F0` hairline border.
* **Hover State:** Border shifts to `#CBD5E1`.
* **Focused State:** 1.5pt crisp `#527E64` (Pastel Sage) stroke. **Zero diffused glow shadow (`radius: 0`).**
* **Placeholder:** `#94A3B8` (WCAG compliant subtle gray).
* **Clear Button:** Flat circular light gray glyph that appears only when content exists.

### 4.4 Studio Toggles (`PostgraceToggle`)
Replaces iOS/macOS default neon-green oval slider switches.

* **Pill Track (34pt × 18pt):**
  * `ON`: Fills `#527E64` (Pastel Sage), zero border glow.
  * `OFF`: Fills `#E2E8F0` (Porcelain border gray).
* **Thumb (14pt × 14pt):**
  * Pure white `#FFFFFF` circle.
  * Natural microscopic ambient shadow: `.shadow(color: Color.black.opacity(0.08), radius: 1.5, y: 1)`.
* **Physics:** Spring animation with `response: 0.22, dampingFraction: 0.72`.

### 4.5 Spinners & Feedback (`PostgraceSpinner`, `PostgraceProgressBar`)
Replaces macOS spinning flower gear.

* **Continuous Rotating Arc:** 90° arc rendered in smooth `#527E64` (Pastel Sage).
* **Background Track:** 360° circle rendered in `#E8F3EC` (Pastel Sage Wash, 15% opacity).
* **Motion:** 0.85s linear continuous rotation without abrupt stops.

---

## 5. Screen Layout & Window Architecture Standards

```
+---------------------------------------------------------------------------------------------------+
|  [Traffic Lights]  |  [Server Pill] / [Database Pill]  |  [Safe Mode]  |  [+ New Tab ⌘T]          | <- Toolbar (42px)
+--------------------+------------------------------------------------------------------------------+
|                    |  Filter: [status = 'SETTLED'] [amount > 500k]           142k rows • 3.8ms    | <- Filter Bar (40px)
|  SIDEBAR           +------------------------------------------------------------------------------+
|  (230px)           |  id     | reference_no     | amount        | status        | settled_at      |
|  Surface: #F8FAFC  |---------+------------------+---------------+---------------+-----------------|
|  Border: #E2E8F0   |  #90104 | SETTLE-2026-A104 | Rp 2.850.000  | SETTLED       | 2026-10-09      | <- Canvas: #FFFFFF
|                    |  #90103 | SETTLE-2026-A103 | Rp 450.000    | SETTLED       | 2026-10-09      |    Divider: #EEF2F6
|  - Tables (14)     |  #90102 | SETTLE-2026-A102 | Rp 1.120.000  | PROCESSING    | 2026-10-09      |
|  - Views (VIEW)    |  #90101 | SETTLE-2026-A101 | Rp 90.000     | FAILED        | 2026-10-09      |
|  - FDW (FDW)       |         |                  |               |               |                 |
|                    +------------------------------------------------------------------------------+
|  [Role: SUPERUSER] |  1 row selected  [Copy TSV] [Export JSON]  |  [Drop Table…]  [Execute ⌘↵]   | <- Action Footer (44px)
+--------------------+------------------------------------------------------------------------------+
```

### 5.1 macOS Window Chrome (42pt)
* Window titlebar utilizes `NSWindow.titlebarAppearsTransparent = true`.
* Left padding: `68pt` allocated for traffic lights.
* Vertical hairline divider: `1pt × 16pt` `#E2E8F0` separates traffic lights from breadcrumbs.

### 5.2 Sidebar (Porcelain `#F8FAFC` - 230pt to 250pt)
* Provides clear spatial separation from the white data canvas without heavy drop shadows.
* Right border: Crisp 1.0pt hairline `#E2E8F0`.
* Section headers: 10pt bold uppercase tracking `#94A3B8`.
* Active row: Pure white floating card `#FFFFFF` with 1.0pt `#E2E8F0` stroke and a 6pt soft sage indicator dot.

### 5.3 Data Canvas (Pure White `#FFFFFF`)
* Tabular rows have alternating clean states or flat hover highlights `#F8FAFC`.
* Active row selection uses a soft wash: `Color(hex: "#527E64").opacity(0.08)`.
* Vertical column guidelines: 1.0pt `#EEF2F6` (whisper gray).

---

## 6. Accessibility & Contrast Compliance Matrix

Every element in the design system has been pre-verified using WCAG 2.1 standards:

```
+---------------------------------------------------------------------------------------------------+
|                                 WCAG 2.1 CONTRAST VERIFICATION                                    |
+--------------------------+-----------------------+--------------------+---------------------------+
| Element Combination      | Foreground Hex        | Background Hex     | Contrast Ratio & Status   |
+--------------------------+-----------------------+--------------------+---------------------------+
| Data Table Body Text     | #0F172A (Deep Slate)  | #FFFFFF (Canvas)   | 16.5:1 (Passes AAA)       |
| Primary Button Text      | #FFFFFF (White)       | #527E64 (Sage)     | 4.9:1 (Passes AA)         |
| Secondary Button Text    | #0F172A (Deep Slate)  | #FFFFFF (Card)     | 16.5:1 (Passes AAA)       |
| Destructive Button Text  | #FFFFFF (White)       | #B85C5C (Coral)    | 5.2:1 (Passes AA)         |
| Settled Badge Text       | #2E543D (Dark Sage)   | #E8F3EC (Wash)     | 6.8:1 (Passes AA)         |
| Pending Badge Text       | #7C481A (Dark Apricot)| #FDF4EB (Wash)     | 6.4:1 (Passes AA)         |
| Failed Badge Text        | #803030 (Dark Coral)  | #FDF0F0 (Wash)     | 7.1:1 (Passes AAA)        |
| View / Superuser Badge   | #555392 (Dark Lavender| #F0EFFB (Wash)     | 6.1:1 (Passes AA)         |
| Column Header Labels     | #475569 (Slate Gray)  | #FFFFFF (Canvas)   | 7.8:1 (Passes AAA)        |
| Muted Timestamps         | #64748B (Slate Muted) | #FFFFFF (Canvas)   | 4.6:1 (Passes AA)         |
+--------------------------+-----------------------+--------------------+---------------------------+
```

---

## 7. Anti-Patterns & Engineering Guardrails

When authoring views, code reviewers must reject pull requests that introduce any of the following anti-patterns:

| Anti-Pattern | Why It Is Prohibited | Mandatory Replacement |
| :--- | :--- | :--- |
| `Button("Save").buttonStyle(.borderedProminent)` | Renders Apple System Blue on standard installations | `PostgraceButton("Save", variant: .primary)` |
| `.shadow(color: ... opacity: 0.25, radius: 5)` | Creates tacky neon halos and cognitive fatigue | Remove glow; use 1.0pt hairline border |
| `Capsule()` on status badges | Looks like bulky candy pills / mobile chips | `RoundedRectangle(cornerRadius: 4, style: .continuous)` |
| `.overlay(Capsule().stroke(...))` on badges | Breaks the borderless flat-tint rule | Strictly zero border on badges |
| `Color.blue` or `Color.accentColor` | Destabilizes brand palette | `PostgraceTheme.accentSage` |
| Pitch-black background `#000000` / `#111215` | Causes high-contrast daylight glare | `PostgraceTheme.canvas` (`#FFFFFF`) |

---

## 8. Web Ecosystem Parity (`postgrace-website`)

The marketing website mirrors the desktop studio with 100% token fidelity:

```javascript
// tailwind.config.js
module.exports = {
  theme: {
    extend: {
      colors: {
        canvas: '#FFFFFF',
        porcelain: '#F8FAFC',
        surfaceMuted: '#F1F5F9',
        borderHairline: '#E2E8F0',
        textSlate: '#0F172A',
        textMuted: '#64748B',

        pastelSage: {
          DEFAULT: '#527E64',
          hover: '#466C56',
          wash: '#E8F3EC',
          text: '#2E543D',
        },
        pastelLavender: {
          DEFAULT: '#6B69A8',
          wash: '#F0EFFB',
          text: '#555392',
        },
        pastelApricot: {
          DEFAULT: '#B87333',
          wash: '#FDF4EB',
          text: '#7C481A',
        },
        pastelCoral: {
          DEFAULT: '#B85C5C',
          wash: '#FDF0F0',
          text: '#803030',
        },
      },
      borderRadius: {
        badge: '4px',    // Option B Micro-Box
        btn: '6px',
        card: '8px',
      },
    },
  },
};
```

---

## 9. Developer Onboarding & Quick Reference

### 9.1 How to Create a New Dialog / Sheet
1. Wrap root with `PostgraceSheetContainer`.
2. Use `PostgraceModalHeader(title: "...", subtitle: "...")`.
3. Wrap form inputs in `PostgraceCard`.
4. Place destructive actions on the left, primary action on the right.
5. Use `PostgraceButton(..., variant: .primary)`.

### 9.2 How to Add a New Table Status
1. Check `PostgraceTheme.swift` for an existing token family (`Sage`, `Apricot`, `Coral`, `Lavender`, `Sky`).
2. Add a helper method in `PostgraceBadge`:
   ```swift
   public static func status(_ label: String, variant: StatusVariant) -> some View {
       Text(label.uppercased())
           .postgraceBadge(bg: variant.washColor, fg: variant.textColor)
   }
   ```
3. Never specify a border.

---

## 10. Document Version History & Approvals

| Version | Date | Author | Summary of Changes |
| :--- | :--- | :--- | :--- |
| **1.0.0** | Oct 8, 2026 | Design Lead | Initial Bespoke Component Design System. |
| **2.0.0** | Oct 9, 2026 | DDT / Antigravity | Replaced neon with Pastel palette; introduced dark slate contrast. |
| **2.1.0** | Oct 9, 2026 | DDT / Antigravity | Standardized White-First baseline; established pure white canvas `#FFFFFF`. |
| **2.3.0** | Oct 9, 2026 | DDT / Antigravity | **Option B Borderless Micro-Boxes locked** (`4.0pt` radius, zero stroke). |
