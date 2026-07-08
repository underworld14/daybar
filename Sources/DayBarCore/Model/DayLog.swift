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
    public var moodTagRaw: String? = nil
    public var moodSourceRaw: String = MoodSource.none.rawValue

    public init(
        id: UUID = UUID(),
        day: Date,
        reflection: String = "",
        plannedCount: Int = 0,
        completedCount: Int = 0,
        moodTag: MoodTag? = nil,
        moodSource: MoodSource = .none
    ) {
        self.id = id
        self.day = day
        self.reflection = reflection
        self.plannedCount = plannedCount
        self.completedCount = completedCount
        self.moodTagRaw = moodTag?.rawValue
        self.moodSourceRaw = moodSource.rawValue
    }
}

public extension DayLog {
    /// Not AI-generated — looked up from `MoodTag.score`, so the same tag always
    /// aggregates identically whether it came from classification or a manual tap.
    var moodTag: MoodTag? {
        get { moodTagRaw.flatMap(MoodTag.init(rawValue:)) }
        set { moodTagRaw = newValue?.rawValue }
    }

    var moodSource: MoodSource {
        get { MoodSource(rawValue: moodSourceRaw) ?? .none }
        set { moodSourceRaw = newValue.rawValue }
    }

    var moodScore: Int? { moodTag?.score }
}
