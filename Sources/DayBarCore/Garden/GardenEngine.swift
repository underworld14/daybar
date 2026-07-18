import Foundation

/// Pure projection of focus sessions + garden meta into a snapshot. Mutates `GardenMeta` in place.
public enum GardenEngine {
    public static let coinPerSession = 1
    public static let harvestBonusCoins = 2
    public static let maxHarvestLogEntries = 30
    public static let maxRewardFeedEntries = 8

    /// What a single unit of focus energy did to the garden this settle.
    enum EnergyOutcome {
        case harvested(String)
        case grew(String)
        case planted(String)
        case none
    }

    @discardableResult
    public static func settle(
        meta: GardenMeta,
        sessions: [FocusSession],
        asOf now: Date = .now,
        calendar: Calendar = .current,
        mode: GardenActionMode = .automatic
    ) -> GardenSnapshot {
        let today = calendar.startOfDay(for: now)
        var slots = meta.slots
        var animals = meta.animals
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
            var harvestedCount = 0
            var lastHarvested: String?
            var lastPlanted: String?
            var lastGrew: String?
            var newlyReady: [OwnedAnimal] = []
            for _ in 0..<newEnergy {
                switch applyOneEnergy(slots: &slots, meta: meta, unlocks: unlocks, today: today, mode: mode) {
                case .harvested(let crop):
                    harvestedCount += 1
                    lastHarvested = crop
                    justHarvested = crop
                    recordHarvest(meta: meta, cropID: crop, day: today)
                    meta.coins += harvestBonusCoins
                case .planted(let crop):
                    lastPlanted = crop
                case .grew(let crop):
                    lastGrew = crop
                case .none:
                    break
                }
                // Each unit of focus energy also feeds the animals (mode-agnostic, no coins here).
                advanceAnimals(&animals, newlyReady: &newlyReady)
            }
            meta.coins += newEnergy * coinPerSession
            meta.lifetimeCompletedSessions = completedCount

            // One durable reward entry summarizing the batch (verb precedence: harvested > planted > grew).
            let coinDelta = newEnergy * coinPerSession + harvestedCount * harvestBonusCoins
            let verb: (GardenRewardEntry.Kind, String)?
            if let c = lastHarvested { verb = (.harvested, c) }
            else if let c = lastPlanted { verb = (.planted, c) }
            else if let c = lastGrew { verb = (.grew, c) }
            else { verb = nil }
            let text = sessionRewardText(coinDelta: coinDelta, verb: verb)
            prependReward(
                meta: meta,
                date: now,
                text: text,
                coinDelta: coinDelta,
                kind: verb?.0 ?? .coin,
                cropID: verb?.1
            )

            // A separate, coin-free entry when animals become collectable (batched to avoid feed flooding).
            if !newlyReady.isEmpty {
                meta.animals = animals   // persist the fresh timers before the ready-entry reads them
                let readyText: String
                if newlyReady.count == 1 {
                    let k = newlyReady[0].kind
                    readyText = "\(k.displayName) has \(k.productName.lowercased()) ready"
                } else {
                    readyText = "\(newlyReady.count) animals have products ready"
                }
                prependReward(meta: meta, date: now, text: readyText, coinDelta: 0, kind: .animalReady, cropID: nil)
            }
        }

        let season = GardenSeason.from(month: calendar.component(.month, from: now))
        meta.season = season
        meta.slots = slots
        meta.animals = animals
        meta.unlockedItemIDs = unlocks
        meta.lastSettledDay = today

