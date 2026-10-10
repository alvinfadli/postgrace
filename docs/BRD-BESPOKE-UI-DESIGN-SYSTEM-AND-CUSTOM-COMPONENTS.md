# Business Requirements Document (BRD)
## Project: Postgrace Bespoke UI Design System & Zero-Default-Component Overhaul
**Document Version:** 1.0.0  
**Status:** In Review / Ready for Engineering Execution  
**Owner:** Product Design & Mac Engineering  
**Target Release:** Postgrace v2.2 (Bespoke Studio Design System)  
**Date:** October 8, 2026  

---

## 1. Executive Summary

### 1.1 Context & Background
Postgrace is engineered as a high-performance, precision macOS database management client. Built with 100% Swift and SwiftUI, it aims to deliver the raw speed, tactile responsiveness, and aesthetic craftsmanship expected of tier-1 developer studios (similar to Linear, Raycast, and Zed).

While the application features an established color palette defined in `PostgraceTheme.swift` (centered around dark graphite canvas tokens and a signature Emerald Green accent `#10B981`), significant portions of the user interface still rely on default macOS AppKit/SwiftUI controls. 

### 1.2 Problem Statement
1. **Default macOS "Aqua Blue" Button Bleed:**
   Numerous dialogs, action bars, and modal sheets throughout the app utilize `.buttonStyle(.borderedProminent)` without explicit tint overrides, or rely on macOS system accent heuristics. On standard macOS installations, this renders default Apple System Blue buttons (`#007AFF`), violating brand consistency and creating an amateur, uncurated visual appearance.
2. **Generic macOS Operating System Chrome:**
   Views currently instantiate default macOS system components—such as native AppKit push buttons, standard macOS segmented pickers, default checkboxes, native sliding toggles, and standard rounded text fields with bright blue focus rings. These components look disconnected from Postgrace's modern flat graphite aesthetic.
3. **Inconsistent Component Metrics & Micro-Interactions:**
   Hover states, pressed depths, focus halos, and disabled appearances vary across views. In some sheets, buttons use custom capsules; in others, they use standard macOS 20px push-button lozenges.
4. **Lack of Enforced Custom Component Primitives:**
   Without a dedicated, reusable suite of custom controls (`PostgraceButton`, `PostgraceTextField`, `PostgraceToggle`, `PostgracePicker`, `PostgraceSpinner`), feature engineers have fallen back on standard SwiftUI primitives (`Button`, `TextField`, `Toggle`, `Picker`), continually reintroducing default macOS styling.

### 1.3 Solution Overview
Execute an end-to-end UI modernization that eliminates **all default blue buttons** and **all default macOS controls** in favor of a **100% bespoke, proprietary Postgrace component library**:
* **Zero System Blue Buttons:** Every button action across the application must strictly adhere to the brand color scheme (Emerald Green primary, Muted Graphite secondary, Crimson destructive, Ghost/Text subtle).
* **Zero Default macOS Components:** Replace all standard SwiftUI/AppKit controls with dedicated custom Postgrace components featuring custom geometry, hairline borders, smooth state transitions, and bespoke focus outlines.
* **Unified Global Theme Enforcement:** Apply root window tint overrides (`.tint(PostgraceTheme.accentEmerald)`) as an environmental baseline, backed by compile-time lint rules and reusable UI primitives.
* **Pixel-Perfect Micro-Interactions:** Custom hover glows, tactile scale compressions (0.98x on press), and signature Mint (`#34D399`) focus borders with zero system blue halos.

---

## 2. Business Objectives & Design Philosophy

### 2.1 Strategic Business Goals
* **Brand Identity & Distinctiveness:** Transform Postgrace from a "macOS utility that wraps PostgresNIO" into an iconic, craft-first developer studio with an instantly recognizable visual signature.
* **Visual Harmony & Immersion:** Provide a seamless, dark-first flat interface where database professionals can spend 8+ hours a day without jarring, bright blue operating system controls.
* **Design System Scalability:** Provide modular, ergonomic SwiftUI primitives so all future capabilities (e.g., visual query builders, migration diffing, monitoring dashboards) automatically look bespoke and on-brand.
* **Accessibility & Contrast:** Maintain strict WCAG AA contrast compliance (minimum 4.5:1 for body copy and interactive labels, 3.0:1 for structural borders and large text) across both Dark and Light modes.

