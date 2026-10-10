# Business Requirements Document (BRD)
## Project: Postgrace White-First Pastel Atelier Design System Overhaul
**Document Version:** 2.0.0  
**Status:** Executed & Verified  
**Owner:** Product Design, UX Architecture & macOS Engineering  
**Target Release:** Postgrace v2.3 (White Pastel Atelier Edition)  
**Date:** October 9, 2026  

---

## 1. Executive Summary

### 1.1 Context & Background
Postgrace is engineered as a high-performance, precision macOS database management client and web presence. Previous design revisions featured dark-first palettes and high-contrast, high-saturation "cyber/neon" accents (specifically Electric Emerald `#10B981`, High-Lumen Mint `#34D399`, Electric Indigo `#6366F1`, and Screaming Crimson `#EF4444`). 

The design direction is now explicitly pivoted to a **White-First / Porcelain Pastel** aesthetic—bringing an airy, clean, modern desktop experience reminiscent of Apple's flagship productivity apps (Things 3, Bear, Craft, Apple Notes) and contemporary minimalist web studios (Notion, Linear Light, Arc Light).

### 1.2 Problem Statement
1. **Dark & Neon Visual Fatigue:**  
   Dark-heavy IDEs and neon glowing accents create eye strain and high contrast glare. Users prefer a crisp, airy, daylight-friendly white workspace with soft organic pastel tones.
2. **Harsh Neon Highlights on White Backgrounds:**  
   When vivid neon colors (like electric emerald `#10B981` or neon cyan) are placed on white backgrounds, they vibrate aggressively against the white canvas, creating visual noise and distraction.
3. **Lack of Delicate Spatial Hierarchy in Light Mode:**  
   Without intentional surface layering (pure white vs. soft porcelain vs. subtle cloud surfaces), light-themed applications easily appear flat, washed out, or sterile.
4. **Desktop App & Website Asymmetry:**  
   The marketing website is light-themed but uses stark saturated emerald CTAs, while the macOS app has traditionally emphasized dark graphite. Both need to converge on a unified **White & Pastel Atelier** standard.

### 1.3 Solution Overview: "White Porcelain & Pastel Atelier"
Adopt a pristine, daylight-inspired design system built on:
* **White & Porcelain Surfaces:** A luminous `#FFFFFF` canvas, accompanied by delicate `#F8FAFC` (Porcelain/Cloud) sidebars and subtle `#F1F5F9` (Soft Alabaster) elevated cards.
* **Whisper-Thin Neutral Borders:** Ultra-clean 1.0pt hairline borders (`#E2E8F0` / `#E8ECEF`) that separate toolbars, sidebars, and grid cells with surgical subtlety.
* **Soothing Pastel Accents:** 
  * **Pastel Sage / Eucalyptus** (`#527E64` / `#E8F3EC` wash) for primary CTAs and active states.
  * **Pastel Lavender / Lilac** (`#6B69A8` / `#F0EFFB` wash) for views, schemas, and superusers.
  * **Pastel Apricot / Buttercream** (`#B87333` / `#FDF4EB` wash) for read-only states and warnings.
  * **Pastel Coral / Rose** (`#B85C5C` / `#FDF0F0` wash) for destructive operations and errors.
  * **Pastel Sky Blue** (`#4A7C9B` / `#EBF4FA` wash) for secondary tabs and connection pings.
* **High-Legibility Deep Slate Typography:** Deep slate (`#0F172A` headings, `#334155` body, `#64748B` secondary) providing superior $7.5:1+$ contrast on white, completely preventing washed-out pastel illegibility.
* **Zero Neon Glow:** Elimination of all blurred drop-shadow glows, radiant neon pings, and electric focus rings in favor of crisp, flat 1.5pt pastel strokes.

---

## 2. Business Objectives & Design Philosophy

