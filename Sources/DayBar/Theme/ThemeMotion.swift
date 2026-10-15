import AppKit
import SwiftUI

/// Named animations. Each collapses to `nil` (instant) under Reduce Motion.
enum ThemeMotion {
    enum Token {
        case snap, reorder, lift, columnMove, reveal
    }

    static func animation(_ token: Token, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        switch token {
        case .snap: return .snappy(duration: 0.22)
        case .reorder: return .spring(response: 0.32, dampingFraction: 0.86)
        case .lift: return .spring(response: 0.22, dampingFraction: 0.7)
        case .columnMove: return .smooth(duration: 0.32)
        case .reveal: return .easeOut(duration: 0.16)
        }
    }

    /// Reduce Motion as AppKit reports it — for call sites outside a view's environment.
    static var systemReduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// `withAnimation` honoring Reduce Motion, for intents fired from buttons and key presses.
func withThemeAnimation<Result>(_ token: ThemeMotion.Token, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(ThemeMotion.animation(token, reduceMotion: ThemeMotion.systemReduceMotion), body)
}

private struct ThemeAnimationModifier<Value: Equatable>: ViewModifier {
    let token: ThemeMotion.Token
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(ThemeMotion.animation(token, reduceMotion: reduceMotion), value: value)
    }
}

extension View {
    /// `.animation(_:value:)` with a theme token that respects Reduce Motion.
    func themeAnimation<Value: Equatable>(_ token: ThemeMotion.Token, value: Value) -> some View {
        modifier(ThemeAnimationModifier(token: token, value: value))
    }
}
