import Foundation
import Testing
@testable import Wikily

struct CalendarDateParsingTests {

    // MARK: - RFC3339 (Google)

    @Test func parsesATimestampWithATimezoneOffset() throws {
        let date = try #require(RFC3339DateParsing.date(from: "2026-08-05T17:00:00-07:00"))
        #expect(date.timeIntervalSince1970 == 1_785_974_400)
    }

    @Test func parsesAZuluTimestamp() throws {
        let date = try #require(RFC3339DateParsing.date(from: "2026-08-05T17:00:00Z"))
        #expect(date.timeIntervalSince1970 == 1_785_949_200)
    }

    @Test func parsesATimestampWithFractionalSeconds() throws {
        let date = try #require(RFC3339DateParsing.date(from: "2026-08-05T17:00:00.500Z"))
        #expect(date.timeIntervalSince1970 == 1_785_949_200.5)
    }

    @Test func rejectsGarbage() {
        #expect(RFC3339DateParsing.date(from: "not a date") == nil)
    }

    // MARK: - Graph `dateTimeTimeZone`

    @Test func parsesGraphsSevenDigitFractionalSeconds() throws {
        // The shape Graph actually sends: no offset, seven fractional digits,
        // meaningful only alongside a `timeZone` field Wikily always forces
        // to UTC — see `OutlookCalendarClient.fetchUpcomingEvents`.
        let date = try #require(GraphDateTimeParsing.date(from: "2026-08-05T17:00:00.0000000"))
        #expect(date.timeIntervalSince1970 == 1_785_949_200)
    }

    @Test func parsesGraphTimestampsWithNoFractionalSeconds() throws {
        let date = try #require(GraphDateTimeParsing.date(from: "2026-08-05T17:00:00"))
        #expect(date.timeIntervalSince1970 == 1_785_949_200)
    }

    @Test func truncatesRatherThanRoundsExtraFractionalDigits() throws {
        // .0009999 truncates to .000 (millisecond precision), not .001 — the
        // parser slices rather than rounds.
        let date = try #require(GraphDateTimeParsing.date(from: "2026-08-05T17:00:00.0009999"))
        #expect(date.timeIntervalSince1970 == 1_785_949_200)
    }

    @Test func padsShortFractionalDigits() throws {
        let date = try #require(GraphDateTimeParsing.date(from: "2026-08-05T17:00:00.5"))
        #expect(date.timeIntervalSince1970 == 1_785_949_200.5)
    }
}
