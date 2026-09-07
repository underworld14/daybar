#if canImport(AppKit)
import AppKit

/// Resolves an effective system appearance to a stable Aqua family appearance.
/// Keeping high-contrast variants in the candidate list preserves accessibility
/// while still producing a deterministic light or dark result.
public enum SystemAppearancePolicy {
    private static let supportedNames: [NSAppearance.Name] = [
        .accessibilityHighContrastDarkAqua,
        .accessibilityHighContrastAqua,
        .darkAqua,
        .aqua,
    ]

    public static func resolvedName(for appearance: NSAppearance) -> NSAppearance.Name {
        resolvedName(fromMatch: appearance.bestMatch(from: supportedNames))
    }

    static func resolvedName(fromMatch name: NSAppearance.Name?) -> NSAppearance.Name {
        guard let name, supportedNames.contains(name) else { return .aqua }
        return name
    }

    public static func resolvedAppearance(for appearance: NSAppearance) -> NSAppearance {
        let name = resolvedName(for: appearance)
        if name == .accessibilityHighContrastAqua
            || name == .accessibilityHighContrastDarkAqua {
            return appearance
        }
        return NSAppearance(named: name) ?? appearance
    }
}
#endif
