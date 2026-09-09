import Foundation

/// Formatting and parsing of durations in the "1h 30m" style.
enum WorkDuration {
    /// 90 -> "1h 30m", 60 -> "1h", 45 -> "45m", 0 -> "0m"
    static func format(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : ""
        let total = abs(minutes)
        let hours = total / 60
        let rest = total % 60
        if hours > 0 && rest > 0 { return "\(sign)\(hours)h \(rest)m" }
        if hours > 0 { return "\(sign)\(hours)h" }
        return "\(sign)\(rest)m"
    }

    /// Hours with one decimal, e.g. 8.5h -> "8.5h", 8h -> "8h"
    static func formatHours(_ minutes: Int) -> String {
        let hours = Double(minutes) / 60
        if hours == hours.rounded() { return "\(Int(hours))h" }
        return String(format: "%.1fh", hours)
    }

    /// Accepts "1h 30m", "1h30m", "1h", "45m", "1:30", "90" (minutes), "1.5h", "1,5h", "1 30" (h m).
    static func parse(_ input: String) -> Int? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return nil }

        if text.contains(":") {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let h = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                  let m = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                  m >= 0, m < 60 else { return nil }
            return h * 60 + m
        }

        let pattern = #"(\d+(?:[.,]\d+)?)\s*(hod|hours?|hrs?|h|minutes?|mins?|m)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return nil }

        // Everything that is not a match must be whitespace.
        var consumed = ""
        for m in matches { consumed += ns.substring(with: m.range) }
        let leftovers = text.replacingOccurrences(of: " ", with: "")
        if consumed.replacingOccurrences(of: " ", with: "") != leftovers { return nil }

        var minutes = 0.0
        for (index, m) in matches.enumerated() {
            let numberText = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")
            guard let value = Double(numberText) else { return nil }
            let unit = m.range(at: 2).location == NSNotFound ? "" : ns.substring(with: m.range(at: 2))
            if unit.hasPrefix("h") {
                minutes += value * 60
            } else if unit.hasPrefix("m") {
                minutes += value
            } else if matches.count == 1 {
                minutes += value            // bare number -> minutes
            } else if index == 0 {
                minutes += value * 60       // "1 30" -> 1h 30m
            } else {
                minutes += value
            }
        }
        return Int(minutes.rounded())
    }
}
