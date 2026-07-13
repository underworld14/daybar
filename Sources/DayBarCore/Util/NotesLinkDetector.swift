import Foundation

/// Extracts link URLs from free-form task notes (description).
public enum NotesLinkDetector {
    public static func urls(in string: String) -> [URL] {
        guard !string.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(string.startIndex..., in: string)
        var seen = Set<String>()
        var urls: [URL] = []
        detector.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
            guard let url = match?.url else { return }
            let key = url.absoluteString
            guard seen.insert(key).inserted else { return }
            urls.append(url)
        }
        return urls
    }
}
