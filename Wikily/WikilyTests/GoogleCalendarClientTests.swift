import Foundation
import Testing
@testable import Wikily

/// Exercises `GoogleCalendarClient.parseEvents` against captured-shape
/// payloads, the same way `LocalServerDiscoveryTests` exercises
/// `LocalServerDiscovery.parseModelList` — with nothing listening.
struct GoogleCalendarClientTests {

    private let accountID = UUID()

    @Test func skipsCancelledEvents() throws {
        let payload = Data("""
            {"items": [
              {"id": "evt-cancelled", "status": "cancelled", "summary": "Gone",
               "start": {"dateTime": "2026-08-05T17:00:00Z"},
               "end": {"dateTime": "2026-08-05T17:30:00Z"}}
            ]}
            """.utf8)
        #expect(try GoogleCalendarClient.parseEvents(payload, accountID: accountID).isEmpty)
    }

    @Test func extractsAZoomLinkFromLocation() throws {
        let payload = Data("""
            {"items": [
              {"id": "evt-1", "status": "confirmed", "summary": "Weekly Sync",
               "start": {"dateTime": "2026-08-05T17:00:00-07:00"},
               "end": {"dateTime": "2026-08-05T17:30:00-07:00"},
               "location": "https://acme.zoom.us/j/1234567890"}
            ]}
            """.utf8)
        let events = try GoogleCalendarClient.parseEvents(payload, accountID: accountID)
        let event = try #require(events.first)
        #expect(event.title == "Weekly Sync")
        #expect(event.isAllDay == false)
        #expect(event.joinURL?.absoluteString == "https://acme.zoom.us/j/1234567890")
        #expect(event.accountID == accountID)
        #expect(event.provider == .google)
    }

    @Test func prefersTheStructuredHangoutLinkOverAMentionInTheDescription() throws {
        let payload = Data("""
            {"items": [
              {"id": "evt-2", "status": "confirmed", "summary": "Google Meet Sync",
               "start": {"dateTime": "2026-08-05T18:00:00Z"},
               "end": {"dateTime": "2026-08-05T18:30:00Z"},
               "hangoutLink": "https://meet.google.com/abc-defg-hij",
               "description": "Backup: https://acme.zoom.us/j/000"}
            ]}
            """.utf8)
        let events = try GoogleCalendarClient.parseEvents(payload, accountID: accountID)
        #expect(events.first?.joinURL?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func aDatelessStartMeansAllDayAndNoTimeToRemindAbout() throws {
        let payload = Data("""
            {"items": [
              {"id": "evt-3", "status": "confirmed", "summary": "Off-site",
               "start": {"date": "2026-08-06"}, "end": {"date": "2026-08-07"}}
            ]}
            """.utf8)
        let events = try GoogleCalendarClient.parseEvents(payload, accountID: accountID)
        let event = try #require(events.first)
        #expect(event.isAllDay)
        #expect(event.joinURL == nil)
    }

    @Test func eventsWithNoTitleAreDropped() throws {
        let payload = Data("""
            {"items": [
              {"id": "evt-4", "status": "confirmed",
               "start": {"dateTime": "2026-08-05T17:00:00Z"},
               "end": {"dateTime": "2026-08-05T17:30:00Z"}}
            ]}
            """.utf8)
        #expect(try GoogleCalendarClient.parseEvents(payload, accountID: accountID).isEmpty)
    }

    @Test func malformedBodyThrows() {
        #expect(throws: (any Error).self) {
            try GoogleCalendarClient.parseEvents(Data("not json".utf8), accountID: accountID)
        }
    }
}