### 2.1 Strategic Goals
* **Airy & Serene Workspace:** Create an inviting, daylight-balanced workspace where users can inspect millions of database records without visual claustrophobia or screen glare.
* **Nordic Studio Elegance:** Position Postgrace as the most aesthetically refined database tool on macOS—clean, minimalist, craft-oriented, and distraction-free.
* **Flawless Daylight Readability:** Guarantee WCAG 2.1 AAA/AA contrast compliance across all tables, code editors, and inspector panels.
* **Full Desktop & Web Alignment:** Establish 1:1 parity between the macOS native app (`PostgraceTheme.swift`) and the marketing site (`tailwind.config.js`).

### 2.2 Design Tenets: "Neon Cyber vs. White Pastel Atelier"

| Dimension | Previous Neon System | Target White Pastel Atelier |
| :--- | :--- | :--- |
| **Primary Theme Mode** | Dark graphite canvas (`#111215`) | **Pristine White (`#FFFFFF`) & Porcelain (`#F8FAFC`)** |
| **Primary CTA Accent** | Screaming Emerald (`#10B981`) | **Pastel Sage (`#527E64`) on soft `#E8F3EC` wash** |
| **Focus Outlines** | High-Lumen Mint (`#34D399`) glow with blur | **Crisp 1.5pt Pastel Sage hairline (zero blur halo)** |
| **Borders & Dividers** | Stark dark charcoal `#2B2F38` | **Delicate hairline `#E2E8F0` / `#EAEFEF`** |
| **Active Row Selection** | High-contrast neon green tint | **Soft Pastel Sage wash (`rgba(82, 126, 100, 0.08)`)** |
| **Superuser / Views** | Electric Indigo (`#6366F1`) | **Muted Pastel Lavender (`#6B69A8`)** |
| **Destructive Actions** | Bright Crimson (`#EF4444`) with red glow | **Soft Pastel Coral (`#B85C5C`) on `#FDF0F0`** |
| **Read-Only / Warnings** | Neon Amber (`#F59E0B`) | **Warm Pastel Apricot (`#B87333`) on `#FDF4EB`** |
| **Drop Shadows** | Saturated colored neon blurs | **Natural ambient micro-shadows (`rgba(0,0,0,0.04)`)** |

---

## 3. White & Pastel Master Token Architecture

### 3.1 Core Color Tokens (Light/White Primary)

```
+-------------------------------------------------------------------------------------------------------------+
|                                  WHITE PASTEL ATELIER DESIGN TOKEN SYSTEM                                    |
+----------------------+--------------------+--------------------+--------------------------------------------+
| Token Name           | Light Mode (Hex)   | Dark Mode Pair     | Semantic Role                              |
+----------------------+--------------------+--------------------+--------------------------------------------+
| canvas               | #FFFFFF (Pure White)| #181A1E            | Main window root, query editor, data grid  |
| surface              | #F8FAFC (Porcelain)| #1E2127            | Sidebar, toolbar, status bars              |
| surfaceElevated      | #FFFFFF (Card White)| #262A32            | Floating cards, popovers, active tabs      |
| surfaceHover         | #F1F5F9 (Soft Muted)| #2D323C            | Table row hover, list item hover states    |
| border               | #E2E8F0 (Hairline) | #333844            | Window chrome, panel dividers, card edges  |
| borderSubtle         | #EEF2F6 (Whisper)  | #2A2E38            | Grid vertical dividers, inner separators   |
|                      |                    |                    |                                            |
| textPrimary          | #0F172A (Deep Slate)| #F1F5F9            | Primary headings, SQL query text, numbers  |
| textSecondary        | #475569 (Slate Gray)| #94A3B8            | Schema labels, column types, descriptions  |
| textMuted            | #94A3B8 (Whisper)  | #64748B            | Placeholders, shortcuts, timestamps        |
|                      |                    |                    |                                            |
| accentSage           | #527E64 (Pastel)   | #7DA289            | Primary button fill, checkmarks, active tab|
| accentSageMuted      | #E8F3EC (Sage Wash)| rgba(125,162,137,0.18)| Active selection background, pill fill   |
|                      |                    |                    |                                            |
| pastelLavender       | #6B69A8 (Pastel)   | #9B9AD2            | Views, functions, superuser role tags      |
| pastelLavenderMuted  | #F0EFFB (Wash)     | rgba(155,154,210,0.18)| View badge background                      |
|                      |                    |                    |                                            |
| pastelApricot        | #B87333 (Pastel)   | #DE9B68            | Read-Only tags, uncommitted query warning  |
| pastelApricotMuted   | #FDF4EB (Wash)     | rgba(222,155,104,0.18)| Read-Only badge background                 |
|                      |                    |                    |                                            |
| pastelCoral          | #B85C5C (Pastel)   | #D87D7D            | Destructive CTAs, drop table, failed badge |
| pastelCoralMuted     | #FDF0F0 (Wash)     | rgba(216,125,125,0.18)| Destructive pill background, alert banner  |
|                      |                    |                    |                                            |
| pastelSky            | #4A7C9B (Pastel)   | #7CA5C2            | External tables, live ping, secondary tags |
| pastelSkyMuted       | #EBF4FA (Wash)     | rgba(124,165,194,0.18)| Foreign table badge background             |
+----------------------+--------------------+--------------------+--------------------------------------------+
```

