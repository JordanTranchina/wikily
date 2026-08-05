# Calendar Meeting Reminders

Settings › Calendar lets Wikily connect a Google or Outlook calendar and notify you one minute
before a meeting starts, so you join on time with Wikily already listening. This is the one piece
of Wikily that reaches off the machine on purpose — see [Privacy](#privacy) below — and it is
entirely opt-in: nothing here runs unless you connect an account.

## How it works

1. `CalendarSyncCoordinator` polls every connected account every 60 seconds for events in the next
   two hours (`Wikily/Wikily/Calendar/CalendarSyncCoordinator.swift`).
2. For each event, `MeetingLinkExtractor` looks for a Zoom, Google Meet, Microsoft Teams, or Webex
   join link — first in the provider's own structured conferencing field, then in the location and
   description text (`Wikily/Wikily/Calendar/MeetingLinkExtractor.swift`).
3. An event with a join link and a start time in the future gets a local notification scheduled
   one minute before it starts (`MeetingReminderPlan.fireDate`,
   `Wikily/Wikily/Calendar/MeetingNotificationScheduler.swift`). Tapping it — or its "Join & Open
   Wikily" action — opens the link and brings Wikily's HUD to the front.

All-day events, events with no detected join link, and events on calendars you haven't connected
are never reminded about.

## Setting up your own OAuth client IDs

Wikily has no backend server, so calendar sign-in is a direct, PKCE-only OAuth flow (Authorization
Code + PKCE, no client secret) straight from the app to Google or Microsoft. That means whoever
builds Wikily needs their own OAuth client registration for each provider — the client ID isn't a
secret (Google's and Microsoft's own guidance for installed/public clients says so), so one team
can register it once and share the ID across everyone's build, the same way an open-source CLI
tool ships a public OAuth client ID.

Both registrations use the same redirect URI:

```
wikily://oauth-callback
```

### Google Calendar

1. In [Google Cloud Console](https://console.cloud.google.com/), create or pick a project, then go
   to **APIs & Services › Credentials**.
2. **Create Credentials › OAuth client ID**, application type **Desktop app**.
3. Under **APIs & Services › OAuth consent screen**, add the
   `https://www.googleapis.com/auth/calendar.readonly` and
   `https://www.googleapis.com/auth/userinfo.email` scopes.
4. **APIs & Services › Library**, enable the **Google Calendar API** for the project.
5. Copy the client ID (not the secret — Wikily never sends one) into Settings › Calendar › OAuth
   Client IDs › Google Client ID.

### Outlook / Microsoft 365

1. In the [Azure Portal](https://portal.azure.com/), go to **Microsoft Entra ID › App
   registrations › New registration**.
2. Supported account types: **Accounts in any organizational directory and personal Microsoft
   accounts** (this is what lets both work/school and personal Outlook.com accounts connect).
3. Under **Authentication**, add a **Mobile and desktop applications** platform with the redirect
   URI above, and set **Allow public client flows** to **Yes** (there is no client secret).
4. Under **API permissions**, add the Microsoft Graph delegated permissions `Calendars.Read`,
   `User.Read`, and `offline_access`.
5. Copy the **Application (client) ID** into Settings › Calendar › OAuth Client IDs › Outlook
   Client ID.

Neither registration costs anything, and both take a few minutes.

## Privacy

Everything else about Wikily is local-first with no cloud fallback — see `Tech Spec Wikily.md` §6.
Calendar sync is the deliberate, opt-in exception, and it is scoped narrowly:

- **What leaves the machine:** the OAuth token exchange itself, and calendar event titles, times,
  and locations/descriptions (read-only — Wikily requests `calendar.readonly` /
  `Calendars.Read`, never write access), fetched directly from Google's or Microsoft's own APIs.
- **What doesn't:** call audio, the live transcript, and anything the wiki matcher sees. None of
  that is affected by connecting a calendar, and nothing calendar-related is read by the
  transcription or matching pipeline.
- **Where tokens live:** the system Keychain (`CalendarTokenStoring` /
  `KeychainCalendarTokenStore.swift`), never `UserDefaults` — see that file's header for why.
  Disconnecting an account (Settings › Calendar › Disconnect) deletes its Keychain entry
  immediately.
- **Turning it off:** disconnect every account, or leave "Notify me 1 minute before meetings
  start" switched off — both are ordinary Settings toggles, not app-wide flags that need a
  rebuild.

## Known limitations

- **Not yet exercised against a live Google or Microsoft account.** The OAuth flow, token refresh,
  and event parsing are covered by unit tests against captured-shape payloads (see
  `WikilyTests/{GoogleCalendarClientTests,OutlookCalendarClientTests,CalendarAccountStoreTests}.swift`),
  but nobody has clicked "Connect" against a real account yet. Treat the first real connect as the
  remaining verification step, the same way `docs/NATIVE_REWRITE_ROADMAP.md` tracks other
  hands-on-app checks that unit tests can't stand in for.
- **No recurring-event exceptions beyond what each API already resolves.** Both clients ask for
  already-expanded instances (`singleEvents=true` for Google; Graph's `calendarview` does this by
  construction), so this is really about trusting the provider's own expansion, not a gap in
  Wikily's parsing.
- **A reconnect after revoking access in Google/Microsoft's own account settings** (rather than
  disconnecting inside Wikily) isn't specially handled — the next sync simply fails with an
  auth error surfaced in Settings › Calendar, and reconnecting clears it.
