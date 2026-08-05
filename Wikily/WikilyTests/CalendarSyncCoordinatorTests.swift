import Foundation
import Testing
@testable import Wikily

@MainActor
struct CalendarSyncCoordinatorTests {

    private let accountID1 = UUID()
    private let accountID2 = UUID()

    private func event(id: String, accountID: UUID, minutesFromNow: Double) -> CalendarEvent {
        CalendarEvent(
            providerEventID: id,
            accountID: accountID,
            provider: .google,
            title: "Event \(id)",
            startDate: Date().addingTimeInterval(minutesFromNow * 60),
            endDate: Date().addingTimeInterval(minutesFromNow * 60 + 1800),
            isAllDay: false,
            joinURL: nil
        )
    }

    // MARK: - `merged(_:)`

    @Test func mergedSortsByStartTime() {
        let early = event(id: "a", accountID: accountID1, minutesFromNow: 30)
        let late = event(id: "b", accountID: accountID1, minutesFromNow: 60)
        let merged = CalendarSyncCoordinator.merged([late, early])
        #expect(merged.map(\.providerEventID) == ["a", "b"])
    }

    @Test func mergedDedupesTheSameEventFromTheSameAccount() {
        let first = event(id: "same", accountID: accountID1, minutesFromNow: 10)
        let duplicate = event(id: "same", accountID: accountID1, minutesFromNow: 10)
        let merged = CalendarSyncCoordinator.merged([first, duplicate])
        #expect(merged.count == 1)
    }

    @Test func mergedKeepsTheSameProviderEventSeenThroughTwoAccounts() {
        // A shared calendar both connected accounts can see is two distinct
        // reminders, not a duplicate — they're different `CalendarEvent.id`s
        // because the id is namespaced by account.
        let seenByFirstAccount = event(id: "shared", accountID: accountID1, minutesFromNow: 10)
        let seenBySecondAccount = event(id: "shared", accountID: accountID2, minutesFromNow: 10)
        let merged = CalendarSyncCoordinator.merged([seenByFirstAccount, seenBySecondAccount])
        #expect(merged.count == 2)
    }

    // MARK: - `refresh()`

    private func makeSettings() -> AppSettings {
        let name = "com.wikily.Wikily.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return AppSettings(defaults: defaults, launchAtLogin: .inert)
    }

    @Test func refreshPublishesEventsFromEveryConnectedAccount() async throws {
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
        let account = try #require(accountStore.accounts.first)

        client.fetchUpcomingEventsResult = .success([
            event(id: "e1", accountID: account.id, minutesFromNow: 15),
        ])

        let coordinator = CalendarSyncCoordinator(accountStore: accountStore)
        await coordinator.refresh()

        #expect(coordinator.upcomingEvents.map(\.providerEventID) == ["e1"])
        #expect(coordinator.lastSyncError == nil)
    }

    @Test func refreshWithNoConnectedAccountsClearsAnyPreviousEvents() async {
        let settings = makeSettings()
        let accountStore = CalendarAccountStore(
            settings: settings,
            tokenStore: InMemoryCalendarTokenStore(),
            browser: FakeOAuthBrowserSession(),
            clients: [:]
        )
        let coordinator = CalendarSyncCoordinator(accountStore: accountStore)

        await coordinator.refresh()

        #expect(coordinator.upcomingEvents.isEmpty)
    }

    @Test func oneAccountFailingDoesNotDiscardAnotherAccountsEvents() async throws {
        let settings = makeSettings()
        settings.googleCalendarClientID = "client-id"
        settings.outlookCalendarClientID = "client-id"
        let googleClient = FakeCalendarProviderClient(provider: .google)
        let outlookClient = FakeCalendarProviderClient(provider: .outlook)
        let accountStore = CalendarAccountStore(
            settings: settings,
            tokenStore: InMemoryCalendarTokenStore(),
            browser: FakeOAuthBrowserSession(),
            clients: [.google: googleClient, .outlook: outlookClient]
        )
        await accountStore.connect(.google)
        await accountStore.connect(.outlook)

        let outlookAccount = try #require(accountStore.accounts.first { $0.provider == .outlook })

        googleClient.fetchUpcomingEventsResult = .failure(CalendarOAuthError.notConnected)
        outlookClient.fetchUpcomingEventsResult = .success([
            event(id: "ok", accountID: outlookAccount.id, minutesFromNow: 20),
        ])

        let coordinator = CalendarSyncCoordinator(accountStore: accountStore)
        await coordinator.refresh()

        #expect(coordinator.upcomingEvents.map(\.providerEventID) == ["ok"])
        #expect(coordinator.lastSyncError != nil)
    }
}
