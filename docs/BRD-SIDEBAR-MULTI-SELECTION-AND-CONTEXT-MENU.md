# Business Requirements Document (BRD)
## Project: Native Sidebar Multi-Selection & Context Menu System for Postgrace
**Document Version:** 1.0.0  
**Status:** In Review / Ready for Approval  
**Owner:** Product & Engineering  
**Target Release:** Postgrace v2.1 (Sidebar Experience Modernization)  
**Date:** October 7, 2026  

---

## 1. Executive Summary

### 1.1 Context & Background
Postgrace is a native macOS database management studio engineered with Swift and SwiftUI, delivering sub-second startup times, memory efficiency (<50 MB baseline), and strict adherence to Apple’s Human Interface Guidelines (macOS HIG). The application sidebar serves as the central command tree for exploring relational database hierarchies—including databases, schemas, tables, and views.

Currently, Postgrace supports only single-item active selection in the sidebar. When users need to perform actions across multiple tables or schemas (such as batch exporting schemas, dropping temporary tables, generating multi-table query joins, or copying lists of qualified table names), they are forced to repeat single-table actions sequentially or manually write custom SQL in the query editor.

### 1.2 Problem Statement
1. **Inefficient Repetitive Workflows:** Users cannot select multiple tables or schemas simultaneously. Common tasks such as exporting 5 tables require repeating the export wizard 5 distinct times.
2. **Missing Native macOS Selection Patterns:** macOS users expect standard system interactions: `⌘-Click` (disjoint multi-select), `⇧-Click` (contiguous range select), `⌘-A` (select all), and arrow key navigation with modifier keys.
3. **Limited Secondary Click / 2-Finger Tap Interactions:** The existing right-click context menu only addresses individual tables with a minimal set of options. There is no contextual adaptation when multiple items are highlighted, and schema-level contextual actions are underutilized.
4. **Lack of Multi-Object Safeguards:** Destructive batch actions (e.g., dropping or truncating multiple tables) have no unified visual confirmation safeguards or integration with Postgrace's Safe Mode guardrails.

### 1.3 Solution Overview
Implement a **Native Sidebar Multi-Selection & Gesture-Driven Context Menu System** in Postgrace:
* Support **Single Click**, **⌘-Click (Disjoint Selection)**, **⇧-Click (Contiguous Range Selection)**, and **⌘-A (Select All in Scope)** for schemas and tables.
* Recognize native **Trackpad 2-Finger Tap** and mouse **Right-Click** events to present dynamically formulated context menus tailored to the exact selection context (Single Table, Multiple Tables, Single Schema, Multiple Schemas, or Canvas Background).
* Provide rich productivity actions (multi-table SQL generation, batch clipboard formats, bulk export, bulk truncate/drop with environment-aware safety guardrails).
* Update the bottom sidebar metadata inspector into a responsive summary container (switching from single-table details to multi-table aggregated statistics).

---

## 2. Business Objectives & Success Metrics

### 2.1 Strategic Business Goals
* **Elevate Developer Productivity:** Reduce user time spent on bulk schema/table tasks by over 70%.
* **Deliver Authentic macOS Feel:** Align sidebar navigation with native macOS applications like Finder, Xcode, and Mail.
* **Prevent Production Data Incidents:** Integrate Postgrace’s `SQLSafetyAnalyzer` and environment tags into bulk operations to prevent accidental bulk data destruction.

### 2.2 Key Performance Indicators (KPIs)
| Metric | Baseline (Current) | Target (v2.1) | Verification Method |
| :--- | :--- | :--- | :--- |
| **Sidebar Selection Capability** | Single item only | Single, Disjoint (`⌘`), Range (`⇧`), All (`⌘-A`) | Automated UI tests & interaction verification |
| **Secondary Click Response Time** | ~50ms | < 16ms (Instantaneous 120 FPS popover render) | Instruments Time Profiler on Apple Silicon |
| **Bulk Export Overhead (5 Tables)** | 5 separate wizard runs | 1 consolidated batch wizard run | User workflow step analysis |
| **Accidental Destruction Incidents** | 0 guardrails on batch | 100% blocked without explicit confirmation | Safety guardrail test suite |
| **Large Tree Scroll & Selection (2,000 tables)** | N/A | Smooth 120Hz scrolling, zero frame drops on multi-select | Core Animation Instruments trace |

