import Foundation
import SwiftData

/// A user-created grouping for tasks (sidebar row + task chips). Tasks link to a project
/// via `DailyTodo.projectID`; deleting a project leaves its tasks untouched (link nulled).
/// Every stored property has a default/optional so lightweight migration stays safe.
@Model
public final class Project {
    @Attribute(.unique) public var id: UUID = UUID()
    public var name: String = ""
    /// SF Symbol shown in the sidebar and on task chips.
    public var symbolName: String = "folder"
    public var sortOrder: Int = 0
    public var createdDate: Date = Date.now

    public init(
        id: UUID = UUID(),
        name: String,
        symbolName: String = "folder",
        sortOrder: Int = 0,
        createdDate: Date = .now
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.createdDate = createdDate
    }
}

extension Project: Identifiable {}
