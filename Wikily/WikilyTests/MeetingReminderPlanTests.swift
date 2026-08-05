import Foundation
import Testing
@testable import Wikily

struct MeetingReminderPlanTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func firesExactlyOneMinuteBeforeStartByDefault() {
        let start = now.addingTimeInterval(600)
        let fireDate = MeetingReminderPlan.fireDate(eventStart: start, now: now)
        #expect(fireDate == start.addingTimeInterval(-60))
    }

    @Test func respectsACustomLeadTime() {
        let start = now.addingTimeInterval(600)
        let fireDate = MeetingReminderPlan.fireDate(eventStart: start, now: now, leadTime: 300)
        #expect(fireDate == start.addingTimeInterval(-300))
    }

    /// The reminder moment already passed but the meeting hasn't started —
    /// Wikily launching, or a calendar reconnecting, thirty seconds before a
    /// call. A late reminder beats none.
    @Test func firesAlmostImmediatelyWhenTheLeadWindowAlreadyPassed() {
        let start = now.addingTimeInterval(30)
        #expect(MeetingReminderPlan.fireDate(eventStart: start, now: now) == now.addingTimeInterval(1))
    }

    @Test func returnsNilOnceTheMeetingHasAlreadyStarted() {
        let start = now.addingTimeInterval(-30)
        #expect(MeetingReminderPlan.fireDate(eventStart: start, now: now) == nil)
    }

    @Test func returnsNilAtTheExactStartMoment() {
        #expect(MeetingReminderPlan.fireDate(eventStart: now, now: now) == nil)
    }
}
