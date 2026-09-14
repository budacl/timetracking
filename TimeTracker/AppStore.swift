import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class AppStore {
    static let shared = AppStore()

    // MARK: Persisted state

    var tickets: [Ticket] { didSet { save() } }
    var log: [LogEntry] { didSet { save() } }
    var vacations: [Vacation] { didSet { save(); rescheduleNotifications() } }
    var baseURL: String { didSet { save() } }
    var workTypeName: String { didSet { save(); workTypeCache.removeAll() } }
    var notificationHour: Int { didSet { save(); rescheduleNotifications() } }
    var notificationMinute: Int { didSet { save(); rescheduleNotifications() } }
    private(set) var lastAutoReviewDay: String? { didSet { save() } }

    /// Stored in the Keychain, never in the JSON file.
    var token: String { didSet { Keychain.writeToken(token) } }

    // MARK: Transient state

    var now = Date()
    var showReview = false
    /// Date the pending records are logged to; the review sheet resets it to today when it opens.
    var reviewDate = Date()
    var isSubmitting = false
    var isSyncing = false
    var errorMessage: String?
    var infoMessage: String?
    var submitError: String?
    var notificationsAuthorized: Bool?
    var lastSync: Date?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var loading = true
    @ObservationIgnored private var workTypeCache: [String: [YouTrackClient.WorkItemType]] = [:]

    init() {
        let state = Self.loadState()
        tickets = state.tickets
        log = state.log
        vacations = state.vacations
        baseURL = state.baseURL
        workTypeName = state.workTypeName
        notificationHour = state.notificationHour
        notificationMinute = state.notificationMinute
        lastAutoReviewDay = state.lastAutoReviewDay
        token = Keychain.readToken() ?? ""
        loading = false
    }

    // MARK: Dashboard numbers

    var monthInterval: DateInterval { CzechCalendar.monthInterval(containing: now) }

    /// Minutes already logged to YouTrack this month.
    var trackedThisMonthMinutes: Int {
        log.filter { monthInterval.contains($0.date) }.map(\.minutes).reduce(0, +)
    }

    /// Minutes added to tickets today but not yet confirmed/logged.
    var pendingMinutes: Int { tickets.map(\.minutes).reduce(0, +) }

    // MARK: Working days (calendar minus vacations)

    func isOnVacation(_ date: Date) -> Bool {
        vacations.contains { $0.contains(date) }
    }

    /// A day you are expected to log time on: weekday, not a Czech holiday, not on vacation.
    func isWorkDay(_ date: Date) -> Bool {
        CzechCalendar.isWorkingDay(date) && !isOnVacation(date)
    }

    /// Non-isolated snapshot of `isWorkDay` for use off the main actor (notification scheduling).
    private var workDayPredicate: @Sendable (Date) -> Bool {
        let vacations = self.vacations
        return { date in CzechCalendar.isWorkingDay(date) && !vacations.contains { $0.contains(date) } }
    }

    /// Working days (weekday, not holiday) inside a vacation period.
    func workingDays(in vacation: Vacation) -> Int {
        let cal = CzechCalendar.calendar
        var count = 0
        var cursor = cal.startOfDay(for: vacation.start)
        let end = cal.startOfDay(for: vacation.end)
        while cursor <= end {
            if CzechCalendar.isWorkingDay(cursor) { count += 1 }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return count
    }

    var workingDaysThisMonth: Int { CzechCalendar.days(inMonthOf: now).filter(isWorkDay).count }
    var workingHoursThisMonth: Int { workingDaysThisMonth * CzechCalendar.hoursPerDay }

    /// Vacation days this month that would otherwise have been working days.
    var vacationDaysThisMonth: Int {
        CzechCalendar.days(inMonthOf: now).filter { CzechCalendar.isWorkingDay($0) && isOnVacation($0) }.count
    }

    var workingDaysUntilToday: Int {
        let today = CzechCalendar.calendar.startOfDay(for: now)
        return CzechCalendar.days(inMonthOf: now).filter { $0 <= today && isWorkDay($0) }.count
    }
    var expectedMinutesUntilToday: Int { workingDaysUntilToday * CzechCalendar.hoursPerDay * 60 }

    /// (logged + pending) − expected. Positive means ahead of plan.
    var balanceMinutes: Int { trackedThisMonthMinutes + pendingMinutes - expectedMinutesUntilToday }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        notificationsAuthorized = await NotificationScheduler.requestAuthorization()
        await NotificationScheduler.reschedule(hour: notificationHour, minute: notificationMinute, isWorkDay: workDayPredicate)
        tick()
        if !token.isEmpty {
            await syncMonthFromYouTrack(silent: true)
        }
    }

    /// Called periodically: refreshes `now` and opens the review sheet once the daily review time has passed.
    func tick() {
        now = Date()
        let todayKey = CzechCalendar.dayKey(now)
        guard isWorkDay(now), lastAutoReviewDay != todayKey else { return }
        let comps = CzechCalendar.calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        if nowMinutes >= notificationHour * 60 + notificationMinute {
            lastAutoReviewDay = todayKey
            showReview = true
        }
    }

    func rescheduleNotifications() {
        guard !loading else { return }
        let predicate = workDayPredicate
        Task { await NotificationScheduler.reschedule(hour: notificationHour, minute: notificationMinute, isWorkDay: predicate) }
    }

    // MARK: Vacations

    /// Adds a period; overlapping periods are allowed and simply counted once per day.
    func addVacation(from start: Date, to end: Date, note: String) {
        let cal = CzechCalendar.calendar
        let s = cal.startOfDay(for: min(start, end))
        let e = cal.startOfDay(for: max(start, end))
        vacations.append(Vacation(start: s, end: e, note: note.trimmingCharacters(in: .whitespaces)))
        vacations.sort { $0.start > $1.start }
    }

    func removeVacation(_ id: Vacation.ID) {
        vacations.removeAll { $0.id == id }
    }

    // MARK: Tickets

    func addTicket(issueId raw: String, title: String) async {
        guard let issueId = IssueIdParser.extract(from: raw) else {
            errorMessage = "“\(raw)” does not look like a ticket ID (expected something like MOB-1234)."
            return
        }
        if tickets.contains(where: { $0.issueId == issueId }) {
            infoMessage = "\(issueId) is already in the list."
            return
        }
        let ticket = Ticket(issueId: issueId, title: title.trimmingCharacters(in: .whitespaces))
        tickets.append(ticket)
        if ticket.title.isEmpty {
            await refreshTitle(for: ticket.id)
        }
    }

    func refreshTitle(for id: Ticket.ID) async {
        guard let index = tickets.firstIndex(where: { $0.id == id }) else { return }
        let issueId = tickets[index].issueId
        guard let client = makeClient(reportErrors: false) else { return }
        do {
            let issue = try await client.issue(issueId)
            if let i = tickets.firstIndex(where: { $0.id == id }) {
                tickets[i].issueId = issue.idReadable
                tickets[i].title = issue.summary ?? ""
            }
        } catch {
            errorMessage = "Could not load \(issueId) from YouTrack: \(error.localizedDescription)"
        }
    }

    func removeTickets(_ ids: Set<Ticket.ID>) {
        tickets.removeAll { ids.contains($0.id) }
    }

    func setMinutes(_ id: Ticket.ID, _ minutes: Int) {
        guard let i = tickets.firstIndex(where: { $0.id == id }) else { return }
        tickets[i].minutes = max(0, minutes)
    }

    func addMinutes(_ id: Ticket.ID, _ delta: Int) {
        guard let i = tickets.firstIndex(where: { $0.id == id }) else { return }
        tickets[i].minutes = max(0, tickets[i].minutes + delta)
    }

    func setNote(_ id: Ticket.ID, _ note: String) {
        guard let i = tickets.firstIndex(where: { $0.id == id }), tickets[i].note != note else { return }
        tickets[i].note = note
    }

    func openInYouTrack(_ ticket: Ticket) {
        guard let client = YouTrackClient(baseURL: baseURL, token: "x") else { return }
        NSWorkspace.shared.open(client.baseURL.appendingPathComponent("issue/\(ticket.issueId)"))
    }

    // MARK: YouTrack

    private func makeClient(reportErrors: Bool = true) -> YouTrackClient? {
        guard let client = YouTrackClient(baseURL: baseURL, token: token) else {
            if reportErrors { errorMessage = YouTrackClient.ClientError.invalidBaseURL.localizedDescription }
            return nil
        }
        guard !token.isEmpty else {
            if reportErrors { errorMessage = YouTrackClient.ClientError.missingToken.localizedDescription }
            return nil
        }
        return client
    }

    func testConnection() async -> String {
        guard let client = makeClient(reportErrors: false) else {
            return token.isEmpty ? "Enter a token first." : "Invalid server URL."
        }
        do {
            let me = try await client.me()
            return "Connected as \(me.name ?? me.login) (\(me.login))."
        } catch {
            return error.localizedDescription
        }
    }

    /// Logs every ticket with time > 0 as a work item on its YouTrack issue, then clears the time.
    func confirmAndLog() async {
        submitError = nil
        guard let client = makeClient() else {
            submitError = errorMessage
            errorMessage = nil
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let toLog = tickets.filter { $0.minutes > 0 }
        var failures: [String] = []
        var loggedMinutes = 0
        // Noon of the chosen day: unambiguous for YouTrack (which stores a date) and for local month attribution.
        let logDate = CzechCalendar.calendar.date(bySettingHour: 12, minute: 0, second: 0, of: reviewDate) ?? reviewDate

        for ticket in toLog {
            do {
                let typeId = await resolveWorkTypeId(client: client, issueId: ticket.issueId)
                let workItemId = try await client.logWork(
                    issueId: ticket.issueId,
                    minutes: ticket.minutes,
                    date: logDate,
                    text: ticket.note,
                    typeId: typeId
                )
                log.append(LogEntry(issueId: ticket.issueId, title: ticket.title, minutes: ticket.minutes, date: logDate, workItemId: workItemId))
                loggedMinutes += ticket.minutes
                if let i = tickets.firstIndex(where: { $0.id == ticket.id }) {
                    tickets[i].minutes = 0
                    tickets[i].note = ""
                }
            } catch {
                failures.append("\(ticket.issueId): \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            showReview = false
            let dateText = logDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            infoMessage = "Logged \(WorkDuration.format(loggedMinutes)) across \(toLog.count) ticket\(toLog.count == 1 ? "" : "s") to YouTrack for \(dateText)."
        } else {
            submitError = "Some entries were not logged (their time was kept):\n" + failures.joined(separator: "\n")
        }
    }

    /// Finds the work item type id matching `workTypeName` for the issue's project. Nil = let YouTrack decide.
    private func resolveWorkTypeId(client: YouTrackClient, issueId: String) async -> String? {
        let wanted = workTypeName.trimmingCharacters(in: .whitespaces)
        guard !wanted.isEmpty else { return nil }
        guard let issue = try? await client.issue(issueId), let projectId = issue.project?.id else { return nil }
        if workTypeCache[projectId] == nil {
            workTypeCache[projectId] = (try? await client.workItemTypes(projectId: projectId)) ?? []
        }
        return workTypeCache[projectId]?.first { ($0.name ?? "").caseInsensitiveCompare(wanted) == .orderedSame }?.id
    }

    /// Replaces this month's local log with the work items YouTrack has for the current user.
    func syncMonthFromYouTrack(silent: Bool = false) async {
        guard let client = makeClient(reportErrors: !silent) else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let me = try await client.me()
            let interval = monthInterval
            let lastDay = CzechCalendar.calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let items = try await client.workItems(authorId: me.id, from: interval.start, to: lastDay)
            let fetched = items.map { item in
                LogEntry(
                    issueId: item.issue?.idReadable ?? "?",
                    title: item.issue?.summary ?? "",
                    minutes: item.duration?.minutes ?? 0,
                    date: Date(timeIntervalSince1970: (item.date ?? 0) / 1000),
                    workItemId: item.id
                )
            }
            log = log.filter { !interval.contains($0.date) } + fetched
            lastSync = Date()
            if !silent {
                infoMessage = "Synced \(fetched.count) work item\(fetched.count == 1 ? "" : "s") (\(WorkDuration.format(trackedThisMonthMinutes))) from YouTrack."
            }
        } catch {
            if !silent { errorMessage = "Sync failed: \(error.localizedDescription)" }
        }
    }

    // MARK: Persistence

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("TimeTracker", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    private static func loadState() -> PersistedState {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return PersistedState()
        }
        return state
    }

    private func save() {
        guard !loading else { return }
        let state = PersistedState(
            tickets: tickets,
            log: log,
            vacations: vacations,
            baseURL: baseURL,
            workTypeName: workTypeName,
            notificationHour: notificationHour,
            notificationMinute: notificationMinute,
            lastAutoReviewDay: lastAutoReviewDay
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