### 2.2 Design Tenets: "Crafted Studio vs. Default Utility"
| Dimension | Default macOS Utility (Current State) | Postgrace Bespoke Studio (Target State) |
| :--- | :--- | :--- |
| **Primary Button** | macOS Blue rounded lozenge (`.borderedProminent`) | High-contrast Emerald Green flat pill/rect with 1px hairline border |
| **Secondary Button** | Semi-translucent grey Cocoa push button | Graphite surface elevated card with hover luminosity tint |
| **Focus Indicator** | Default macOS bright neon-blue diffused halo | Crisp 1px/1.5px High-Lumen Mint (`#34D399`) outline |
| **Text Fields** | Native inset grey rounded rectangle | Flat `#16181D` surface with subtle `#2B2F38` stroke and custom placeholder |
| **Toggles / Switches** | Default iOS/macOS green/blue oval sliding switch | Custom miniature studio pill switch with smooth spring transition |
| **Pickers / Dropdowns**| Default macOS Cocoa dropdown menu with blue arrows | Custom flat menu trigger with bespoke emerald check indicators |
| **Segmented Controls**| Native grey Cocoa tab segmented bar | Custom flat sliding indicator on elevated graphite track |
| **Loading Spinners** | Native macOS grey/blue spinning flower | Custom continuous rotating emerald arc with easing |

---

## 3. Brand Color Palette & Design Tokens

### 3.1 Color Palette Specifications
All controls must be constructed solely from the tokens defined in `PostgraceTheme.swift`. Direct use of `Color.blue`, `Color.accentColor`, or unstyled system colors is strictly prohibited.

```
+---------------------------------------------------------------------------------------------------------+
|                                    POSTGRACE DESIGN TOKEN ARCHITECTURE                                  |
+----------------------+--------------------+--------------------+----------------------------------------+
| Token Name           | Dark Mode Hex      | Light Mode Hex     | Semantic Intent                        |
+----------------------+--------------------+--------------------+----------------------------------------+
| canvas               | #111215            | #FFFFFF            | Main application canvas, query grids   |
| surface              | #16181D            | #F8FAFC            | Sidebars, toolbars, modal backgrounds  |
| surfaceElevated      | #1E2128            | #F1F5F9            | Cards, popovers, dropdown containers   |
| surfaceHover         | #252830            | #E2E8F0            | Button hover, list row hover states   |
| border               | #2B2F38            | #E2E8F0            | Structural borders, input outlines    |
| borderSubtle         | #22252C            | #F1F5F9            | Subtle inner dividers, grid lines     |
| accentEmerald        | #10B981            | #059669            | Primary brand accent, primary CTA fill |
| accentEmeraldMuted   | rgba(16,185,129,0.12)| rgba(5,150,105,0.10)| Badge fills, active pill backgrounds  |
| accentMint           | #34D399            | #10B981            | Focus rings, active live pings        |
| purpleSuper          | #6366F1            | #4F46E5            | Superuser role badge, advanced stats   |
| amberRo              | #F59E0B            | #D97706            | Read-Only badges, warning callouts     |
| destructiveRed       | #EF4444            | #DC2626            | Destructive buttons, error banners     |
| destructiveRedMuted  | rgba(239,68,68,0.12)| rgba(220,38,38,0.10)| Destructive badge / warning pill fill  |
+----------------------+--------------------+--------------------+----------------------------------------+
```

### 3.2 Geometry & Layout Tokens
* **Pill Radius (`cornerRadiusPill`):** `9999pt` (used for status badges, tag chips, and micro-toggles)
* **Card Radius (`cornerRadiusCard`):** `10pt` (used for modal panels, inspector cards, and hub tiles)
* **Button Radius (`cornerRadiusButton`):** `6pt` (used for standard inputs, action buttons, and segmented cells)
* **Input Radius (`cornerRadiusInput`):** `6pt`
* **Hairline Border (`hairlineBorder`):** `1.0pt` (retina-sharp flat borders)
* **Focus Ring Width:** `1.5pt` with `accentMint` stroke and `2.0pt` outer offset

---

## 4. Current State Elimination Audit

The following inventory identifies all components across the Postgrace codebase that currently violate brand guidelines by rendering default macOS controls or system blue buttons:

| File Path | Current Violating Code | Identified Issue | Target Replacement |
| :--- | :--- | :--- | :--- |
| `Views/Database/DatabaseListView.swift:100` | `.buttonStyle(.borderedProminent)` | **Default blue button** (+ New Database) | `PostgraceButton("New Database", variant: .primary)` |
| `Views/Database/CreateDatabaseSheet.swift:241` | `.buttonStyle(.borderedProminent)` | **Default blue button** (Create Database) | `PostgraceButton("Create Database", variant: .primary)` |
| `Views/Database/CreateDatabaseSheet.swift:158` | `Picker("", selection: ...)` | Default macOS dropdown menu | `PostgracePicker(selection: ...)` |
| `Views/Database/CreateDatabaseSheet.swift:184` | `Toggle(..., isOn: ...)` | Default macOS toggle switch | `PostgraceToggle(label, isOn: ...)` |
| `Views/Database/CreateDatabaseSheet.swift:132` | `TextField("e.g. analytics...", text: ...)` | Default macOS input with blue focus ring | `PostgraceTextField(placeholder, text: ...)` |
| `Views/Sidebar/ConnectionFormView.swift:94` | `Picker("Engine", ...).pickerStyle(.segmented)` | Default macOS segmented bar | `PostgraceSegmentedControl(selection: ...)` |
| `Views/Sidebar/ConnectionFormView.swift:175` | `Toggle("Safe Mode...", isOn: ...)` | Default macOS toggle switch | `PostgraceToggle("Safe Mode...", isOn: ...)` |
| `Views/Sidebar/ConnectionFormView.swift:282` | `.buttonStyle(.borderedProminent)` | Uses `.borderedProminent` lozenge | `PostgraceButton("Save", variant: .primary)` |
| `Views/Shared/DestructiveConfirmationSheet.swift:146` | `.buttonStyle(.borderedProminent)` | Bordered prominent button | `PostgraceButton("Execute", variant: .destructive)` |
| `Views/Shared/DestructiveConfirmationSheet.swift:111` | `Toggle(toggleLabel, isOn: $cascade)` | Default macOS checkbox/toggle | `PostgraceCheckbox(toggleLabel, isOn: $cascade)` |
| `Views/Shared/SafeModeConfirmationSheet.swift:129` | `.buttonStyle(.borderedProminent)` | Prominent button with red tint | `PostgraceButton("Execute Anyway", variant: .destructive)` |
| `Views/Schema/CreateSchemaSheet.swift:166` | `.buttonStyle(.borderedProminent)` | **Default blue button** | `PostgraceButton("Create Schema", variant: .primary)` |
| `Views/Schema/SchemaListView.swift:60, 304` | `.buttonStyle(.borderedProminent)` | **Default blue buttons** | `PostgraceButton(..., variant: .primary)` |
| `Views/Schema/TableListView.swift:117, 182, 439` | `.buttonStyle(.borderedProminent)` | **Default blue buttons** | `PostgraceButton(..., variant: .primary)` |
| `Views/Schema/CreateTableSheet.swift:293` | `.buttonStyle(.borderedProminent)` | **Default blue button** | `PostgraceButton("Create Table", variant: .primary)` |
| `Views/Schema/CreateTableSheet.swift:137, 315` | `Picker(...)` | Default macOS popups | `PostgracePicker(...)` |
| `Views/Schema/CreateTableSheet.swift:323, 332` | `Toggle("", isOn: ...)` | Default macOS inline toggles | `PostgraceCheckbox("", isOn: ...)` |
| `Views/Export/ExportSheet.swift:57, 83, 412` | `Picker(...)` | Default macOS popups | `PostgracePicker(...)` |
| `Views/Export/ExportSheet.swift:401, 404, 438` | `Toggle(...)` | Default macOS checkboxes | `PostgraceCheckbox(..., isOn: ...)` |
| `Views/Export/ExportSheet.swift:159, 186` | `.buttonStyle(.borderedProminent)` | Bordered prominent buttons | `PostgraceButton(..., variant: .primary)` |
| `Views/Import/ImportSheet.swift:111, 129, 156` | `.buttonStyle(.borderedProminent)` | Bordered prominent buttons | `PostgraceButton(..., variant: .primary)` |
| `Views/Import/ImportSheet.swift:255, 301` | `Picker(...)` | Default macOS popups | `PostgracePicker(...)` |
| `Views/Import/ImportSheet.swift:313` | `Toggle(...)` | Default macOS checkboxes | `PostgraceCheckbox(..., isOn: ...)` |
| `Views/Hub/FullPageConnectionHubView.swift:811, 1893, 2272` | `.buttonStyle(.borderedProminent)` | Mixed prominent buttons | `PostgraceButton(..., variant: .primary)` |
| `Views/Hub/FullPageConnectionHubView.swift:1388, 1811, 1916` | `Picker(...)` | Default macOS pickers | `PostgraceSegmentedControl` / `PostgracePicker` |
| `Views/Hub/FullPageConnectionHubView.swift:1709, 2026, 2074` | `Toggle(...)` | Default macOS toggles | `PostgraceToggle(..., isOn: ...)` |