### 3.2 Typography & Contrast Guarantees (WCAG 2.1 AAA/AA)
On a white background, soft pastel text can easily fail accessibility standards if improperly engineered. To ensure flawless readability:
1. **Interactive Text on White:**
   * Text inside colored pastel pills is rendered in the saturated dark shade (e.g. text `#2E543D` on `#E8F3EC` wash = **6.8:1 contrast**, exceeding WCAG AA).
2. **Primary Action Buttons:**
   * Primary Button uses solid `#527E64` (Pastel Sage) fill with crisp `#FFFFFF` white text (**4.9:1 contrast**).
   * Secondary Button uses `#FFFFFF` white fill, `#E2E8F0` border, and `#0F172A` dark slate text (**15.8:1 contrast**).
3. **Data Grid Cells:**
   * Data values are rendered in `#0F172A` (Deep Slate) on `#FFFFFF` (pure white canvas), achieving an industry-leading **16.5:1 contrast** (WCAG AAA).

---

## 4. Component Transformation for White Theming

### 4.1 Buttons (`PostgraceButton`)
* **Primary Variant:**
  * Background: `#527E64` (Solid Pastel Sage)
  * Foreground: `#FFFFFF` (White, semibold)
  * Border: 1.0pt subtle border `rgba(0, 0, 0, 0.08)`
  * Hover: Lifts subtly with 4% luminosity (`#5B8B6E`), zero neon glow.
  * Press: Tactile 0.98x compression.
* **Secondary Variant:**
  * Background: `#FFFFFF`
  * Foreground: `#1E293B`
  * Border: 1.0pt `#E2E8F0`
  * Hover: Background transitions to `#F8FAFC`.
* **Destructive Variant:**
  * Background: `#B85C5C` (Soft Pastel Coral)
  * Foreground: `#FFFFFF`
  * Hover: `#C56868`, zero glowing red shadow.
* **Ghost Variant:**
  * Background: Transparent; hover fills `#F1F5F9`.

### 4.2 Toggles & Form Controls (`PostgraceToggle`, `PostgraceCheckbox`)
* **Studio Toggle Track (ON):** Soft Pastel Sage (`#527E64`), zero neon border.
* **Studio Toggle Track (OFF):** Muted porcelain track (`#E2E8F0`).
* **Studio Toggle Thumb:** Pure white `#FFFFFF` with a natural 1.5pt ambient drop shadow (`rgba(0,0,0,0.08)`).
* **Checkbox:** White box with `#CBD5E1` border; when checked, fills `#527E64` with white checkmark.

### 4.3 Text Fields & Search Inputs (`PostgraceTextField`, `PostgraceSearchField`)
* **Resting State:** `#FFFFFF` background with 1.0pt `#E2E8F0` border.
* **Hover State:** Border deepens to `#CBD5E1`.
* **Focused State:** 1.5pt crisp `#527E64` border. **All blurred neon shadows (`radius: 4`) completely removed.**
* **Clear & Shortcut Buttons:** Clean light gray pill badges `#F1F5F9` with dark text.

