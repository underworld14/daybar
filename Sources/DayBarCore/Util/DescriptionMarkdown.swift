import Foundation

/// Prepares task-note text for markdown rendering.
public enum DescriptionMarkdown {
    /// Wraps bare URLs in `<...>` so cmark autolinks them. URLs already inside
    /// a markdown link `](...)` or an existing `<...>` autolink are untouched.
    /// Replacement runs back-to-front so earlier ranges stay valid.
    public static func autolinked(_ text: String) -> String {
        let urls = NotesLinkDetector.urls(in: text)
        guard !urls.isEmpty else { return text }

        var spans: [Range<String.Index>] = []
        for url in urls {
            guard let range = text.range(of: url.absoluteString) else { continue }
            let precededByLinkTarget = range.lowerBound > text.startIndex
                && text[text.index(before: range.lowerBound)] == "("
            let precededByAutolinkOpen = range.lowerBound > text.startIndex
                && text[text.index(before: range.lowerBound)] == "<"
            if precededByLinkTarget || precededByAutolinkOpen { continue }
            spans.append(range)
        }
        guard !spans.isEmpty else { return text }

        var result = text
        for range in spans.reversed() {
            result.replaceSubrange(range, with: "<\(text[range])>")
        }
        return result
    }
}
