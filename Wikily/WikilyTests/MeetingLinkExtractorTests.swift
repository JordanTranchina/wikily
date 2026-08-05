import Foundation
import Testing
@testable import Wikily

struct MeetingLinkExtractorTests {

    @Test func findsAZoomLinkInLocation() {
        let url = MeetingLinkExtractor.joinURL(in: [nil, "https://acme.zoom.us/j/1234567890", nil])
        #expect(url?.absoluteString == "https://acme.zoom.us/j/1234567890")
    }

    @Test func findsAGoogleMeetLinkInDescription() {
        let url = MeetingLinkExtractor.joinURL(in: [
            nil, nil, "Agenda:\n1. Standup\n\nJoin: https://meet.google.com/abc-defg-hij",
        ])
        #expect(url?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func findsATeamsLinkAmongOtherText() {
        let url = MeetingLinkExtractor.joinURL(in: [
            "Click here to join: https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0",
        ])
        #expect(url?.absoluteString == "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc/0")
    }

    @Test func findsAWebexLink() {
        let url = MeetingLinkExtractor.joinURL(in: ["https://acme.webex.com/acme/j.php?MTID=abc123"])
        #expect(url?.absoluteString == "https://acme.webex.com/acme/j.php?MTID=abc123")
    }

    @Test func earlierTextsWinOverLaterOnes() {
        // A structured conferencing field ranks above a description that
        // merely mentions a different service — see `joinURL(in:)`'s ordering
        // contract.
        let url = MeetingLinkExtractor.joinURL(in: [
            "https://meet.google.com/real-link",
            "In case that fails, try https://acme.zoom.us/j/999",
        ])
        #expect(url?.absoluteString == "https://meet.google.com/real-link")
    }

    @Test func stripsTrailingPunctuationSweptUpByTheGreedyMatch() {
        let url = MeetingLinkExtractor.joinURL(in: [
            "Join the call (https://meet.google.com/abc-defg-hij).",
        ])
        #expect(url?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test func returnsNilWhenNothingLooksLikeAJoinLink() {
        let url = MeetingLinkExtractor.joinURL(in: [nil, "", "Conference Room B, 3rd floor"])
        #expect(url == nil)
    }

    @Test func ignoresPlainTextMentionsOfAServiceWithNoURL() {
        let url = MeetingLinkExtractor.joinURL(in: ["We'll do this over Zoom, link to follow."])
        #expect(url == nil)
    }
}
