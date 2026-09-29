import Foundation
import Observation

/// ViewModel managing document tabs in the active workspace.
@Observable
public class WorkspaceTabViewModel {
    public var tabs: [WorkspaceTab] = []
    public var activeTabId: UUID?
    private var queryCounter: Int = 1

    public init() {
        // Open a default Query #1 tab on startup
        openQueryTab()
    }

    /// The currently active tab.
    public var activeTab: WorkspaceTab? {
        tabs.first { $0.id == activeTabId }
    }

    /// Opens or switches to a table data tab.
    public func openTableTab(schema: String, table: String) {
        // If tab is already open for this schema/table, select it
        if let existing = tabs.first(where: {
            if case .table(let s, let t) = $0.type, s == schema, t == table {
                return true
            }
            return false
        }) {
            activeTabId = existing.id
            return
        }

        let tab = WorkspaceTab(title: table, type: .table(schema: schema, table: table))
        tabs.append(tab)
        activeTabId = tab.id
    }

    /// Opens or switches to a table structure tab.
    public func openStructureTab(schema: String, table: String) {
        if let existing = tabs.first(where: {
            if case .structure(let s, let t) = $0.type, s == schema, t == table {
                return true
            }
            return false
        }) {
            activeTabId = existing.id
            return
        }

        let tab = WorkspaceTab(title: "Structure: \(table)", type: .structure(schema: schema, table: table))
        tabs.append(tab)
        activeTabId = tab.id
    }

    /// Opens or switches to the Schemas catalog tab.
    public func openSchemasTab() {
        if let existing = tabs.first(where: {
            if case .schemas = $0.type { return true }
            return false
        }) {
            activeTabId = existing.id
            return
        }

        let tab = WorkspaceTab(title: "Schemas", type: .schemas)
        tabs.append(tab)
        activeTabId = tab.id
    }

    /// Opens or switches to the Tables catalog tab for a given schema.
    public func openTablesTab(schema: String) {
        if let existing = tabs.first(where: {
            if case .tables(let s) = $0.type, s == schema { return true }
            return false
        }) {
            activeTabId = existing.id
            return
        }

        let tab = WorkspaceTab(title: "Tables: \(schema)", type: .tables(schema: schema))
        tabs.append(tab)
        activeTabId = tab.id
    }

    /// Opens a new SQL Query tab.
    public func openQueryTab() {
        let title = "Query #\(queryCounter)"
        queryCounter += 1
        let tab = WorkspaceTab(title: title, type: .query(id: UUID(), title: title))
        tabs.append(tab)
        activeTabId = tab.id
    }

    /// Closes the specified tab.
    public func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)

        if activeTabId == id {
            if !tabs.isEmpty {
                let newIndex = min(index, tabs.count - 1)
                activeTabId = tabs[newIndex].id
            } else {
                openQueryTab()
            }
        }
    }

    /// Closes all tabs except the active one.
    public func closeOtherTabs(id: UUID) {
        tabs.removeAll { $0.id != id }
        activeTabId = id
    }
}
