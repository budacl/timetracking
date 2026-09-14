import Foundation

/// A ticket the user is currently working on, with time accumulated today (not yet logged).
struct Ticket: Identifiable, Codable, Hashable {
    var id = UUID()
    var issueId: String          // e.g. "MOB-1234"
    var title: String
    var minutes: Int = 0
    var note: String = ""

    var display: String { title.isEmpty ? issueId : "\(issueId) \(title)" }
}

/// A work item that has been confirmed and logged to YouTrack.
struct LogEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var issueId: String
    var title: String
    var minutes: Int
    var date: Date
    var workItemId: String?
}

/// A vacation / days-off period (inclusive, whole days). Those days are not working days:
/// they reduce the month's expected hours and no review reminder is shown.
struct Vacation: Identifiable, Codable, Hashable {
    var id = UUID()
    var start: Date
    var end: Date
    var note: String = ""

    func contains(_ date: Date) -> Bool {
        let cal = CzechCalendar.calendar
        let day = cal.startOfDay(for: date)
        return day >= cal.startOfDay(for: start) && day <= cal.startOfDay(for: end)
    }
}

/// Everything persisted to disk.
struct PersistedState: Codable {
    var tickets: [Ticket] = []
    var log: [LogEntry] = []
    var vacations: [Vacation] = []
    var baseURL: String = "https://youtrack.livesport.eu"
    var workTypeName: String = "Development"
    var notificationHour: Int = 16
    var notificationMinute: Int = 0
    var lastAutoReviewDay: String?
}

extension PersistedState {
    /// Tolerant decoding: fields added in later versions fall back to their defaults,
    /// so an older state file is never rejected.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PersistedState()
        tickets = try c.decodeIfPresent([Ticket].self, forKey: .tickets) ?? defaults.tickets
        log = try c.decodeIfPresent([LogEntry].self, forKey: .log) ?? defaults.log
        vacations = try c.decodeIfPresent([Vacation].self, forKey: .vacations) ?? defaults.vacations
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL) ?? defaults.baseURL
        workTypeName = try c.decodeIfPresent(String.self, forKey: .workTypeName) ?? defaults.workTypeName
        notificationHour = try c.decodeIfPresent(Int.self, forKey: .notificationHour) ?? defaults.notificationHour
        notificationMinute = try c.decodeIfPresent(Int.self, forKey: .notificationMinute) ?? defaults.notificationMinute
        lastAutoReviewDay = try c.decodeIfPresent(String.self, forKey: .lastAutoReviewDay)
    }
}

enum IssueIdParser {
    /// Extracts "MOB-1234" from plain text or a YouTrack URL.
    static func extract(from text: String) -> String? {
        let pattern = #"([A-Za-z][A-Za-z0-9_]*-\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).uppercased()
    }
}
