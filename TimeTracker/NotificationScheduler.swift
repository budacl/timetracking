import Foundation
import UserNotifications

enum NotificationScheduler {
    /// Returns true when notifications are (or become) authorized.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// Schedules one reminder per upcoming working day. `isWorkDay` decides which days count
    /// (weekends, Czech holidays and the user's vacations are skipped).
    static func reschedule(hour: Int, minute: Int, isWorkDay: @Sendable (Date) -> Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let cal = CzechCalendar.calendar
        for day in CzechCalendar.nextDays(from: Date(), count: 20, where: isWorkDay) {
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = hour
            comps.minute = minute
            guard let fireDate = cal.date(from: comps), fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Time to check your time tracking"
            content.body = "Review today's records and confirm to log them to YouTrack."
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: "review-\(CzechCalendar.dayKey(day))", content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