---

## 3. User Personas & Real-World Use Cases

### 3.1 Target Personas
1. **Full-Stack & Backend Engineer (Alex):**
   - *Scenario:* Refactoring database schema migrations. Frequently needs to copy a comma-separated list of 10 newly created tables to import into seed scripts, or generate a query template joining three related lookup tables.
2. **DevOps & Data Platform Engineer (Brenda):**
   - *Scenario:* Cleaning up staging databases after running integration test pipelines. Needs to select 15 transient test tables (`test_*`) and batch drop or truncate them in one swift, verified action.
3. **Data Analyst & BI Specialist (Carlos):**
   - *Scenario:* Preparing reporting datasets. Needs to export 8 dimension and fact tables into individual CSV or JSON files without clicking through 8 independent dialogs.

### 3.2 High-Value User Stories
* **US-01:** *As a developer, I want to hold `⌘` and click multiple tables so that I can group-select specific tables across an expanded schema.*
* **US-02:** *As a developer, I want to click a table, hold `⇧`, and click another table so that all intermediate tables in that schema are highlighted.*
* **US-03:** *As a Mac user, I want to perform a 2-finger tap on an unselected table to immediately select it and view its context menu without deselecting other items prematurely.*
* **US-04:** *As a developer, I want to 2-finger tap an existing multi-selection of tables to see a dedicated "Batch Actions" menu (Batch Export, Copy Names, Batch Drop, Query Selected).*
* **US-05:** *As a developer, I want to 2-finger tap a schema header to quickly create tables, export the full DDL, or refresh only that schema's introspection cache.*

---

## 4. User Interaction & Gesture Specifications

### 4.1 Selection Interaction Rules

```
+---------------------------------------------------------------------------------------------------+
|                                  SIDEBAR SELECTION MATRIX                                         |
+---------------------+-------------------------------+---------------------------------------------+
| Gesture / Event     | Target                        | Resulting State                             |
+---------------------+-------------------------------+---------------------------------------------+
| Single Primary Click| Unselected Item               | Clears previous selection; selects target;  |
|                     |                               | sets active anchor; loads table metadata.   |
| Single Primary Click| Already Selected Item (Solo)  | Retains selection; preserves focus.         |
| ⌘-Click (Command)   | Any Item                      | Toggles target item in/out of selection set.|
|                     |                               | Anchor stays at last clicked item.          |
| ⇧-Click (Shift)     | Sibling Item in same Schema   | Selects continuous range from anchor to     |
|                     |                               | target item inclusive.                      |
| ⌘-A (Command-A)     | Focused Schema / Tree Scope   | Selects all visible tables in active schema |
|                     |                               | (or all schemas if schema header focused).  |
| Escape Key          | Multi-selection active        | Collapses multi-selection to single anchor. |
+---------------------+-------------------------------+---------------------------------------------+
```

### 4.2 Trackpad 2-Finger Tap / Secondary Click Event Handling

In macOS, a 2-finger tap on the trackpad or a physical secondary click triggers an `NSResponder.rightMouseDown(with:)` event.

1. **2-Finger Tap on an UNSELECTED Item:**
   - **Action:** Immediately select the clicked item (replacing any prior selection unless `⌘` or `⇧` is concurrently depressed).
   - **Visual:** Apply the active selection highlight to the clicked row.
   - **Menu:** Display the **Single Item Context Menu** corresponding to the item's type (Single Table or Single Schema).

2. **2-Finger Tap on an ALREADY SELECTED Item (Part of Multi-Selection):**
   - **Action:** Preserve the entire multi-selection set intact.
   - **Visual:** Keep all selected rows in the active highlight state.
   - **Menu:** Display the **Batch Context Menu** showing actions applicable to `{N} Selected Items`.

3. **2-Finger Tap on Blank Sidebar Canvas / Empty Area:**
   - **Action:** Maintain or clear active selection depending on clicked area.
   - **Menu:** Display the **Sidebar Canvas Global Context Menu** (Refresh All, Expand All, Collapse All, New Schema...).

