import Foundation

/// Natural quick-add: "Send invoice !!! besok #client" → title "Send invoice", high
/// priority, tomorrow, project "Client work".
///
/// - `!` / `!!` / `!!!` → low / medium / high (Apple Reminders' convention).
/// - `today`, `hari ini`, `tomorrow`, `tmr`, `tmrw`, `besok` → planned day.
/// - `#name` → a project, matched ignoring case, spaces, `-` and `_`: exact first, then a
///   unique prefix. Unknown or ambiguous tags stay in the title.
/// - A leading `\` keeps a word literal (`\besok`). Tokens must be whole words; the last
///   one of each kind wins.
public enum QuickAddParser {
    public struct ProjectRef: Sendable {
        public let id: UUID
        public let name: String

        public init(id: UUID, name: String) {
            self.id = id
            self.name = name
        }
    }

    private static let todayWords: Set<String> = ["today"]
    private static let tomorrowWords: Set<String> = ["tomorrow", "tmr", "tmrw", "besok"]

    /// `nil` when nothing but syntax (or whitespace) was typed.
    public static func parse(_ text: String, projects: [ProjectRef] = []) -> QuickAddResult? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var titleWords: [String] = []
        var tokens: [QuickAddToken] = []
        var priority: Priority?
        var day: QuickAddDay?
        var projectID: UUID?

        var index = 0
        while index < words.count {
            let word = words[index]
            let lower = word.lowercased()

            if word.hasPrefix("\\"), word.count > 1 {
                titleWords.append(String(word.dropFirst()))
                index += 1
                continue
            }
            if let level = priorityLevel(word) {
                priority = level
                tokens.append(QuickAddToken(kind: .priority(level), source: word))
            } else if lower == "hari", index + 1 < words.count, words[index + 1].lowercased() == "ini" {
                day = .today
                tokens.append(QuickAddToken(kind: .day(.today), source: "\(word) \(words[index + 1])"))
                index += 2
                continue
            } else if todayWords.contains(lower) {
                day = .today
                tokens.append(QuickAddToken(kind: .day(.today), source: word))
            } else if tomorrowWords.contains(lower) {
                day = .tomorrow
                tokens.append(QuickAddToken(kind: .day(.tomorrow), source: word))
            } else if word.hasPrefix("#"), word.count > 1, let project = matchProject(String(word.dropFirst()), in: projects) {
                projectID = project.id
                tokens.append(QuickAddToken(kind: .project(id: project.id, name: project.name), source: word))
            } else {
                titleWords.append(word)
            }
            index += 1
        }

        let title = titleWords.joined(separator: " ")
        guard !title.isEmpty else { return nil }
        return QuickAddResult(title: title, priority: priority, day: day, projectID: projectID, tokens: tokens)
    }

    private static func priorityLevel(_ word: String) -> Priority? {
        switch word {
        case "!": return .low
        case "!!": return .medium
        case "!!!": return .high
        default: return nil
        }
    }

    private static func normalize(_ name: String) -> String {
        name.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
    }

    private static func matchProject(_ query: String, in projects: [ProjectRef]) -> ProjectRef? {
        let key = normalize(query)
        guard !key.isEmpty else { return nil }
        if let exact = projects.first(where: { normalize($0.name) == key }) { return exact }
        let prefixed = projects.filter { normalize($0.name).hasPrefix(key) }
        return prefixed.count == 1 ? prefixed[0] : nil
    }
}
