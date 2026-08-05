import Foundation
import Testing
import UserNotifications
@testable import Wikily

@MainActor
struct MeetingNotificationSchedulerTests {

    private func makeSettings() -> AppSettings {
        let name = "com.wikily.Wikily.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return AppSettings(defaults: defaults, launchAtLogin: .inert)
    }

    /// A coordinator whose `upcomingEvents` is exactly `events` — driven
    /// through a real `connect()` + `refresh()` round trip against fakes,
    /// since the property itself is deliberately `private(set)`.
    private func makeCoordinator(
        events: [CalendarEvent],
        settings: AppSettings
    ) async throws -> CalendarSyncCoordinator {
        settings.googleCalendarClientID = "client-id"
        let client = FakeCalendarProviderClient(provider: .google)
        let accountStore = CalendarAccountStore(
            settings: settings,
            tokenStore: InMemoryCalendarTokenStore(),
            browser: FakeOAuthBrowserSession(),
            clients: [.google: client, .outlook: FakeCalendarProviderClient(provider: .outlook)]
        )
        await accountStore.connect(.google)
        client.fetchUpcomingEventsResult = .success(events)

        let coordinator = CalendarSyncCoordinator(accountStore: accountStore)
        await coordinator.refresh()
        return coordinator
    }

    private func event(
        id: String = "e1",
        minutesFromNow: Double,
        isAllDay: Bool = false,
        hasJoinURL: Bool = true
    ) -> CalendarEvent {
        CalendarEvent(
            providerEventID: id,
            accountID: UUID(),
            provider: .google,
            title: "Standup",
            startDate: Date().addingTimeInterval(minutesFromNow * 60),
            endDate: Date().addingTimeInterval(minutesFromNow * 60 + 1800),
            isAllDay: isAllDay,
            joinURL: hasJoinURL ? URL(string: "https://meet.google.com/abc-defg-hij") : nil
        )
    }

    @Test func schedulesAReminderForAnUpcomingCallWithAJoinLink() async throws {
        let settings = makeSettings()
        let coordinator = try await makeCoordinator(events: [event(minutesFromNow: 10)], settings: settings)
        let center = FakeNotificationCenter()
        let scheduler = MeetingNotificationScheduler(coordinator: coordinator, settings: settings, center: center)

        scheduler.reconcile()

        #expect(center.pendingRequests.count == 1)
        let request = try #require(center.pendingRequests.values.first)
        #expect(request.content.title.contains("starts in 1 minute"))
    }

    @Test func skipsEventsWithNoJoinLink() async throws {
        let settings = makeSettings()
        let coordinator = try await makeCoordinator(
            events: [event(minutesFromNow: 10, hasJoinURL: false)], settings: settings
        )
        let center = FakeNotificationCenter()
        let scheduler = MeetingNotificationScheduler(coordinator: coordinator, settings: settings, center: center)

        scheduler.reconcile()

        #expect(center.pendingRequests.isEmpty)
    }

    @Test func skipsAllDayEvents() async throws {
        let settings = makeSettings()
        let coordinator = try await makeCoordinator(
            events: [event(minutesFromNow: 10, isAllDay: true)], settings: settings
        )
        let center = FakeNotificationCenter()
        let scheduler = MeetingNotificationScheduler(coordinator: coordinator, settings: settings, center: center)

        scheduler.reconcile()

        #expect(center.pendingRequests.isEmpty)
    }

    @Test func doesNothingWhenRemindersAreTurnedOff() async throws {
        let settings = makeSettings()
        settings.meetingRemindersEnabled = false
        let coordinator = try await makeCoordinator(events: [event(minutesFromNow: 10)], settings: settings)
        let center = FakeNotificationCenter()
        let scheduler = MeetingNotificationScheduler(coordinator: coordinator, settings: settings, center: center)

        scheduler.reconcile()

        #expect(center.pendingRequests.isEmpty)
    }

    @Test func turningRemindersOffCancelsAnAlreadyScheduledOne() async throws {
        let settings = makeSettings()
        let coordinator = try await makeCoordinator(events: [event(minutesFromNow: 10)], settings: settings)
        let center = FakeNotificationCenter()
        let scheduler = MeetingNotificationScheduler(coordinator: coordinator, settings: settings, center: center)
        scheduler.reconcile()
        #expect(center.pendingRequests.count == 1)

        settings.meetingRemindersEnabled = false
        scheduler.reconcile()

        #expect(center.pendingRequests.isEmpty)
    }

    @Test func doesNotDuplicateAnAlreadyScheduledReminder() async throws {
        let settings = makeSettings()
        let coordinator = try await makeCoordinator(events: [event(minutesFromNow: 10)], settings: settings)
        let center = FakeNotificationCenter()
        let scheduler = MeetingNotificationScheduler(coordinator: coordinator, settings: settings, center: center)

        scheduler.reconcile()
        scheduler.reconcile()

        #expect(center.pendingRequests.count == 1)
        #expect(center.removedIdentifiers.isEmpty)
    }

    @Test func cancelsAReminderWhoseEventDisappeared() async throws {
        let settings = makeSettings()
        settings.googleCalendarClientID = "client-id"
        let client = FakeCalendarProviderClient(provider: .google)
        let accountStore = CalendarAccountStore(
            settings: settings,
            tokenStore: InMemoryCalendarTokenStore(),
            browser: FakeOAuthBrowserSession(),
            clients: [.google: client, .outlook: FakeCalendarProviderClient(provider: .outlook)]
        )
        await accountStore.connect(.google)
        let coordinator = CalendarSyncCoordinator(accountStore: accountStore)
        let center = FakeNotificationCenter()
        let scheduler = MeetingNotificationScheduler(coordinator: coordinator, settings: settings, center: center)

        client.fetchUpcomingEventsResult = .success([event(id: "e1", minutesFromNow: 10)])
        await coordinator.refresh()
        scheduler.reconcile()
        #expect(center.pendingRequests.count == 1)

        // The meeting got cancelled — the next refresh no longer returns it.
        client.fetchUpcomingEventsResult = .success([])
        await coordinator.refresh()
        scheduler.reconcile()

        #expect(center.pendingRequests.isEmpty)
    }

    @Test func startRegistersTheJoinActionCategory() async throws {
        let settings = makeSettings()
        let coordinator = try await makeCoordinator(events: [], settings: settings)
        let center = FakeNotificationCenter()
        let scheduler = MeetingNotificationScheduler(coordinator: coordinator, settings: settings, center: center)

        scheduler.start()

        let category = try #require(center.categories.first)
        #expect(category.identifier == MeetingNotificationScheduler.categoryIdentifier)
        #expect(category.actions.map(\.identifier) == [MeetingNotificationScheduler.joinActionIdentifier])
    }
}
