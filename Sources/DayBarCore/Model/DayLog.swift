import Foundation
import SwiftData

/// One record per reviewed day: stores the end-of-day reflection and a snapshot of the
/// planned/completed counts. Its existence also marks "already reviewed today", so the
/// auto-prompt fires at most once per day.
@Model
public final class DayLog {
    @Attribute(.unique) public var id: UUID = UUID()
    /// Normalized start-of-day.
    public var day: Date = Date.now
    public var reflection: String = ""
    public var plannedCount: Int = 0
    public var completedCount: Int = 0

    public init(id: UUID = UUID(), day: Date, reflection: String = "", plannedCount: Int = 0, completedCount: Int = 0) {
        self.id = id
        self.day = day
        self.reflection = reflection
        self.plannedCount = plannedCount
        self.completedCount = completedCount
    }
}