### 4.3 Multi-Selection Scope & Invariants
* **Homogeneous Scope Preference:** Tables and Schemas exist at different hierarchical tiers. Postgrace enforces a clean hierarchy policy:
  - If a user selects tables, selection is constrained to tables. Selecting a schema header clears table selections.
  - Cross-schema table multi-selection is permitted: A user may select `public.users` and `audit.log_events` concurrently using `⌘-Click`.
* **Selection Limit Safeguard:** While there is no hard ceiling for table selection, any batch action opening tabs (e.g., "Open All in Tabs") prompts a confirmation if `N > 8` to avoid overwhelming system resources.

---

## 5. Formulated Context Menu Options

The following matrices define the exact menu items, visual icons (SF Symbols), keyboard shortcuts, separators, and behaviors for each context menu permutation.

---

### 5.1 Option Matrix: Single Table / View (2-Finger Tap on 1 Table)

```
+-----------------------------------------------------------------------------------------------+
| CONTEXT: Single Table / View ('public'.'users')                                               |
+----+------------------------------------+------------------+-------------+--------------------+
| ID | Menu Item Label                    | SF Symbol Icon   | Shortcut    | Action Description |
+----+------------------------------------+------------------+-------------+--------------------+
| 01 | Open Data                          | tablecells       | Return      | Opens data grid tab|
| 02 | Open Structure                     | square.split.2x2 | ⌥ Return    | Opens schema DDL   |
| 03 | Open in New Tab                    | plus.rectangle   | ⌘ Return    | Forces duplicate   |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 04 | Query in SQL Editor (LIMIT 100)    | terminal         | ⌘T          | Populates editor   |
| 05 | Script as >                        | chevron.right    | Submenu     | SQL templates:     |
|    |   • SELECT Statement               | doc.text         |             | SELECT cols FROM.. |
|    |   • INSERT Template                | text.badge.plus  |             | INSERT INTO ..     |
|    |   • UPDATE Template                | pencil.line      |             | UPDATE .. SET ..   |
|    |   • DELETE Template                | trash            |             | DELETE FROM ..     |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 06 | Copy >                             | chevron.right    | Submenu     | Clipboard formats: |
|    |   • Copy Table Name                | doc.on.clipboard | ⌘C          | "users"            |
|    |   • Copy Qualified Name            | quote.opening    | ⌥⌘C         | "public"."users"   |
|    |   • Copy SELECT Query              | text.quote       | ⇧⌘C         | SELECT * FROM ...  |
|    |   • Copy DDL (CREATE TABLE)        | curlybraces      |             | Full CREATE TABLE  |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 07 | Export Table Data…                 | arrow.up.doc     | ⌘E          | Opens export modal |
| 08 | Import Data to Table…              | arrow.down.doc   | ⌘I          | Opens import modal |
| 09 | Duplicate / Clone Table Structure… | square.on.square |             | Creates copy modal |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 10 | Truncate Table… (Safe Mode)        | exclaim.triangle |             | Truncate dialog    |
| 11 | Drop Table… (Safe Mode)            | trash.fill       | ⌘⌫          | Destructive drop   |
+----+------------------------------------+------------------+-------------+--------------------+
```

---

### 5.2 Option Matrix: Multiple Tables Selected (2-Finger Tap on {N} Tables)

When two or more tables are selected (e.g., `users`, `orders`, `line_items`):

