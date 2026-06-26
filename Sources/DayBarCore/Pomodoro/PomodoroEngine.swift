import Foundation
import Observation

public enum PomodoroPhase: String, Sendable {
    case idle
    case work
    case shortBreak
    case longBreak

    public var isBreak: Bool { self == .shortBreak || self == .longBreak }

    public var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .work: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }
}

public struct PomodoroConfig: Sendable, Equatable {
    public var workDuration: TimeInterval
    public var shortBreakDuration: TimeInterval
    public var longBreakDuration: TimeInterval
    public var cyclesBeforeLongBreak: Int
    public var autoStartNext: Bool

    public init(
        workDuration: TimeInterval = 25 * 60,
        shortBreakDuration: TimeInterval = 5 * 60,
        longBreakDuration: TimeInterval = 15 * 60,
        cyclesBeforeLongBreak: Int = 4,
        autoStartNext: Bool = false
    ) {
        self.workDuration = workDuration
        self.shortBreakDuration = shortBreakDuration
        self.longBreakDuration = longBreakDuration
        self.cyclesBeforeLongBreak = cyclesBeforeLongBreak
        self.autoStartNext = autoStartNext
    }
}

/// Wall-clock Pomodoro timer. The stored `endDate` is the single source of truth, so the
/// countdown stays correct across sleep/wake; the 1-second timer only triggers a redraw.
/// Drive `tick()` on wake to fire any phase transition missed while asleep.
@MainActor
@Observable
public final class PomodoroEngine {
    public private(set) var phase: PomodoroPhase = .idle
    public private(set) var endDate: Date?
    public private(set) var remaining: TimeInterval = 0
    public private(set) var completedWorkCount: Int = 0
    public var config: PomodoroConfig

    /// Fired when a phase ends: `(finishedPhase, elapsedSeconds, completedNaturally)`.
    public var onPhaseEnd: ((PomodoroPhase, TimeInterval, Bool) -> Void)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activityToken: (any NSObjectProtocol)?

    public init(config: PomodoroConfig = .init()) {
        self.config = config
    }

    public var isRunning: Bool { endDate != nil }

    public var remainingString: String {
        let total = max(0, Int(remaining.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Coarse minutes for the (closed) menu-bar label — avoids a per-second status redraw.
    public var remainingMinutesCoarse: Int { max(0, Int((remaining / 60).rounded(.up))) }

    public func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .work: return config.workDuration
        case .shortBreak: return config.shortBreakDuration
        case .longBreak: return config.longBreakDuration
        case .idle: return 0
        }
    }

    // MARK: - Controls

    public func start(_ newPhase: PomodoroPhase, now: Date = .now) {
        guard newPhase != .idle else { return }
        phase = newPhase
        let dur = duration(for: newPhase)
        endDate = now.addingTimeInterval(dur)
        remaining = dur
        beginActivityIfNeeded()
        scheduleTimer()
    }

    public func startWork(now: Date = .now) { start(.work, now: now) }

    public func pause(now: Date = .now) {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSince(now))
        endDate = nil
        teardownTimer()
        endActivity()
    }

    public func resume(now: Date = .now) {
        guard endDate == nil, phase != .idle, remaining > 0 else { return }
        endDate = now.addingTimeInterval(remaining)
        beginActivityIfNeeded()
        scheduleTimer()
    }

    public func stop() {
        phase = .idle
        endDate = nil
        remaining = 0
        teardownTimer()
        endActivity()
    }

    /// Skip to the next phase as though the current one just ended.
    public func skip(now: Date = .now) {
        guard phase != .idle else { return }
        handlePhaseEnd(now: now, naturally: false)
    }

    /// Recompute remaining from the wall-clock `endDate`; fire the transition if elapsed.
    /// Call on every timer tick and on wake-from-sleep.
    public func tick(now: Date = .now) {
        guard let end = endDate else { return }
        let rem = end.timeIntervalSince(now)
        if rem <= 0 {
            remaining = 0
            handlePhaseEnd(now: now, naturally: true)
        } else {
            remaining = rem
        }
    }

    // MARK: - Internals

    private func nextPhase(after finished: PomodoroPhase) -> PomodoroPhase {
        switch finished {
        case .work:
            let cycles = max(1, config.cyclesBeforeLongBreak)
            return completedWorkCount % cycles == 0 ? .longBreak : .shortBreak
        default:
            return .work
        }
    }

    private func handlePhaseEnd(now: Date, naturally: Bool) {
        let finished = phase
        let remainingAtEnd = naturally ? 0 : max(0, endDate?.timeIntervalSince(now) ?? remaining)
        let elapsed = max(0, duration(for: finished) - remainingAtEnd)
        teardownTimer()
        endActivity()
        if finished == .work { completedWorkCount += 1 }
        onPhaseEnd?(finished, elapsed, naturally)

        let next = nextPhase(after: finished)
        if config.autoStartNext {
            start(next, now: now)
        } else {
            // Armed but not running: UI offers "Start <next>".
            phase = next
            endDate = nil
            remaining = duration(for: next)
        }
    }

    private func scheduleTimer() {
        teardownTimer()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.15
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func teardownTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func beginActivityIfNeeded() {
        guard activityToken == nil else { return }
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "DayBar Pomodoro running"
        )
    }

    private func endActivity() {
        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
    }
}