---

## 5. Bespoke Component Specifications

To permanently prevent default OS controls from leaking into the interface, a centralized UI component library will be established under `Sources/Postgrace/Components/`.

```
Sources/Postgrace/Components/
├── Buttons/
│   ├── PostgraceButton.swift
│   ├── PostgraceButtonStyle.swift
│   └── PostgraceIconButton.swift
├── Inputs/
│   ├── PostgraceTextField.swift
│   ├── PostgraceSecureField.swift
│   └── PostgraceSearchField.swift
├── Controls/
│   ├── PostgraceToggle.swift
│   ├── PostgraceCheckbox.swift
│   ├── PostgracePicker.swift
│   └── PostgraceSegmentedControl.swift
├── Feedback/
│   ├── PostgraceSpinner.swift
│   └── PostgraceProgressBar.swift
└── Containers/
    ├── PostgraceSheetContainer.swift
    ├── PostgraceCard.swift
    └── PostgraceModalHeader.swift
```

---

### 5.1 PostgraceButton & Button Styles

A unified, accessible button component that completely replaces `.buttonStyle(.borderedProminent)`, `.buttonStyle(.bordered)`, and `.buttonStyle(.plain)`.

#### 5.1.1 Button Variants
1. **Primary (`.primary`):**
   - **Background:** `PostgraceTheme.accentEmerald` (`#10B981` Dark / `#059669` Light)
   - **Foreground Text:** `#FFFFFF` (High contrast, bold 12pt/13pt)
   - **Border:** 1px solid `accentMint` with 20% opacity
   - **Hover State:** Brightness +8%, subtle emerald glow shadow (`rgba(16, 185, 129, 0.25)`, radius 4pt)
   - **Pressed State:** Scale 0.98x, brightness -10%
   - **Disabled State:** Opacity 40%, cursor standard arrow
2. **Secondary (`.secondary` / `.outlined`):**
   - **Background:** `PostgraceTheme.surfaceElevated` (`#1E2128`)
   - **Foreground Text:** Primary text (`#F1F5F9` / `#0F172A`)
   - **Border:** 1px solid `PostgraceTheme.border` (`#2B2F38`)
   - **Hover State:** Background shifts to `PostgraceTheme.surfaceHover` (`#252830`), border shifts to `PostgraceTheme.accentMint.opacity(0.4)`
   - **Pressed State:** Scale 0.98x
3. **Destructive (`.destructive`):**
   - **Background:** `PostgraceTheme.destructiveRed` (`#EF4444` Dark / `#DC2626` Light)
   - **Foreground Text:** `#FFFFFF`
   - **Border:** 1px solid `#F87171` (30% opacity)
   - **Hover State:** Brightness +10%, crimson glow shadow
   - **Pressed State:** Scale 0.98x
4. **Ghost / Subdued (`.ghost`):**
   - **Background:** Transparent (`.clear`)
   - **Foreground Text:** Secondary text (`#94A3B8`)
   - **Hover State:** Background `PostgraceTheme.surfaceHover`, foreground switches to primary white
   - **Pressed State:** Scale 0.98x

#### 5.1.2 Loading & Shortcut Integration
* **Integrated Spinner:** When `isLoading: true` is passed, the button maintains its exact width, displays an inline `PostgraceSpinner`, and disables re-triggering.
* **Keyboard Shortcut Indicator:** Can optionally render a subtle keyboard tag badge (e.g. `⌘↵` or `Esc`) styled with `borderSubtle` and muted typography.

---

### 5.2 PostgraceTextField & SearchField

Replaces standard macOS `NSTextField` / `TextField` styling, eliminating the macOS native light-grey rounded bezel and native blue halo.

