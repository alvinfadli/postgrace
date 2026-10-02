import Foundation

/// Types of tabs supported in the workspace.
public enum TabType: Hashable {
    case table(schema: String, table: String)
    case query(id: UUID, title: String)
    case structure(schema: String, table: String)
    case schemas
    case tables(schema: String)
    case databases
}

/// Represents an open tab in the Postgrace document workspace.
public struct WorkspaceTab: Identifiable, Hashable {
    public let id: UUID
    public var title: String
    public var type: TabType

    public init(id: UUID = UUID(), title: String, type: TabType) {
        self.id = id
        self.title = title
        self.type = type
    }
}