        return makeSnapshot(
            meta: meta,
            slots: slots,
            unlocks: unlocks,
            season: season,
            sessions: sessions,
            justHarvested: justHarvested,
            today: today,
            now: now,
            calendar: calendar
        )
    }

    // MARK: - Manual actions (pure)

    /// Manually harvest a mature plot: clears it, awards the harvest bonus, logs it, and returns a reward entry.
    /// Returns `nil` (no-op, no mutation) if the index is out of range or the slot isn't mature.
    /// Never touches `lifetimeCompletedSessions`/`lastSettledDay` — `settle` owns those.
    @discardableResult
    public static func harvest(
        meta: GardenMeta,
        slotIndex idx: Int,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> GardenRewardEntry? {
        var slots = meta.slots
        guard slots.indices.contains(idx), slots[idx].isMature else { return nil }
        let today = calendar.startOfDay(for: now)
        let crop = slots[idx].cropID ?? GardenCatalog.defaultCropID
        slots[idx] = GardenPlotSlot(index: slots[idx].index)
        meta.slots = slots
        meta.coins += harvestBonusCoins
        recordHarvest(meta: meta, cropID: crop, day: today)
        let text = "Harvested \(GardenCatalog.displayName(for: crop)) · +\(harvestBonusCoins) coins"
        return prependReward(meta: meta, date: now, text: text, coinDelta: harvestBonusCoins, kind: .harvested, cropID: crop)
    }

    /// Manually plant an empty plot with the next rotation crop. No coin cost. Returns a reward entry,
    /// or `nil` (no-op) if the index is out of range or the slot isn't empty.
    @discardableResult
    public static func plant(
        meta: GardenMeta,
        slotIndex idx: Int,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> GardenRewardEntry? {
        var slots = meta.slots
        guard slots.indices.contains(idx), slots[idx].isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        let crop = GardenCatalog.nextCropID(after: meta.lastPlantedCropID, unlocked: meta.unlockedItemIDs)
        slots[idx].cropID = crop
        slots[idx].stage = 1
        slots[idx].plantedOn = today
        slots[idx].lastGrownOn = today
        slots[idx].wiltLevel = 0
        meta.slots = slots
        meta.lastPlantedCropID = crop
        let text = "Planted \(GardenCatalog.displayName(for: crop))"
        return prependReward(meta: meta, date: now, text: text, coinDelta: 0, kind: .planted, cropID: crop)
    }

    /// Collect the product from a ready animal: awards coins, resets its timer, returns a reward entry.
    /// Returns `nil` (no-op, no mutation) if the animal is unknown or has no product yet.
    /// Never touches `lifetimeCompletedSessions`/`lastSettledDay` — collecting is not new focus energy.
    @discardableResult
    public static func collectFromAnimal(
        meta: GardenMeta,
        animalID: UUID,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> GardenRewardEntry? {
        var animals = meta.animals
        guard let idx = animals.firstIndex(where: { $0.id == animalID }), animals[idx].hasProduct else {
            return nil
        }
        let kind = animals[idx].kind
        animals[idx].energyUntilReady = kind.productionEnergy   // reset — must be focus-fed again
        meta.animals = animals
        meta.coins += kind.collectValue
        let text = "Collected \(kind.productName) · +\(kind.collectValue) coins"
        return prependReward(meta: meta, date: now, text: text, coinDelta: kind.collectValue, kind: .collected, cropID: nil)
    }

    // MARK: - Growth

    /// Feeds one unit of focus energy to every not-yet-ready animal. Any animal that crosses to ready
    /// this step is appended to `newlyReady` (for a single batched reward entry). No coins here —
    /// coins are only awarded on collect, keeping "focus is the only fuel" structurally true.
    private static func advanceAnimals(_ animals: inout [OwnedAnimal], newlyReady: inout [OwnedAnimal]) {
        for i in animals.indices where animals[i].energyUntilReady > 0 {
            animals[i].energyUntilReady -= 1
            if animals[i].energyUntilReady <= 0 {
                newlyReady.append(animals[i])
            }
        }
    }

    /// Applies one unit of focus energy and reports what it did.
    /// In `.manual` mode the harvest and plant steps are skipped (crops still grow; wilt still recovers),
    /// leaving mature crops ready and empty plots open for the player.
    private static func applyOneEnergy(
        slots: inout [GardenPlotSlot],
        meta: GardenMeta,
        unlocks: [String],
        today: Date,
        mode: GardenActionMode
    ) -> EnergyOutcome {
        // Recover wilt on all planted slots.
        for i in slots.indices where !slots[i].isEmpty {
            slots[i].wiltLevel = max(0, slots[i].wiltLevel - 1)
        }

        // Harvest mature first (leftmost) — automatic mode only.
        if mode == .automatic, let idx = slots.firstIndex(where: { $0.isMature }) {
            let crop = slots[idx].cropID ?? GardenCatalog.defaultCropID
            slots[idx] = GardenPlotSlot(index: slots[idx].index)
            return .harvested(crop)
        }

        // Grow leftmost non-mature planted slot.
        if let idx = slots.firstIndex(where: { !$0.isEmpty && !$0.isMature }) {
            let bonus = seasonalBonusSteps(slot: slots[idx], season: meta.season)
            slots[idx].stage = min(GardenCatalog.maxStage, slots[idx].stage + 1 + bonus)
            slots[idx].lastGrownOn = today
            return .grew(slots[idx].cropID ?? GardenCatalog.defaultCropID)
        }

        // Plant in first empty slot — automatic mode only.
        if mode == .automatic, let idx = slots.firstIndex(where: \.isEmpty) {
            let crop = GardenCatalog.nextCropID(after: meta.lastPlantedCropID, unlocked: unlocks)
            slots[idx].cropID = crop
            slots[idx].stage = 1
            slots[idx].plantedOn = today
            slots[idx].lastGrownOn = today
            slots[idx].wiltLevel = 0
            meta.lastPlantedCropID = crop
            return .planted(crop)
        }
        return .none
    }

    private static func seasonalBonusSteps(slot: GardenPlotSlot, season: GardenSeason) -> Int {
        guard let crop = slot.cropID, season.favoredCropIDs.contains(crop) else { return 0 }
        return 1
    }

    // MARK: - Snapshot

    private static func makeSnapshot(
        meta: GardenMeta,
        slots: [GardenPlotSlot],
        unlocks: [String],
        season: GardenSeason,
        sessions: [FocusSession],
        justHarvested: String?,
        today: Date,
        now: Date,
        calendar: Calendar
    ) -> GardenSnapshot {
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
            hasScarf: unlocks.contains(GardenCatalog.itemScarf),
            recentRewards: meta.recentRewards,
            animals: meta.animals.map {
                AnimalSnapshot(
                    id: $0.id,
                    kind: $0.kind,
                    cell: $0.cell,
                    hasProduct: $0.hasProduct,
                    energyUntilReady: $0.energyUntilReady
                )
            }
        )
    }

    // MARK: - Reward feed

    private static func sessionRewardText(coinDelta: Int, verb: (GardenRewardEntry.Kind, String)?) -> String {
        var text = "Focus complete · +\(coinDelta) \(coinDelta == 1 ? "coin" : "coins")"
        if let (kind, cropID) = verb {
            let name = GardenCatalog.displayName(for: cropID)
            switch kind {
            case .harvested: text += " · \(name) harvested"
            case .planted: text += " · \(name) planted"
            case .grew: text += " · \(name) grew"
            case .coin, .animalReady, .collected: break
            }
        }
        return text
    }

    @discardableResult
    private static func prependReward(
        meta: GardenMeta,
        date: Date,
        text: String,
        coinDelta: Int,
        kind: GardenRewardEntry.Kind,
        cropID: String?
    ) -> GardenRewardEntry {
        var feed = meta.recentRewards
        let seq = (feed.first?.seq ?? 0) + 1
        let entry = GardenRewardEntry(seq: seq, date: date, text: text, coinDelta: coinDelta, kind: kind, cropID: cropID)
        feed.insert(entry, at: 0)
        if feed.count > maxRewardFeedEntries {
            feed = Array(feed.prefix(maxRewardFeedEntries))
        }
        meta.recentRewards = feed
        return entry
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