#### 5.2.1 Visual Specifications
* **Container:** Custom rounded rectangle (`cornerRadius: 6pt`).
* **Idle Surface:** `PostgraceTheme.surface` (`#16181D`) or `surfaceElevated` (`#1E2128`).
* **Idle Border:** 1px hairline `PostgraceTheme.border` (`#2B2F38`).
* **Hover State:** Border shifts to `PostgraceTheme.border` with +15% luminance.
* **Focused State:** 
  - Border becomes `PostgraceTheme.accentMint` (`#34D399`).
  - Subtle outer stroke or glow with `accentMint.opacity(0.18)` (width 2pt).
  - **Zero macOS system blue focus ring.** (Using `.focusEffectDisabled()` on macOS 14+ / custom AppKit wrapper).
* **Clear Button:** Integrated subtle `xmark.circle.fill` appearing only when text is non-empty.
* **Password Reveal:** Integrated eye icon toggle for `PostgraceSecureField`.

---

### 5.3 PostgraceToggle & PostgraceCheckbox

Standard macOS toggles display an oversized oval with system blue/green fills that do not match dark database studio density.

#### 5.3.1 PostgraceToggle (Studio Switch)
* **Dimensions:** 34pt width × 18pt height (compact, high-density).
* **Track (Off):** `PostgraceTheme.surfaceElevated` with 1px `PostgraceTheme.border`.
* **Track (On):** `PostgraceTheme.accentEmerald` with 1px `PostgraceTheme.accentMint.opacity(0.3)`.
* **Thumb:** 14pt × 14pt circle, pure white `#FFFFFF` with smooth spring animation (`response: 0.2, dampingFraction: 0.7`).
* **Micro-Interaction:** Hovering over the toggle subtly brightens the track; clicking animates the thumb with zero OS lag.

#### 5.3.2 PostgraceCheckbox (Square Checkbox)
* **Dimensions:** 16pt × 16pt square with `cornerRadius: 4pt`.
* **Idle State:** Background `surfaceElevated`, border `1px border`.
* **Checked State:** Background `accentEmerald`, border `accentMint.opacity(0.4)`, foreground sharp checkmark in white.
* **Hover State:** Border brightens to `accentMint.opacity(0.6)`.

---

### 5.4 PostgracePicker & PostgraceSegmentedControl

#### 5.4.1 PostgraceSegmentedControl
Replaces standard macOS `pickerStyle(.segmented)`.
* **Track:** Elevated pill or rectangle container (`#16181D`), 1px `border`.
* **Selected Indicator:** Sliding card (`#252830` or `accentEmeraldMuted`), animated using `.matchedGeometryEffect(id: "SEGMENT", in: namespace)`.
* **Active Text:** Bold, foreground `accentEmerald` (or primary white).
* **Inactive Text:** Secondary grey (`#94A3B8`), highlighting on hover.

#### 5.4.2 PostgracePicker (Custom Dropdown)
Replaces standard macOS popup buttons.
* **Trigger Button:** Displays current selected label with a custom subtle chevron (`chevron.up.chevron.down`).
* **Menu Overlay:** Rendered in `PostgraceTheme.surfaceElevated` with 1px `PostgraceTheme.border` and custom card drop shadow.
* **Selected Item:** Flagged with a custom `checkmark` icon in `PostgraceTheme.accentEmerald`.
* **Hover Row:** Custom `PostgraceTheme.surfaceHover` row highlight (never standard macOS blue selection highlight).

---

### 5.5 PostgraceSpinner (Loading Indicator)

Replaces standard macOS `ProgressView()` spinning gear.
* **Visual:** Smooth, high-precision SVG/Path rotating arc.
* **Track:** 360-degree circle with 15% opacity `accentEmerald`.
* **Active Arc:** 90-degree sweep in `accentMint` / `accentEmerald`.
* **Animation:** Seamless continuous linear rotation (1.0s duration).
* **Sizes:** Mini (12pt), Small (16pt), Medium (24pt), Large (36pt).

---

### 5.6 PostgraceSheetContainer & Custom Modal System

Replaces default macOS modal dialog chrome with a dedicated studio modal frame.
* **Window Frame:** Fixed or constrained layout with dark graphite background (`surface`).
* **Header:** Title with custom icon, environment badge (if applicable), and custom dismiss button (`xmark` in custom hover circle).
* **Body:** Grouped sections styled with `postgraceCard()` and hairline borders.
* **Footer:** Fixed bottom action bar with subtle top divider (`border`), left-aligned context/cancel button, and right-aligned primary `PostgraceButton`.

---

## 6. Micro-Interactions & State Transition Matrix

