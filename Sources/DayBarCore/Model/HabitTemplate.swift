import Foundation
import SwiftData

/// Recurring habit definition. A new `HabitLog` is materialized each calendar day by `HabitEngine`.
@Model
public final class HabitTemplate {
    @Attribute(.unique) public var id: UUID = UUID()
    public var title: String = ""
    public var cueText: String = ""
    public var symbolName: String = "circle"
    public var sortOrder: Int = 0
    public var isActive: Bool = true
    public var createdDate: Date = Date.now
    /// Optional anchor hour (0–23). `anchorMinute` is ignored when nil.
    public var anchorHour: Int? = nil
    public var anchorMinute: Int? = nil
    public var notifyEnabled: Bool = false

    public init(
        id: UUID = UUID(),
        title: String = "",
        cueText: String = "",
        symbolName: String = "circle",
        sortOrder: Int = 0,
        isActive: Bool = true,
        createdDate: Date = .now,
        anchorHour: Int? = nil,
        anchorMinute: Int? = nil,
        notifyEnabled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.cueText = cueText
        self.symbolName = symbolName
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.createdDate = createdDate
        self.anchorHour = anchorHour
        self.anchorMinute = anchorMinute
        self.notifyEnabled = notifyEnabled
    }
}

extension HabitTemplate: Identifiable {}