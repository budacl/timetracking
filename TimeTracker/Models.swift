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

/// Everything persisted to disk.
struct PersistedState: Codable {
    var tickets: [Ticket] = []
    var log: [LogEntry] = []
    var baseURL: String = "https://youtrack.livesport.eu"
    var workTypeName: String = "Development"
    var notificationHour: Int = 16
    var notificationMinute: Int = 0
    var lastAutoReviewDay: String?
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
