import SwiftUI

/// Settings › Calendar: connect Google/Outlook calendars and control the
/// "starts in 1 minute" meeting reminder.
///
/// The one settings tab that reaches outside Wikily's local-first design —
/// see `Tech Spec Wikily.md` §6 — so it's also the one tab that has to explain
/// itself: what leaves the machine (calendar metadata and an OAuth token, to
/// Google or Microsoft directly), what doesn't (call audio, the transcript,
/// anything the wiki matcher sees), and that it's entirely opt-in.
@MainActor
struct CalendarSettingsView: View {

    @Bindable var settings: AppSettings
    @Bindable var accountStore: CalendarAccountStore
    var syncCoordinator: CalendarSyncCoordinator

    @State private var notificationStatus: NotificationPermission.Status = .notDetermined
    @State private var isRequestingNotificationPermission = false

    init(
        settings: AppSettings,
        accountStore: CalendarAccountStore = .shared,
        syncCoordinator: CalendarSyncCoordinator = .shared
    ) {
        self.settings = settings
        self.accountStore = accountStore
        self.syncCoordinator = syncCoordinator
    }

    var body: some View {
        SettingsPane {
            Section {
                Toggle("Notify me 1 minute before meetings start", isOn: remindersBinding)

                LabeledContent("Notifications") {
                    StatusIndicator(level: notificationLevel, text: notificationText)
                }

                switch notificationStatus {
                case .granted:
                    EmptyView()
                case .notDetermined:
                    Button("Allow Notifications…") { requestNotificationPermission() }
                        .disabled(isRequestingNotificationPermission)
                case .denied:
                    Button("Open Notification Settings…") { NotificationPermission.openSystemSettings() }
                }
            } header: {
                Text("Meeting Reminders")
            } footer: {
                SettingsFootnote(
                    "When a connected calendar's meeting has a Zoom, Google Meet, Teams or "
                        + "Webex link, Wikily reminds you one minute before it starts. Tapping "
                        + "the reminder opens the link and brings Wikily's HUD to the front."
                )
            }

            Section {
                if accountStore.accounts.isEmpty {
                    Text("No calendars connected.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(accountStore.accounts) { account in
                        LabeledContent {
                            Button("Disconnect") { accountStore.disconnect(account) }
                        } label: {
                            Label(account.email, systemImage: account.provider.symbol)
                        }
                    }
                }
            } header: {
                Text("Connected Calendars")
            }

            Section {
                connectRow(.google)
                connectRow(.outlook)

                if let error = accountStore.connectionError {
                    StatusIndicator(level: .problem, text: error)
                }
            } header: {
                Text("Connect a Calendar")
            } footer: {
                SettingsFootnote(
                    "Connecting needs an OAuth client ID for each provider — see "
                        + "docs/CALENDAR_INTEGRATION.md in the Wikily repository for how to "
                        + "create one for free in a few minutes. The id isn't secret and can be "
                        + "shared across a team's own builds of Wikily."
                )
            }

            Section("Advanced") {
                DisclosureGroup("OAuth Client IDs") {
                    TextField("Google Client ID", text: $settings.googleCalendarClientID)
                        .textFieldStyle(.roundedBorder)
                    TextField("Outlook Client ID", text: $settings.outlookCalendarClientID)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if !syncCoordinator.upcomingEvents.isEmpty {
                Section("Upcoming") {
                    ForEach(syncCoordinator.upcomingEvents.prefix(5)) { event in
                        LabeledContent {
                            if event.joinURL != nil {
                                Image(systemName: "video.fill").foregroundStyle(.secondary)
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(event.title)
                                Text(event.startDate, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .task {
            notificationStatus = await NotificationPermission.status()
        }
    }

    /// Requesting notification permission the moment reminders are switched
    /// on, rather than only the first time one would actually fire — the
    /// toggle *is* the moment the user asked for this, so that's when Wikily
    /// should ask the system for the ability to deliver it.
    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { settings.meetingRemindersEnabled },
            set: { newValue in
                settings.meetingRemindersEnabled = newValue
                if newValue { requestNotificationPermissionIfNeeded() }
            }
        )
    }

    @ViewBuilder
    private func connectRow(_ provider: CalendarProvider) -> some View {
        HStack {
            Button("Connect \(provider.displayName)") {
                Task {
                    await accountStore.connect(provider)
                    if settings.meetingRemindersEnabled { requestNotificationPermissionIfNeeded() }
                }
            }
            .disabled(!accountStore.isConfigured(provider) || accountStore.isConnecting)

            if accountStore.isConnecting {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func requestNotificationPermissionIfNeeded() {
        guard notificationStatus == .notDetermined else { return }
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        isRequestingNotificationPermission = true
        Task {
            _ = await NotificationPermission.request()
            notificationStatus = await NotificationPermission.status()
            isRequestingNotificationPermission = false
        }
    }

    private var notificationLevel: StatusIndicator.Level {
        switch notificationStatus {
        case .granted: .ok
        case .notDetermined: .warning
        case .denied: .problem
        }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .granted: "Allowed"
        case .notDetermined: "Not requested yet."
        case .denied: "Denied. Wikily can't remind you until you re-enable it."
        }
    }
}
