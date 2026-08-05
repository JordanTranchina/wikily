import Foundation

/// Finds a join-a-call URL inside whatever text a calendar event carries it in.
///
/// Google and Outlook both surface a *structured* conferencing link when the
/// event was created with their own "Add video call" button
/// (`conferenceData`/`onlineMeeting`), and the provider clients read that field
/// first, before ever calling this. This exists for everything else: a Zoom
/// link pasted into the location field, a Google Meet URL buried three
/// paragraphs into the description — the shape organizers actually use as
/// often as the structured field, especially for Zoom, which neither provider
/// surfaces structurally at all.
enum MeetingLinkExtractor {

    /// Order doesn't affect which service wins within one text — the regexes
    /// are disjoint — but scanning `texts` in the caller's given order does:
    /// the first text that contains *any* match wins over a later text that
    /// might contain a different one, so callers pass their most authoritative
    /// field first.
    private static let patterns: [String] = [
        #"https?://[\w-]+\.?zoom\.us/j/\S+"#,
        #"https?://meet\.google\.com/\S+"#,
        #"https?://teams\.microsoft\.com/l/meetup-join/\S+"#,
        #"https?://teams\.live\.com/meet/\S+"#,
        #"https?://[\w-]+\.?webex\.com/\S+"#,
    ]

    /// - Parameter texts: searched in order until one yields a match — pass
    ///   the structured conferencing field first, then location, then
    ///   description, so a real conferencing link always wins over one merely
    ///   mentioned in the agenda.
    static func joinURL(in texts: [String?]) -> URL? {
        for text in texts {
            guard let text, !text.isEmpty, let url = firstMatch(in: text) else { continue }
            return url
        }
        return nil
    }

    private static func firstMatch(in text: String) -> URL? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let matchRange = Range(match.range, in: text)
            else { continue }

            var raw = String(text[matchRange])
            // Trailing punctuation swept up by the greedy `\S+` when the link
            // ends a sentence or sits inside parentheses/quotes — "join here:
            // https://zoom.us/j/123)." shouldn't hand back a trailing ")."
            while let last = raw.last, ".,;:)]>\"'".contains(last) {
                raw.removeLast()
            }
            if let url = URL(string: raw) { return url }
        }
        return nil
    }
}
