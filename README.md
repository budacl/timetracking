# Time Tracker

A small native macOS app (SwiftUI, macOS 14+) for tracking the time you spend on
YouTrack tickets during the day and logging it to YouTrack at the end of the day.

## What it does

**Dashboard (top of the main window)**

| Tile | Meaning |
| --- | --- |
| Tracked this month | Hours already logged to YouTrack this month (+ today's pending time). |
| Working hours this month | Working days in the month × 8 h. Weekends, Czech public holidays (incl. Good Friday and Easter Monday) and your vacation days are excluded. |
| Expected until today | Working days from the 1st through today × 8 h. |
| Ahead / Behind plan | `tracked + pending − expected`. |

**Ticket list**

- `⌘N` (or the `+` toolbar button) adds a ticket by ID or URL (`MOB-1234`). The
  title is fetched from YouTrack.
- The **Time** column is editable. Type `1h 30m`, `1:30`, `90` (minutes) or
  `1.5h`; the `⊕` menu adds 15 m / 30 m / 1 h / 2 h.
- Double-click a row to open the ticket in YouTrack. Right-click for
  *Refresh title* / *Remove*. `⌫` removes the selected rows.

**Daily review**

- At 16:00 (configurable in Settings) on working days a notification reminds you
  to check your time. If the app is running, the review sheet opens by itself.
- The review sheet lists every ticket with time > 0. You can still fix the
  duration and add an optional note per ticket.
- **Confirm & log to YouTrack** creates one work item per ticket (dated today,
  work type "Development" by default), records it locally, and resets the time
  in the list to 0. Tickets stay in the list so you can keep working on them
  tomorrow. If a ticket fails to log, its time is kept and the error is shown.

**Vacations & days off**

- The 🏖 toolbar button opens the vacation list. Add a period (from – to, optional
  note); overlapping periods are fine.
- Vacation days are not working days: they are subtracted from *Working hours
  this month* and *Expected until today*, so being away never shows as
  "behind plan". No 16:00 reminder is scheduled for those days, and the
  dashboard shows "On vacation" while a period is active.

**Sync**

The ↻ toolbar button (and app start) reloads this month's work items for your
user from YouTrack, so the "Tracked this month" number matches YouTrack even if
you logged time elsewhere.

## Install

Run `./install.sh`. It builds a Release version and copies it to
`/Applications/TimeTracker.app`. Re-run it after changing the code. To have the
app running for the 16:00 review, add it to *System Settings → General → Login
Items*.

## Distribute (DMG / zip)

Run `./package.sh`. It builds Release and writes `dist/TimeTracker-<version>.dmg`
(drag the app onto the Applications shortcut inside) and `dist/TimeTracker-<version>.zip`.
Bump `MARKETING_VERSION` in the project to change the version number.

The app is ad-hoc signed, so on **another** Mac Gatekeeper blocks the first launch.
The recipient can right-click the app → *Open*, or go to *System Settings →
Privacy & Security* and click *Open Anyway*. To avoid that dialog you need an
Apple Developer account: set your team in Xcode, sign with a *Developer ID
Application* certificate, and notarize (`xcrun notarytool submit … --wait`, then
`xcrun stapler staple`).

## Setup

1. Open `TimeTracker.xcodeproj` in Xcode and run (⌘R), or install with
   `./install.sh`. The app is signed to run locally; no team is required.
2. Allow notifications when asked.
3. Open Settings (`⌘,`):
   - Server URL: `https://youtrack.livesport.eu` (default)
   - Permanent token: YouTrack → your avatar → *Profile* → *Account Security* →
     *New token…* (scope **YouTrack**). Stored in the macOS Keychain.
   - Work item type: `Development` (default), `Testing`, `Analysis`, `CR`, `Support`
     for the MOB project. Leave empty to let YouTrack pick the default.
   - Click **Test connection**.

## Files

```
TimeTracker/
  TimeTrackerApp.swift      App entry, window, notification delegate (timetracker:// URL scheme)
  AppStore.swift            State, persistence, dashboard math, confirm/sync logic
  ContentView.swift         Dashboard, ticket table, duration field
  Sheets.swift              Add-ticket and Review/Confirm sheets
  SettingsView.swift        Server, token, work type, reminder time
  YouTrackClient.swift      Minimal REST client (issues, work items, users/me)
  CzechCalendar.swift       Czech holidays, working-day arithmetic
  WorkDuration.swift        "1h 30m" formatting and parsing
  NotificationScheduler.swift
  Keychain.swift
  Models.swift
  Assets.xcassets/AppIcon   App icon PNGs (rendered from Design/AppIcon.svg)
Design/AppIcon.svg          Icon source. Re-render with:
                            qlmanage -t -s 1024 -o . Design/AppIcon.svg && sips -z <size> <size> …
```

State is stored in
`~/Library/Containers/com.lukasbudac.TimeTracker/Data/Library/Application Support/TimeTracker/state.json`
(the app is sandboxed). The token lives only in the Keychain.

## Notes

- Closing the window keeps the app running (so the 16:00 review can still pop
  up). Quit with `⌘Q`.
- When the app is not running, the notification is still delivered by macOS;
  clicking it launches the app and opens the review sheet.