```
+-----------------------------------------------------------------------------------------------+
| CONTEXT: Multiple Tables Selected ({N} Tables Selected)                                       |
+----+------------------------------------+------------------+-------------+--------------------+
| ID | Menu Item Label                    | SF Symbol Icon   | Shortcut    | Action Description |
+----+------------------------------------+------------------+-------------+--------------------+
| 01 | Open All in Tabs ({N})             | square.stack     | Return      | Opens N data tabs  |
|    |                                    |                  |             | (confirms if N > 8)|
| 02 | Query Selected in SQL Editor       | terminal         | ⌘T          | Emits SELECT for   |
|    |                                    |                  |             | all selected tables|
| 03 | Generate JOIN Query Scratchpad…    | link.circle      |             | Opens SQL tab with |
|    |                                    |                  |             | auto FK JOIN query |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 04 | Copy >                             | chevron.right    | Submenu     | Batch clipboard:   |
|    |   • Copy Names (Comma-separated)   | doc.on.doc       | ⌘C          | users, orders, ... |
|    |   • Copy Names (Newline-separated) | list.bullet      |             | users\norders\n... |
|    |   • Copy Qualified Names           | quote.opening    | ⌥⌘C         | "public"."users",..|
|    |   • Copy Combined SELECT Queries   | text.quote       |             | Multi SELECTs      |
|    |   • Copy Combined DDL              | curlybraces      |             | Combined DDL dump  |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 05 | Batch Export Selected ({N} Tables)…| arrow.up.doc.fill| ⌘E          | Consolidated Wizard|
|    |                                    |                  |             | (Zip / Multi-file) |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 06 | Batch Truncate ({N} Tables)…       | exclaim.triangle |             | High-risk modal    |
| 07 | Batch Drop ({N} Tables)…           | trash.fill       | ⌘⌫          | Destructive modal  |
|    |                                    |                  |             | (Type count to ok) |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 08 | Deselect All                       | xmark.circle     | Escape      | Clears selection   |
+----+------------------------------------+------------------+-------------+--------------------+
```

---

### 5.3 Option Matrix: Single Schema (2-Finger Tap on 1 Schema)

```
+-----------------------------------------------------------------------------------------------+
| CONTEXT: Single Schema ('public')                                                             |
+----+------------------------------------+------------------+-------------+--------------------+
| ID | Menu Item Label                    | SF Symbol Icon   | Shortcut    | Action Description |
+----+------------------------------------+------------------+-------------+--------------------+
| 01 | Browse Tables Catalog              | tablecells       |             | Opens catalog tab  |
| 02 | New Table in '{schema}'…           | plus.rectangle   | ⌘N          | Shows table creator|
| 03 | New View in '{schema}'…            | eye.circle       |             | Opens view creator |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 04 | Refresh Schema                     | arrow.clockwise  | ⌘R          | Reloads introspection|
| 05 | Expand All Tables in Schema        | chevron.down     |             | Unfurls node       |
| 06 | Collapse All Tables in Schema      | chevron.right    |             | Furls node         |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 07 | Copy >                             | chevron.right    | Submenu     | Clipboard formats: |
|    |   • Copy Schema Name               | doc.on.clipboard | ⌘C          | "public"           |
|    |   • Copy DDL (CREATE SCHEMA)       | curlybraces      |             | CREATE SCHEMA ...  |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 08 | Export Schema…                     | arrow.up.doc     | ⌘E          | Dump DDL + Data    |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 09 | Truncate All Tables in Schema…     | exclaim.triangle |             | Safe Mode modal    |
| 10 | Drop Schema '{schema}'…            | trash.fill       | ⌘⌫          | RESTRICT/CASCADE   |
+----+------------------------------------+------------------+-------------+--------------------+
```

---

### 5.4 Option Matrix: Multiple Schemas Selected (2-Finger Tap on {N} Schemas)

```
+-----------------------------------------------------------------------------------------------+
| CONTEXT: Multiple Schemas Selected ({N} Schemas Selected)                                     |
+----+------------------------------------+------------------+-------------+--------------------+
| ID | Menu Item Label                    | SF Symbol Icon   | Shortcut    | Action Description |
+----+------------------------------------+------------------+-------------+--------------------+
| 01 | Refresh Selected Schemas ({N})     | arrow.clockwise  | ⌘R          | Re-queries caches  |
| 02 | Expand All Selected                | chevron.down     |             | Expands all nodes  |
| 03 | Collapse All Selected              | chevron.right    |             | Collapses all nodes|
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 04 | Copy Schema Names (Comma-separated)| doc.on.doc       | ⌘C          | "public, audit"    |
| 05 | Batch Export Schemas ({N})…        | arrow.up.doc.fill| ⌘E          | Batch schema dump  |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 06 | Batch Drop Schemas ({N})…          | trash.fill       | ⌘⌫          | Strict modal alert |
+----+------------------------------------+------------------+-------------+--------------------+
| 07 | Deselect All                       | xmark.circle     | Escape      | Clears selection   |
+----+------------------------------------+------------------+-------------+--------------------+
```

