import Foundation

/// RFC 3339 timestamps, as Google's Calendar API sends them (e.g.
/// `"2026-08-05T17:00:00-07:00"` or `"...Z"`, with or without fractional
/// seconds).
///
/// `ISO8601DateFormatter` configured for fractional seconds refuses to parse a
/// timestamp that lacks them, and vice versa — Google sends both shapes in
/// practice, so this tries the stricter one first and falls back.
enum RFC3339DateParsing {
    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String) -> Date? {
        withFraction.date(from: string) ?? withoutFraction.date(from: string)
    }
}

/// Microsoft Graph's `dateTimeTimeZone` value — a timestamp with **no**
/// offset, meaningful only alongside a separate `timeZone` field (e.g.
/// `"2026-08-05T17:00:00.0000000"` next to `"timeZone": "UTC"`).
///
/// `OutlookCalendarClient.fetchUpcomingEvents` always requests events with
/// `Prefer: outlook.timezone="UTC"`, so by the time this runs `timeZone` is
/// always `"UTC"` — parsing can treat the string as UTC directly rather than
/// carrying a timezone database lookup through this layer.
enum GraphDateTimeParsing {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return formatter
    }()

    static func date(from dateTime: String) -> Date? {
        formatter.date(from: normalizeFractionalSeconds(dateTime))
    }

    /// Graph's fractional-second digit count isn't contractually fixed (seven
    /// digits in practice, but nothing guarantees that stays true), so this
    /// normalizes to exactly three rather than hard-coding the format string
    /// to match what's been observed.
    private static func normalizeFractionalSeconds(_ raw: String) -> String {
        guard let dotIndex = raw.firstIndex(of: ".") else { return raw + ".000" }
        let wholePart = raw[..<dotIndex]
        let fraction = raw[raw.index(after: dotIndex)...]
        let millis = String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        return "\(wholePart).\(millis)"
    }
}