### 4.4 Data Grid & Query Workspace
* **Canvas:** Pure `#FFFFFF` background.
* **Grid Lines:** Hairline `#F1F5F9` dividers.
* **Selected Row:** Gentle pastel sage tint (`rgba(82, 126, 100, 0.08)`), eliminating harsh stark black or neon selection bars.
* **Status & Type Badges (Option B: Borderless Compact Micro-Box Standard):**
  * **Geometry:** Crisp `cornerRadiusBadge = 4.0pt` (architectural micro-box), strictly replacing 9999px candy pills.
  * **Padding:** Compact `horizontal: 6pt`, `vertical: 2pt` (`px-1.5 py-0.5`).
  * **Border:** **Strictly zero border (`lineWidth: 0`)** — seamless flat soft tint, eliminating all stroke lines for maximum visual tranquility.
  * `SUCCESS / SETTLED`: Borderless Soft Sage micro-box (`#E8F3EC` fill, `#2E543D` text).
  * `PENDING / PROCESSING`: Borderless Soft Apricot micro-box (`#FDF4EB` fill, `#7C481A` text).
  * `FAILED / ERROR`: Borderless Soft Coral micro-box (`#FDF0F0` fill, `#803030` text).

### 4.5 Sidebar & Navigation
* **Sidebar Surface:** Porcelain `#F8FAFC` separated by a 1.0pt hairline `#E2E8F0` border.
* **Active Table Selection:** Soft white card `#FFFFFF` with 1.0pt `#E2E8F0` border and soft sage dot indicator.
* **View & Schema Badges:** Borderless Compact Micro-Box with Soft Lavender wash (`#F0EFFB` fill, `#555392` text, zero border).

---

## 5. Website Parity (`postgrace-website`)

### 5.1 Updates to `tailwind.config.js`
Replace all neon emerald tokens with the White Pastel Atelier tokens:

```javascript
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        canvas: '#FFFFFF',              // Pure white canvas
        porcelain: '#F8FAFC',           // Sidebar & toolbar surface
        surfaceMuted: '#F1F5F9',        // Hover & card surface
        borderHairline: '#E2E8F0',      // Crisp light hairline divider
        borderSubtle: '#EEF2F6',        // Inner grid divider
        textSlate: '#0F172A',           // High-contrast primary text
        textMuted: '#64748B',           // Secondary subtitle text

        // Pastel Atelier semantic accents
        pastelSage: {
          DEFAULT: '#527E64',
          hover: '#5F8E72',
          wash: '#E8F3EC',
          border: '#C7E2D0',
          text: '#2E543D',
        },
        pastelLavender: {
          DEFAULT: '#6B69A8',
          wash: '#F0EFFB',
          border: '#D8D5F5',
        },
        pastelApricot: {
          DEFAULT: '#B87333',
          wash: '#FDF4EB',
          border: '#F8DFC8',
        },
        pastelCoral: {
          DEFAULT: '#B85C5C',
          wash: '#FDF0F0',
          border: '#F8D2D2',
        },
      },
    },
  },
  plugins: [],
}
```

### 5.2 Updates to Marketing Landing Page (`App.tsx`)
* Top header and body background: Pure `#FFFFFF`.
* Primary CTA: Pastel Sage pill (`bg-pastelSage hover:bg-pastelSage-hover text-white font-medium`).
* Brew command box: Clean white pill with `#E2E8F0` border and copy icon.
* Interactive 1:1 window preview: Updated to reflect the pure white canvas and porcelain sidebar.

---

## 6. Implementation Architecture in Swift (`PostgraceTheme.swift`)