---

### 5.5 Option Matrix: Canvas Background (2-Finger Tap on Blank Area)

```
+-----------------------------------------------------------------------------------------------+
| CONTEXT: Blank Area / Sidebar Canvas                                                          |
+----+------------------------------------+------------------+-------------+--------------------+
| ID | Menu Item Label                    | SF Symbol Icon   | Shortcut    | Action Description |
+----+------------------------------------+------------------+-------------+--------------------+
| 01 | Refresh All Schemas & Tables       | arrow.clockwise  | ⌘R          | Full sync          |
| 02 | Expand All Schemas                 | arrow.down.right |             | Expands all tree   |
| 03 | Collapse All Schemas               | arrow.up.left    |             | Collapses all tree |
+----+------------------------------------+------------------+-------------+--------------------+
| -- | --- Divider ---                    |                  |             |                    |
+----+------------------------------------+------------------+-------------+--------------------+
| 04 | New Schema…                        | folder.badge.plus| ⇧⌘N         | Create schema sheet|
| 05 | Open Databases Catalog             | cylinder.split   | ⌘D          | Catalogs tab       |
| 06 | Open Schemas Catalog               | square.3.layers  | ⌘S          | Schemas tab        |
+----+------------------------------------+------------------+-------------+--------------------+
```

---

## 6. Destructive Actions & Safe Mode Guardrails

Batch operations introduce heightened operational risk. Postgrace enforces a multi-tier defense system against accidental data loss:

```
+----------------------------------------------------------------------------------------------------+
|                                    BATCH SAFETY ARCHITECTURE                                       |
+---------------------+-------------------------------+----------------------------------------------+
| Environment Tag     | Visual Alert Level            | Confirmation Safeguard Mechanism             |
+---------------------+-------------------------------+----------------------------------------------+
| Development (Local) | Soft Amber Warning Sheet      | Standard "Confirm Truncate / Drop" button    |
| Staging / UAT       | Orange Warning Sheet          | Checkbox verification: "[x] I understand"    |
| Production          | High-Visibility Red Banner    | Explicit typed challenge:                    |
|                     |                               | User must type "DROP 5 TABLES" to unlock OK  |
+---------------------+-------------------------------+----------------------------------------------+
```

### 6.1 Batch Truncate Safeguard Workflow
1. When user selects "Batch Truncate ({N} Tables)…", a dedicated modal sheet opens.
2. The sheet lists every affected table, its schema, current estimated row count, and whether foreign keys reference it.
3. If Postgrace Safe Mode is active on the connection, the action is disabled until Safe Mode is temporarily overridden with an explicit prompt.
4. Execution runs inside a single atomic transaction block (`BEGIN; TRUNCATE ...; COMMIT;`) with immediate rollback on any error.

### 6.2 Batch Drop Safeguard Workflow
1. Displays the list of `{N}` tables with options for `RESTRICT` vs. `CASCADE`.
2. Clearly indicates any known child foreign keys that will be severed.
3. In Production environments, requires typing the exact string: `DROP {N} TABLES`.

---

## 7. Technical Architecture & Component Design

```
+--------------------------------------------------------------------------------------------------+
|                                    SIDEBAR ARCHITECTURE                                          |
|                                                                                                  |
|   +------------------------------------------------------------------------------------------+   |
|   |                              SidebarSelectionViewModel                                  |   |
|   |  - selectedItems: Set<SidebarItemIdentifier>                                             |   |
|   |  - selectionAnchor: SidebarItemIdentifier?                                               |   |
|   |  - isBatchActive: Bool                                                                   |   |
|   |  - selectedTableCount: Int                                                               |   |
|   |  - selectedSchemaCount: Int                                                              |   |
|   +------------------------------------------------------------------------------------------+   |
|                                             |                                                    |
|                      +----------------------+----------------------+                             |
|                      |                                             |                             |
|                      v                                             v                             |
|   +------------------------------------+        +------------------------------------+           |
|   |        SidebarNodeRowView          |        |      SidebarMetadataInspector      |           |
|   |  - Handles Click / Modifier Events |        |  - Solo Mode: Detailed Stats       |           |
|   |  - Native 2-Finger Tap Responder   |        |  - Multi Mode: Aggregate Summary   |           |
|   |  - Context Menu Builder Dispatcher |        |    ("4 Tables • 185k Rows • 42MB") |           |
|   +------------------------------------+        +------------------------------------+           |
|                      |                                                                           |
|                      v                                                                           |
|   +------------------------------------------------------------------------------------------+   |
|   |                              SidebarContextMenuDispatcher                                |   |
|   |  - route(for: selectionState, clickedItem: item) -> AnyView                              |   |
|   |  - Builds Single vs. Batch context menus dynamically                                     |   |
|   +------------------------------------------------------------------------------------------+   |
+--------------------------------------------------------------------------------------------------+
```