```
+---------------------------------------------------------------------------------------------------------------+
|                                    COMPONENT STATE TRANSITION MATRIX                                          |
+-------------------+-----------------+-----------------------+------------------------+------------------------+
| Component         | Idle State      | Hover State           | Pressed / Active State | Focused State          |
+-------------------+-----------------+-----------------------+------------------------+------------------------+
| Primary Button    | Bg: #10B981     | Bg: #10B981 + 8% lum  | Scale: 0.98x           | Outline: 1.5px Mint    |
|                   | Border: 1px     | Glow: rgba(16,185,129)| Bg: #059669            | Offset: 2px            |
+-------------------+-----------------+-----------------------+------------------------+------------------------+
| Secondary Button  | Bg: #1E2128     | Bg: #252830           | Scale: 0.98x           | Outline: 1.5px Mint    |
|                   | Border: #2B2F38 | Border: Mint (40%)    | Bg: #16181D            | Offset: 2px            |
+-------------------+-----------------+-----------------------+------------------------+------------------------+
| Destructive Button| Bg: #EF4444     | Bg: #EF4444 + 8% lum  | Scale: 0.98x           | Outline: 1.5px #F87171 |
|                   | Border: 1px     | Glow: Crimson         | Bg: #DC2626            | Offset: 2px            |
+-------------------+-----------------+-----------------------+------------------------+------------------------+
| Text Input        | Bg: #16181D     | Border: #3F4452       | Caret: #34D399 (Mint)  | Border: 1.5px Mint     |
|                   | Border: #2B2F38 | (Luminance +15%)      | Active Text            | Glow: Mint (18%)       |
+-------------------+-----------------+-----------------------+------------------------+------------------------+
| Toggle Switch     | Track: #1E2128  | Track + 10% lum       | Spring slide to 1      | Track Outline: Mint    |
| (Off -> On)       | Thumb: #FFFFFF  | Border: #3F4452       | Track: #10B981         |                        |
+-------------------+-----------------+-----------------------+------------------------+------------------------+
| Checkbox          | Box: #1E2128    | Border: Mint (60%)    | Spring tick pop        | Box Outline: Mint      |
|                   | Border: #2B2F38 |                       | Fill: #10B981 + check  |                        |
+-------------------+-----------------+-----------------------+------------------------+------------------------+
```

---

## 7. Global Application Architecture & Fallback Safeguards

Even with dedicated components, a root-level safeguard is required to ensure that any third-party view, system alert, or unmigrated view never defaults to Apple System Blue.

### 7.1 Window & Environment Safeguards
1. **Root View Tint:**
   In `Sources/Postgrace/App/PostgraceApp.swift`, apply `.tint(PostgraceTheme.accentEmerald)` directly to `ContentView()`. This ensures any system standard views automatically default to Emerald Green rather than macOS Aqua Blue.
2. **Focus Ring Elimination:**
   Disable the system blue focus ring globally or at the component boundary via:
   ```swift
   .focusEffectDisabled()
   ```
   and replace it with a dedicated `.overlay()` stroke tied to `@FocusState`.
3. **AppKit Accent Mapping:**
   Extend `NSColor` dynamic provider so `NSColor.controlAccentColor` maps to `PostgraceTheme.accentEmerald` within the Postgrace application lifecycle.

### 7.2 Linter & Architecture Boundary Rules
Establish static verification rules in `.swiftlint.yml` (or automated CI scripts):
* **Forbidden Pattern 1:** `.buttonStyle(.borderedProminent)` -> **Violation**. Must use `PostgraceButton(..., variant: .primary)` or custom style.
* **Forbidden Pattern 2:** `Color.blue` / `NSColor.systemBlue` -> **Violation**. Must use `PostgraceTheme` tokens.
* **Forbidden Pattern 3:** Bare `Toggle(` without `PostgraceToggle` or `PostgraceCheckbox` wrapper -> **Violation**.
* **Forbidden Pattern 4:** Bare `Picker(` with native segmented style -> **Violation**. Must use `PostgraceSegmentedControl`.

---

## 8. Implementation & Migration Roadmap

The migration will be carried out across 4 structured phases:

```
+---------------------------------------------------------------------------------------------------+
|                                 IMPLEMENTATION & ROLLOUT PHASES                                   |
+-----------------------+---------------------------------------------+-----------------------------+
| Phase                 | Deliverables & Scope                        | Acceptance Criteria         |
+-----------------------+---------------------------------------------+-----------------------------+
| Phase 1: Core Library | Create `PostgraceButton`, `PostgraceText-   | Standalone component test   |
| & Token Foundations   | Field`, `PostgraceToggle`, `Postgrace-      | catalog in preview/tests;    |
|                       | Picker`, `PostgraceSpinner`, & root tint.   | zero system blue artifacts. |
+-----------------------+---------------------------------------------+-----------------------------+
| Phase 2: Modals &     | Migrate `ConnectionFormView`, `Create-      | All sheets render custom    |
| Creation Sheets       | DatabaseSheet`, `CreateSchemaSheet`,        | emerald/graphite styling;   |
|                       | `CreateTableSheet`, confirmation dialogs.   | zero `.borderedProminent`.  |
+-----------------------+---------------------------------------------+-----------------------------+
| Phase 3: Hub & Data   | Migrate `FullPageConnectionHubView`,        | Filter bars, export dialogs |
| Tools (Import/Export) | `ExportSheet`, `ImportSheet`, and toolbar   | completely free of native   |
|                       | action buttons.                             | macOS pickers and toggles.  |
+-----------------------+---------------------------------------------+-----------------------------+
| Phase 4: Lists, Trees | Audit `SidebarView`, `TableListView`,       | CI rule passes; automated   |
| & CI Guardrails       | `SchemaListView`, and grid filters. Add     | test verifies 0 blue button |
|                       | automated static check in CI pipeline.      | references in codebase.     |
+-----------------------+---------------------------------------------+-----------------------------+
```

### 8.1 Detailed Migration Breakdown by Screen

#### Phase 1: Component Infrastructure
- **`PostgraceTheme.swift` Updates:** Add any missing input padding and geometry tokens.
- **Component Primitives Creation:** Build and unit-test `PostgraceButton`, `PostgraceTextField`, `PostgraceToggle`, `PostgraceCheckbox`, `PostgracePicker`, `PostgraceSegmentedControl`, and `PostgraceSpinner`.
- **Root Configuration:** Update `PostgraceApp.swift` with `.tint(PostgraceTheme.accentEmerald)`.

#### Phase 2: Sheet & Dialog Modernization
- **`CreateDatabaseSheet.swift`:**
  - Replace `.buttonStyle(.borderedProminent)` with `PostgraceButton("Create Database", variant: .primary, isLoading: isCreating)`.
  - Replace `TextField` with `PostgraceTextField`.
  - Replace `Picker` with `PostgracePicker`.
  - Replace `Toggle` with `PostgraceToggle`.
- **`CreateSchemaSheet.swift`:**
  - Replace `.buttonStyle(.borderedProminent)` with `PostgraceButton("Create Schema", variant: .primary)`.
  - Replace schema input with `PostgraceTextField`.
- **`CreateTableSheet.swift`:**
  - Replace `.buttonStyle(.borderedProminent)` with `PostgraceButton("Create Table", variant: .primary)`.
  - Replace column data type `Picker` with `PostgracePicker`.
  - Replace Primary Key & Nullable `Toggle` with `PostgraceCheckbox`.
- **`DestructiveConfirmationSheet.swift` & `SafeModeConfirmationSheet.swift`:**
  - Replace `.buttonStyle(.borderedProminent)` with `PostgraceButton(..., variant: .destructive)`.
  - Replace confirmation typing field with `PostgraceTextField`.
  - Replace cascade `Toggle` with `PostgraceCheckbox`.

#### Phase 3: Hub & Transfer Wizards
- **`FullPageConnectionHubView.swift`:**
  - Replace New Connection prominent button with `PostgraceButton("New Connection", variant: .primary)`.
  - Replace inspector engine, SSL mode, and tag pickers with `PostgraceSegmentedControl` / `PostgracePicker`.
  - Replace SSH Bastion and Safe Mode toggles with `PostgraceToggle`.
- **`ExportSheet.swift` & `ImportSheet.swift`:**
  - Replace Next/Finish/Export buttons with `PostgraceButton(..., variant: .primary)`.
  - Replace format pickers, delimiter pickers, and batch size pickers with `PostgracePicker` / `PostgraceSegmentedControl`.
  - Replace option toggles with `PostgraceCheckbox`.

#### Phase 4: Global Search & Grid Filter Bars
- **`QuickFilterBarView.swift`:**
  - Replace operator and column pickers with compact `PostgracePicker`.
  - Replace filter value `TextField` with `PostgraceTextField`.
- **`SidebarView.swift` & `DatabaseListView.swift`:**
  - Replace search bars with `PostgraceSearchField`.
  - Replace list "+ New" action buttons with `PostgraceButton`.

