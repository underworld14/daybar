# Focus Garden (Garden Dayscape) — Design Spec

> Approved 2026-07-18. Source of truth for Phases 1–5.

## Context

DayBar already has soft focus gamification: Dayscape ink strip, focus streak with one grace day per week, milestones 7/30/100. This feature **replaces** the ink strip with a Stardew-inspired **focus garden** (plot beds + companion) so completed Pomodoros feel like tending a cottage farm — calm, not Duolingo-harsh.

## Locked decisions

| Decision | Choice |
|---|---|
| Role in product | Visual signature (replaces Dayscape strip) |
| Metaphor | Hybrid: 3 plot slots + 1 companion |
| Fuel | Completed focus sessions only (`completed == true`) |
| Miss day | Soft wilt (recover with 1–2 sessions); grace day = no wilt |
| Ink strip | Fully replaced; keep small `Nd` streak pill |
| Art (app) | SwiftUI procedural via `GardenRenderer` |
| Landing | Stardew-cozy revitalization required in Phase 5 |
| Architecture | `GardenEngine` + SwiftData `GardenMeta`; `FocusSession` remains SoT |

## Architecture

```
FocusSession (completed) → AppState → GardenEngine.settle → GardenMeta + GardenSnapshot → GardenDayscapeView
                              ↑
                     FocusAnalytics (streak/grace)
```

- Pure engine, unit-tested in DayBarCore
- Menu-bar panel width 360; garden row ~48–64pt
- Backup: optional `gardenMeta` on `StoreSnapshotDTO` (missing key preserves live garden)

## Economy & growth

- Coins: +1 per completed session (spend in Phase 4 shop)
- Growth: 1 completed session = 1 stage step on leftmost non-mature planted slot; else plant in first empty slot
- Stages: 0 empty → 1 seed → 2 sprout → 3 young → 4 mature
- Harvest (Phase 2+): mature + next growth → clear slot, +2 bonus coins
- Wilt: daily settle — yesterday empty and not grace → `wiltLevel = min(2, wiltLevel+1)`; completed session recovers −1
- Companion: happy (≥1 completed today), wilted (any wilt≥1), else idle
- Season (NH): spring Mar–May, summer Jun–Aug, autumn Sep–Nov, winter Dec–Feb

## Phases

1. Foundation: types, engine, persistence, AppState, replace UI (parsnip only; coins accrue; shop skeleton fields)
2. Crops: catalog rotation, harvest, weather (rain if ≥2 sessions today)
3. Seasons: in-season +1 bonus energy; harvest log; seasonal palette
4. Shop: seed packs 5c, fence 8c, scarf 12c, 4th slot 20c
5. Polish: motion, SFX, living landing page, README

## Out of scope

Habit/todo fuel, SpriteKit, cloud, real Stardew IP, WebGL landing, autoplay music.