### 7.1 Data Model: `SidebarItemIdentifier`

```swift
public enum SidebarItemIdentifier: Hashable, Identifiable, Sendable {
    case schema(name: String)
    case table(schema: String, name: String)

    public var id: String {
        switch self {
        case .schema(let name):
            return "schema:\(name)"
        case .table(let schema, let name):
            return "table:\(schema).\(name)"
        }
    }
}
```

### 7.2 Selection State Store: `SidebarSelectionViewModel`

```swift
@Observable
public final class SidebarSelectionViewModel {
    public var selectedItems: Set<SidebarItemIdentifier> = []
    public var selectionAnchor: SidebarItemIdentifier? = nil

    public var isBatchSelection: Bool {
        selectedItems.count > 1
    }

    public var selectedTables: [SidebarItemIdentifier] {
        selectedItems.filter {
            if case .table = $0 { return true }
            return false
        }
    }

    public var selectedSchemas: [SidebarItemIdentifier] {
        selectedItems.filter {
            if case .schema = $0 { return true }
            return false
        }
    }

    public func selectSingle(_ item: SidebarItemIdentifier) {
        selectedItems = [item]
        selectionAnchor = item
    }

    public func toggleDisjoint(_ item: SidebarItemIdentifier) {
        if selectedItems.contains(item) {
            selectedItems.remove(item)
            if selectionAnchor == item {
                selectionAnchor = selectedItems.first
            }
        } else {
            selectedItems.insert(item)
            selectionAnchor = item
        }
    }

    public func selectRange(to target: SidebarItemIdentifier, orderedVisibleItems: [SidebarItemIdentifier]) {
        guard let anchor = selectionAnchor,
              let anchorIndex = orderedVisibleItems.firstIndex(of: anchor),
              let targetIndex = orderedVisibleItems.firstIndex(of: target) else {
            selectSingle(target)
            return
        }

        let start = min(anchorIndex, targetIndex)
        let end = max(anchorIndex, targetIndex)
        let rangeItems = orderedVisibleItems[start...end]
        selectedItems.formUnion(rangeItems)
    }

    public func clear() {
        selectedItems.removeAll()
        selectionAnchor = nil
    }
}
```

### 7.3 Native Trackpad 2-Finger Tap Event Handling

To guarantee 100% native macOS Trackpad responsiveness without gesture conflicts:
1. Wrap sidebar row elements with native AppKit contextual responder (`NSViewRepresentable` with custom `menu(for event: NSEvent)`) or SwiftUI's native `.contextMenu` attached to row container views.
2. In the secondary click handler, evaluate whether `clickedItem` is already a member of `selectedItems`:
   - If `selectedItems.contains(clickedItem)`: Retain `selectedItems` and render the **Batch Menu**.
   - If `!selectedItems.contains(clickedItem)`: Call `selectSingle(clickedItem)` and render the **Single Item Menu**.

---

## 8. Bottom Sidebar Metadata Box: Dynamic Aggregation

When the user selects items in the sidebar, the bottom metadata inspector (`selectedTableMetadataBox`) adapts dynamically:

### 8.1 Single Table Selected (Current Detail Mode)
* Displays Table Name, Type (TABLE / VIEW), Schema Name.
* Accurate Row Count (asynchronously fetched).
* Disk Size & Index Size.
* Column Count & Primary Key name in Sky Accent color.

