import Foundation
import Testing
@testable import Wikily

/// Exercises `OutlookCalendarClient.parseEvents`/`parseEmail` against
/// captured-shape Microsoft Graph payloads, with nothing listening — same
/// reasoning as `GoogleCalendarClientTests`.
struct OutlookCalendarClientTests {

    private let accountID = UUID()

    @Test func skipsCancelledEvents() throws {
        let payload = Data("""
            {"value": [
              {"id": "e-cancelled", "subject": "Gone", "isCancelled": true,
               "start": {"dateTime": "2026-08-05T17:00:00.0000000"},
               "end": {"dateTime": "2026-08-05T17:30:00.0000000"}}
            ]}
            """.utf8)
        #expect(try OutlookCalendarClient.parseEvents(payload, accountID: accountID).isEmpty)
    }

    @Test func extractsTheStructuredOnlineMeetingLink() throws {
        let payload = Data("""
            {"value": [
              {"id": "e1", "subject": "Standup", "isAllDay": false, "isCancelled": false,
               "start": {"dateTime": "2026-08-05T17:00:00.0000000"},
               "end": {"dateTime": "2026-08-05T17:30:00.0000000"},
               "onlineMeeting": {"joinUrl": "https://teams.microsoft.com/l/meetup-join/19%3aabc/0"}}
            ]}
            """.utf8)
        let events = try OutlookCalendarClient.parseEvents(payload, accountID: accountID)
        let event = try #require(events.first)
        #expect(event.title == "Standup")
        #expect(event.provider == .outlook)
        #expect(event.accountID == accountID)
        #expect(event.joinURL?.absoluteString == "https://teams.microsoft.com/l/meetup-join/19%3aabc/0")
    }

    @Test func fallsBackToTheLocationFieldWhenThereIsNoStructuredLink() throws {
        let payload = Data("""
            {"value": [
              {"id": "e2", "subject": "Zoom Sync", "isAllDay": false,
               "start": {"dateTime": "2026-08-05T17:00:00.0000000"},
               "end": {"dateTime": "2026-08-05T17:30:00.0000000"},
               "location": {"displayName": "https://acme.zoom.us/j/1234567890"}}
            ]}
            """.utf8)
        let events = try OutlookCalendarClient.parseEvents(payload, accountID: accountID)
        #expect(events.first?.joinURL?.absoluteString == "https://acme.zoom.us/j/1234567890")
    }

    @Test func missingSubjectFallsBackToAPlaceholderRatherThanBeingDropped() throws {
        let payload = Data("""
            {"value": [
              {"id": "e3", "isAllDay": true,
               "start": {"dateTime": "2026-08-06T00:00:00.0000000"},
               "end": {"dateTime": "2026-08-07T00:00:00.0000000"}}
            ]}
            """.utf8)
        let events = try OutlookCalendarClient.parseEvents(payload, accountID: accountID)
        let event = try #require(events.first)
        #expect(event.title == "(No title)")
        #expect(event.isAllDay)
    }

    @Test func eventsWithUnparseableStartTimesAreDropped() throws {
        let payload = Data("""
            {"value": [
              {"id": "e4", "subject": "Broken", "start": {"dateTime": "garbage"},
               "end": {"dateTime": "2026-08-05T17:30:00.0000000"}}
            ]}
            """.utf8)
        #expect(try OutlookCalendarClient.parseEvents(payload, accountID: accountID).isEmpty)
    }

    @Test func malformedBodyThrows() {
        #expect(throws: (any Error).self) {
            try OutlookCalendarClient.parseEvents(Data("not json".utf8), accountID: accountID)
        }
    }

    // MARK: - Email resolution

    @Test func prefersMailOverUserPrincipalName() throws {
        let payload = Data(#"{"mail": "person@example.com", "userPrincipalName": "upn@example.com"}"#.utf8)
        #expect(try OutlookCalendarClient.parseEmail(payload) == "person@example.com")
    }

    @Test func fallsBackToUserPrincipalNameWhenMailIsMissing() throws {
        let payload = Data(#"{"userPrincipalName": "upn@example.com"}"#.utf8)
        #expect(try OutlookCalendarClient.parseEmail(payload) == "upn@example.com")
    }

    @Test func throwsWhenNeitherFieldIsPresent() {
        #expect(throws: (any Error).self) {
            try OutlookCalendarClient.parseEmail(Data("{}".utf8))
        }
    }
}
