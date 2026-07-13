import Foundation

/// Keyword → mood mapping used as fallback when AI confidence is low or classification fails.
public enum MoodKeywordHeuristic: Sendable {
    public static func classify(_ text: String) -> MoodTag? {
        let lowered = text.lowercased()
        // Order matters: more specific / stronger negatives before weaker ones.
        let rules: [(MoodTag, [String])] = [
            (.stressed, ["stress", "stres", "tertekan", "overwhelmed", "burnout"]),
            (.anxious, ["cemas", "khawatir", "anxious", "worried", "panic", "galau"]),
            (.disappointed, [
                "sedih", "kecewa", "murung", "nangis", "menangis", "miserable",
                "disappointed", "heartbroken", "down", "sad",
            ]),
            (.tired, ["lelah", "capek", "exhausted", "tired", "sleepy", "ngantuk"]),
            (.lovestruck, ["jatuh cinta", "lovestruck", "in love", "kasmaran"]),
            (.proud, ["bangga", "proud"]),
            (.productive, ["produktif", "productive", "got a lot done"]),
            (.social, ["bareng teman", "hang out", "party", "social"]),
            (.happy, ["senang", "seneng", "bahagia", "gembira", "happy", "glad", "joyful"]),
            (.busyMeetings, ["rapat terus", "back to back", "meetings all day"]),
        ]
        for (tag, keywords) in rules {
            if keywords.contains(where: { lowered.contains($0) }) {
                return tag
            }
        }
        return nil
    }
}