### 8.2 Multiple Tables Selected (Aggregate Summary Mode)
* **Title:** `MULTI-TABLE SELECTION`
* **Count Badge:** `{N} TABLES SELECTED`
* **Parent Schemas:** List of schemas involved (e.g., `public, audit`).
* **Aggregate Rows:** Estimated sum of rows across all selected tables.
* **Aggregate Disk Size:** Sum of storage footprint (e.g., `14.2 MB total`).
* **Quick Batch Toolbar:** Quick icons for `Batch Export`, `Copy Names`, and `Batch Query`.

---

## 9. Implementation Roadmap & Milestones

```
+----------------------------------------------------------------------------------------------------+
|                                    DEVELOPMENT MILESTONES                                          |
+-------------+------------------------------------+------------+------------------------------------+
| Milestone   | Scope & Deliverables               | Duration   | Dependencies                       |
+-------------+------------------------------------+------------+------------------------------------+
| Phase 1     | SidebarSelectionViewModel &        | 3 Days     | None                               |
|             | Modifier Key Event Engine          |            | (Core Selection Model)             |
| Phase 2     | Single-Item Context Menu Overhaul  | 2 Days     | Phase 1                            |
|             | (Submenus for Script As, Copy)     |            | (Updated Row Views)                |
| Phase 3     | Batch Context Menus & Multi-Table  | 3 Days     | Phase 1, Phase 2                   |
|             | Actions (Batch Export / Scripting) |            | (Batch UI Builders)                |
| Phase 4     | Batch Destructive Confirmation     | 2 Days     | SafeModeGuard, SQLSafetyAnalyzer   |
|             | Modals (Truncate / Drop)           |            |                                    |
| Phase 5     | Dynamic Multi-Table Metadata Box & | 2 Days     | Phase 3                            |
|             | Large Tree Performance Testing     |            |                                    |
+-------------+------------------------------------+------------+------------------------------------+
| Total       | Complete Delivery                  | 12 Days    | Target: Postgrace v2.1             |
+-------------+------------------------------------+------------+------------------------------------+
```

---

## 10. QA Verification & Test Matrix

| Test ID | Category | Scenario | Expected Behavior | Status |
| :--- | :--- | :--- | :--- | :--- |
| **TC-01** | Selection | Primary click on table `users` | Selects `users`; deselects any previously selected row. | Planned |
| **TC-02** | Selection | `⌘-Click` on `orders` while `users` is selected | Both `users` and `orders` remain selected. | Planned |
| **TC-03** | Selection | `⇧-Click` on row 5 from row 2 | Rows 2, 3, 4, 5 are all selected contiguously. | Planned |
| **TC-04** | Gesture | 2-finger tap on unselected table `products` | Exclusively selects `products` and displays Single Table Context Menu. | Planned |
| **TC-05** | Gesture | 2-finger tap on `users` when `users` + `orders` selected | Retains both tables selected; displays Batch Context Menu with count 2. | Planned |
| **TC-06** | Context Menu | Select "Copy Names (Comma-separated)" on 3 tables | System clipboard contains `table1, table2, table3`. | Planned |
| **TC-07** | Safety | Batch Drop 4 tables in Production environment | Red banner modal displays; requires typing `DROP 4 TABLES`. | Planned |
| **TC-08** | Performance | Multi-selection across 1,500 tables | No UI hitching, memory consumption remains under 60 MB. | Planned |
| **TC-09** | Keyboard | Press `Escape` with 5 tables selected | Multi-selection collapses to single focused anchor. | Planned |
| **TC-10** | Metadata Box | Switch from 1 table to 3 tables | Metadata box switches from single detail to multi-table summary badge. | Planned |

---

## 11. Appendix: Keyboard Shortcuts Summary

* `⌘-Click`: Toggle item in/out of selection.
* `⇧-Click`: Extend selection range from active anchor.
* `⌘-A`: Select all items in active scope.
* `Escape`: Clear multi-selection.
* `Return`: Open primary Data Grid tab for selected item(s).
* `⌥-Return`: Open Structure / DDL tab.
* `⌘-T`: Open query tab prefilled with SELECT statement(s).
* `⌘-E`: Trigger Export Wizard (single or batch).
* `⌘-C`: Copy Name(s).
* `⌥-⌘-C`: Copy Qualified Name(s).
* `⌘-⌫`: Trigger Drop confirmation.
