import Foundation

/// Pure projection of focus sessions + garden meta into a snapshot. Mutates `GardenMeta` in place.
public enum GardenEngine {
    public static let coinPerSession = 1
    public static let harvestBonusCoins = 2
    public static let maxHarvestLogEntries = 30

    @discardableResult
    public static func settle(
        meta: GardenMeta,
        sessions: [FocusSession],
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> GardenSnapshot {
        let today = calendar.startOfDay(for: now)
        var slots = meta.slots
        var justHarvested: String?
        var unlocks = meta.unlockedItemIDs

        ensureSlotCount(&slots, unlocks: unlocks)

        // 1) Soft wilt for each unsettled past day through yesterday.
        applyWiltForUnsettledDays(
            slots: &slots,
            sessions: sessions,
            lastSettled: meta.lastSettledDay,
            today: today,
            calendar: calendar
        )

        // 2) Apply new completed-session energy.
        let completedCount = sessions.filter(\.completed).count
        let newEnergy = max(0, completedCount - meta.lifetimeCompletedSessions)
        if newEnergy > 0 {
            var energy = newEnergy
            while energy > 0 {
                let harvested = applyOneEnergy(
                    slots: &slots,
                    meta: meta,
                    unlocks: unlocks,
                    today: today,
                    calendar: calendar
                )
                if let crop = harvested {
                    justHarvested = crop
                    recordHarvest(meta: meta, cropID: crop, day: today)
                    meta.coins += harvestBonusCoins
                }
                energy -= 1
            }
            meta.coins += newEnergy * coinPerSession
            meta.lifetimeCompletedSessions = completedCount
        }

        let season = GardenSeason.from(month: calendar.component(.month, from: now))
        meta.season = season
        meta.slots = slots
        meta.unlockedItemIDs = unlocks
        meta.lastSettledDay = today

        let streak = FocusAnalytics.streakInfo(sessions: sessions, asOf: now, calendar: calendar)
        let todayCompleted = sessions.filter {
            $0.completed && calendar.isDate($0.endedAt, inSameDayAs: today)
        }.count
        let weather: GardenWeather = todayCompleted >= 2 ? .rain : .clear
        let mood = companionMood(slots: slots, todayCompleted: todayCompleted)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let harvestThisWeek = meta.harvestLog
            .filter { $0.day >= weekStart && $0.day <= today }
            .reduce(0) { $0 + $1.count }

        return GardenSnapshot(
            slots: slots,
            companionMood: mood,
            season: season,
            coins: meta.coins,
            currentStreak: streak.current,
            graceRemaining: streak.graceRemaining,
            weather: weather,
            unlockedItemIDs: unlocks,
            harvestThisWeek: harvestThisWeek,
            justHarvestedCropID: justHarvested,
            hasFence: unlocks.contains(GardenCatalog.itemFence),
            hasScarf: unlocks.contains(GardenCatalog.itemScarf)
        )
    }

    // MARK: - Growth

    /// Returns harvested crop ID if this energy harvested a mature plant.
    private static func applyOneEnergy(
        slots: inout [GardenPlotSlot],
        meta: GardenMeta,
        unlocks: [String],
        today: Date,
        calendar: Calendar
    ) -> String? {
        // Recover wilt on all planted slots.
        for i in slots.indices where !slots[i].isEmpty {
            slots[i].wiltLevel = max(0, slots[i].wiltLevel - 1)
        }

        // Harvest mature first (leftmost).
        if let idx = slots.firstIndex(where: { $0.isMature }) {
            let crop = slots[idx].cropID ?? GardenCatalog.defaultCropID
            slots[idx] = GardenPlotSlot(index: slots[idx].index)
            return crop
        }

        // Grow leftmost non-mature planted slot.
        if let idx = slots.firstIndex(where: { !$0.isEmpty && !$0.isMature }) {
            let bonus = seasonalBonusSteps(slot: slots[idx], season: meta.season)
            slots[idx].stage = min(GardenCatalog.maxStage, slots[idx].stage + 1 + bonus)
            slots[idx].lastGrownOn = today
            return nil
        }

        // Plant in first empty slot.
        if let idx = slots.firstIndex(where: \.isEmpty) {
            let crop = GardenCatalog.nextCropID(after: meta.lastPlantedCropID, unlocked: unlocks)
            slots[idx].cropID = crop
            slots[idx].stage = 1
            slots[idx].plantedOn = today
            slots[idx].lastGrownOn = today
            slots[idx].wiltLevel = 0
            meta.lastPlantedCropID = crop
        }
        return nil
    }

    private static func seasonalBonusSteps(slot: GardenPlotSlot, season: GardenSeason) -> Int {
        guard let crop = slot.cropID, season.favoredCropIDs.contains(crop) else { return 0 }
        return 1
    }

    // MARK: - Wilt

    private static func applyWiltForUnsettledDays(
        slots: inout [GardenPlotSlot],
        sessions: [FocusSession],
        lastSettled: Date?,
        today: Date,
        calendar: Calendar
    ) {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return }
        let start: Date
        if let last = lastSettled {
            let lastDay = calendar.startOfDay(for: last)
            if lastDay >= today { return } // already settled today
            start = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? yesterday
        } else {
            // First settle: only evaluate yesterday (no historical punishment).
            start = calendar.startOfDay(for: yesterday)
        }

        var day = calendar.startOfDay(for: start)
        let end = calendar.startOfDay(for: yesterday)
        guard day <= end else { return }

        while day <= end {
            if shouldWilt(on: day, sessions: sessions, today: today, calendar: calendar) {
                for i in slots.indices where !slots[i].isEmpty {
                    slots[i].wiltLevel = min(2, slots[i].wiltLevel + 1)
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
    }

    /// Empty day that is not covered by focus grace → soft wilt.
    private static func shouldWilt(
        on day: Date,
        sessions: [FocusSession],
        today: Date,
        calendar: Calendar
    ) -> Bool {
        let cells = FocusAnalytics.weekStrip(
            sessions: sessions,
            days: FocusAnalytics.defaultWeekDays,
            endingAt: today,
            calendar: calendar
        )
        // If the day is outside the strip window, compute completed count directly + grace via strip ending at that day.
        if let cell = cells.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) {
            return cell.completedSessions == 0 && !cell.usedGrace
        }
        let dayCells = FocusAnalytics.weekStrip(
            sessions: sessions,
            days: FocusAnalytics.defaultWeekDays,
            endingAt: day,
            calendar: calendar
        )
        guard let cell = dayCells.last else {
            let count = sessions.filter { $0.completed && calendar.isDate($0.endedAt, inSameDayAs: day) }.count
            return count == 0
        }
        return cell.completedSessions == 0 && !cell.usedGrace
    }

    // MARK: - Helpers

    private static func companionMood(slots: [GardenPlotSlot], todayCompleted: Int) -> CompanionMood {
        if todayCompleted > 0 { return .happy }
        if slots.contains(where: { $0.wiltLevel >= 1 }) { return .wilted }
        return .idle
    }

    private static func ensureSlotCount(_ slots: inout [GardenPlotSlot], unlocks: [String]) {
        let target = unlocks.contains(GardenCatalog.itemExtraSlot)
            ? GardenCatalog.maxSlotCount
            : GardenCatalog.defaultSlotCount
        while slots.count < target {
            slots.append(GardenPlotSlot(index: slots.count))
        }
        if slots.count > target {
            slots = Array(slots.prefix(target))
        }
        for i in slots.indices {
            slots[i].index = i
        }
    }

    private static func recordHarvest(meta: GardenMeta, cropID: String, day: Date) {
        var log = meta.harvestLog
        if let idx = log.firstIndex(where: { $0.day == day && $0.cropID == cropID }) {
            log[idx].count += 1
        } else {
            log.insert(GardenHarvestEntry(day: day, cropID: cropID), at: 0)
        }
        if log.count > maxHarvestLogEntries {
            log = Array(log.prefix(maxHarvestLogEntries))
        }
        meta.harvestLog = log
    }
}