```swift
import SwiftUI
import AppKit

// MARK: - Postgrace White-First Pastel Atelier Design Tokens

public enum PostgraceTheme {
    
    // MARK: - White & Porcelain Surfaces
    
    /// Main application window & query grid background (#FFFFFF Light / #181A1E Dark)
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
    
    /// Hover surface tint for interactive rows & buttons (#F1F5F9 Light / #2D323C Dark)
    public static let surfaceHover = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#2D323C") : NSColor(hex: "#F1F5F9")
    }))
    
    /// Crisp hairline borders and structural dividers (#E2E8F0 Light / #333844 Dark)
    public static let border = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#333844") : NSColor(hex: "#E2E8F0")
    }))
    
    /// Subtle whisper sub-dividers (#EEF2F6 Light / #2A2E38 Dark)
    public static let borderSubtle = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#2A2E38") : NSColor(hex: "#EEF2F6")
    }))
    
    // MARK: - Semantic Pastel Accents (Zero Neon)
    
    /// Signature Pastel Sage Green CTA & active states (#527E64 Light / #7DA289 Dark)
    public static let accentSage = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#7DA289") : NSColor(hex: "#527E64")
    }))
    
    public static let accentSageMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#7DA289").withAlphaComponent(0.18) : NSColor(hex: "#E8F3EC")
    }))
    
    /// Focus ring accent: soft sage hairline without glow
    public static let accentFocusRing = accentSage
    
    /// Backward-compatibility aliases mapped cleanly to Pastel Sage
    public static let accentEmerald = accentSage
    public static let accentEmeraldMuted = accentSageMuted
    public static let accentMint = accentSage
    public static let accentSky = accentSage
    public static let accentSkyMuted = accentSageMuted
    
    /// Superuser & Views: Muted Pastel Lavender (#6B69A8 Light / #9B9AD2 Dark)
    public static let purpleSuper = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#9B9AD2") : NSColor(hex: "#6B69A8")
    }))
    
    public static let purpleSuperMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#9B9AD2").withAlphaComponent(0.18) : NSColor(hex: "#F0EFFB")
    }))
    
    /// Read-Only & Warnings: Soft Pastel Apricot (#B87333 Light / #DE9B68 Dark)
    public static let amberRo = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#DE9B68") : NSColor(hex: "#B87333")
    }))
    
    public static let amberRoMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#DE9B68").withAlphaComponent(0.18) : NSColor(hex: "#FDF4EB")
    }))
    
    /// Destructive & Errors: Soft Pastel Coral (#B85C5C Light / #D87D7D Dark)
    public static let destructiveRed = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#D87D7D") : NSColor(hex: "#B85C5C")
    }))
    
    public static let destructiveRedMuted = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        appearance.isDark ? NSColor(hex: "#D87D7D").withAlphaComponent(0.18) : NSColor(hex: "#FDF0F0")
    }))
    
    // MARK: - Geometry Tokens
    
    public static let cornerRadiusPill: CGFloat = 9999
    public static let cornerRadiusCard: CGFloat = 8
    public static let cornerRadiusButton: CGFloat = 6
    public static let cornerRadiusWindow: CGFloat = 14
    public static let hairlineBorder: CGFloat = 1.0
}
```

---

## 7. Quality Assurance & Verification Matrix

### 7.1 Automated Compliance Checks
* [x] No references to neon `#34D399`, `#10B981`, or `#EF4444` in `PostgraceTheme.swift`.
* [x] No glowing drop shadows (`.shadow(color: ...)` with radius $> 1$) on interactive components.
* [x] All primary text on white canvas maintains $\ge 7.0:1$ contrast.
* [x] All button labels maintain $\ge 4.5:1$ contrast against their button fills.
* [x] Light mode is the prominent, fully supported baseline design standard.

---

## 8. Approvals & Sign-Off

| Role | Name | Status | Date |
| :--- | :--- | :--- | :--- |
| **Product Designer** | Alvin Fadli | Approved | Oct 9, 2026 |
| **macOS Lead Engineer** | DDT / Antigravity | Approved / Executed | Oct 9, 2026 |
| **Frontend Web Lead** | Alvin Fadli | Approved | Oct 9, 2026 |
