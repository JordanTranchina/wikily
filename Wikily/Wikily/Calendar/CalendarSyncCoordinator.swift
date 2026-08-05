import Foundation
import OSLog

/// Polls every connected calendar account and publishes the merged upcoming
/// events the reminder scheduler and the Calendar settings tab both read.
///
/// `@MainActor @Observable`, the same shape as `CallSession` — see its header
/// for why: the interesting part (accounts turning into a sorted, deduped
/// event list) can be tested by calling `refresh()` against a fake account
/// store, with no timer and no real network running.
@MainActor
@Observable
final class CalendarSyncCoordinator {

    static let shared = CalendarSyncCoordinator()

    private let logger = Logger(subsystem: "com.wikily.Wikily", category: "CalendarSyncCoordinator")

    private(set) var upcomingEvents: [CalendarEvent] = []
    private(set) var lastSyncError: String?
    private(set) var isSyncing = false

    private let accountStore: CalendarAccountStore
    /// How far ahead to fetch. Two hours is generous against the one-minute
    /// reminder window while staying a cheap request against either API.
    private let lookahead: TimeInterval
    private let refreshInterval: TimeInterval
    private let now: @Sendable () -> Date

    private var refreshTask: Task<Void, Never>?

    init(
        accountStore: CalendarAccountStore = .shared,
        lookahead: TimeInterval = 2 * 60 * 60,
        refreshInterval: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.accountStore = accountStore
        self.lookahead = lookahead
        self.refreshInterval = refreshInterval
        self.now = now
    }

    /// Begin periodic polling. Idempotent — calling it twice doesn't start a
    /// second loop.
    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let interval = self?.refreshInterval else { return }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Fetch once, from every connected account, merged and sorted.
    ///
    /// One account's failure (an expired grant, a network blip) doesn't lose
    /// the others' events — each account is fetched independently, and the
    /// first error is surfaced without discarding whatever else succeeded.
    func refresh() async {
        guard !accountStore.accounts.isEmpty else {
            upcomingEvents = []
            lastSyncError = nil
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        let windowStart = now()
        let windowEnd = windowStart.addingTimeInterval(lookahead)

        var merged: [CalendarEvent] = []
        var firstError: String?
        for account in accountStore.accounts {
            do {
                let events = try await accountStore.fetchEvents(for: account, from: windowStart, to: windowEnd)
                merged.append(contentsOf: events)
            } catch {
                logger.error("""
                    Calendar sync failed for \(account.email, privacy: .private): \
                    \(error.localizedDescription, privacy: .public)
                    """)
                firstError = firstError ?? "Couldn't refresh \(account.email): \(error.localizedDescription)"
            }
        }

        upcomingEvents = Self.merged(merged)
        lastSyncError = firstError
    }

    /// Dedupe — an account reconnected under a new id, or two accounts that
    /// can both see one shared-calendar event, shouldn't double it — and sort
    /// by start time, the order both the reminder scheduler and the Settings
    /// preview want.
    static func merged(_ events: [CalendarEvent]) -> [CalendarEvent] {
        var seen = Set<String>()
        var result: [CalendarEvent] = []
        for event in events.sorted(by: { $0.startDate < $1.startDate }) {
            guard seen.insert(event.id).inserted else { continue }
            result.append(event)
        }
        return result
    }
}