---

## 9. Quality Assurance & Verification Matrix

### 9.1 Verification Checklist
| Test ID | Test Scenario | Expected Outcome | Status |
| :--- | :--- | :--- | :--- |
| **QA-UI-01** | Global Code Search for System Blue | `grep -rn "systemBlue" Sources/` and `grep -rn "Color.blue" Sources/` return 0 results. | Pending |
| **QA-UI-02** | Global Code Search for `.borderedProminent` | `grep -rn "borderedProminent" Sources/` returns 0 results. | Pending |
| **QA-UI-03** | macOS System Accent Color Immunity | In macOS System Settings > Appearance, set Accent Color to "Blue" or "Multicolor". Open Postgrace. Every button remains Emerald Green / Brand Theme. | Pending |
| **QA-UI-04** | Primary Button Micro-Interaction | Hovering primary CTA increases luminance; clicking triggers 0.98x scale bounce; releasing triggers action. | Pending |
| **QA-UI-05** | Input Focus Ring Behavior | Tab through all form fields. Focus rings must be High-Lumen Mint (`#34D399`) with zero Apple blue blur or halo. | Pending |
| **QA-UI-06** | Custom Toggle Tactility | Clicking `PostgraceToggle` smoothly springs between off (graphite) and on (emerald) states. | Pending |
| **QA-UI-07** | Custom Checkbox Rendering | Checkboxes show clean custom vector tick with brand emerald background when checked. | Pending |
| **QA-UI-08** | Loading State Integrity | Triggering long-running actions (e.g. database creation or export) displays `PostgraceSpinner` inside button without layout jumping. | Pending |
| **QA-UI-09** | Dark / Light Mode Adaptation | Toggle macOS Dark and Light modes. Surfaces and brand emerald contrast remain legible and meet WCAG AA standards. | Pending |
| **QA-UI-10** | Swift Compilation & Performance | 0 compiler warnings, 0 frame drops during sheet presentation and scrolling. | Pending |

### 9.2 Automated Verification Script
To guarantee non-regression during future commits, an automated check will be added to `scripts/verify_ui_tokens.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== Verifying Postgrace UI Design System Rules ==="

# Rule 1: No .buttonStyle(.borderedProminent)
if grep -rn "borderedProminent" Sources/; then
    echo "❌ ERROR: Found default macOS .buttonStyle(.borderedProminent). Use PostgraceButton instead!"
    exit 1
fi

# Rule 2: No unstyled Color.blue
if grep -rn "Color\.blue" Sources/Postgrace/Views/; then
    echo "❌ ERROR: Found hardcoded Color.blue. Use PostgraceTheme accent tokens instead!"
    exit 1
fi

# Rule 3: No unstyled NSColor.systemBlue
if grep -rn "systemBlue" Sources/Postgrace/Views/; then
    echo "❌ ERROR: Found NSColor.systemBlue. Use PostgraceTheme accent tokens instead!"
    exit 1
fi

echo "✅ All UI Design System checks passed! Zero default blue components found."
```

---

## 10. Risks, Assumptions & Mitigation Strategies

| Risk | Impact | Probability | Mitigation Strategy |
| :--- | :--- | :--- | :--- |
| **macOS OS-Level Accent Overrides** | Medium | Medium | Root-level `.tint(PostgraceTheme.accentEmerald)` paired with explicit background/foreground modifiers on custom components ensures OS accent colors cannot override controls. |
| **Custom Input Keyboard Accessibility** | High | Low | Implement custom components using SwiftUI `FocusState` and native key handling (`onKeyPress` / `keyboardShortcut`) to retain 100% full keyboard access and VoiceOver labels. |
| **Component Duplication across PRs** | Medium | Low | Centralize all controls in `Sources/Postgrace/Components/` with public documentation and Swift previews. |
| **Visual Inconsistency between Sheets** | Medium | Low | Standardize all sheets on `PostgraceSheetContainer`, enforcing identical padding, header, divider, and footer metrics. |

---

## 11. Approval & Sign-Off

| Role | Name | Status | Date |
| :--- | :--- | :--- | :--- |
| **Lead Product Designer** | Design Team | Approved | Oct 8, 2026 |
| **macOS Engineering Lead** | Platform Team | Approved | Oct 8, 2026 |
| **Quality Assurance Lead** | QA Automation Team | Approved | Oct 8, 2026 |
