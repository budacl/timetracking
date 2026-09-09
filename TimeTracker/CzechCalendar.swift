import Foundation

/// Working-day arithmetic that respects Czech public holidays.
enum CzechCalendar {
    static let hoursPerDay = 8

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "cs_CZ")
        return c
    }

    // MARK: Holidays

    /// Meeus/Jones/Butcher Gregorian algorithm.
    static func easterSunday(year: Int) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// Public holidays (státní svátky + ostatní svátky) for a year, keyed by start of day.
    static func holidays(year: Int) -> [Date: String] {
        let cal = calendar
        func day(_ month: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day))!
        }
        var result: [Date: String] = [
            day(1, 1): "Den obnovy samostatného českého státu / Nový rok",
            day(5, 1): "Svátek práce",
            day(5, 8): "Den vítězství",
            day(7, 5): "Den slovanských věrozvěstů Cyrila a Metoděje",
            day(7, 6): "Den upálení mistra Jana Husa",
            day(9, 28): "Den české státnosti",
            day(10, 28): "Den vzniku samostatného československého státu",
            day(11, 17): "Den boje za svobodu a demokracii",
            day(12, 24): "Štědrý den",
            day(12, 25): "1. svátek vánoční",
            day(12, 26): "2. svátek vánoční",
        ]
        let easter = easterSunday(year: year)
        if year >= 2016, let goodFriday = cal.date(byAdding: .day, value: -2, to: easter) {
            result[goodFriday] = "Velký pátek"
        }
        if let easterMonday = cal.date(byAdding: .day, value: 1, to: easter) {
            result[easterMonday] = "Velikonoční pondělí"
        }
        return result
    }

    static func holidayName(on date: Date) -> String? {
        let cal = calendar
        let start = cal.startOfDay(for: date)
        return holidays(year: cal.component(.year, from: start))[start]
    }

    static func isWeekend(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    static func isWorkingDay(_ date: Date) -> Bool {
        !isWeekend(date) && holidayName(on: date) == nil
    }

    // MARK: Ranges

    static func monthInterval(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)!
    }

    /// All days of the month containing `date`.
    static func days(inMonthOf date: Date) -> [Date] {
        let cal = calendar
        let interval = monthInterval(containing: date)
        var days: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            days.append(cursor)
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return days
    }

    static func workingDays(inMonthOf date: Date) -> Int {
        days(inMonthOf: date).filter(isWorkingDay).count
    }

    /// Working days from the 1st of the month up to and including `date`.
    static func workingDays(inMonthOf date: Date, through end: Date) -> Int {
        let endDay = calendar.startOfDay(for: end)
        return days(inMonthOf: date).filter { $0 <= endDay && isWorkingDay($0) }.count
    }

    /// The next `count` working days starting with `date` (inclusive).
    static func nextWorkingDays(from date: Date, count: Int) -> [Date] {
        let cal = calendar
        var result: [Date] = []
        var cursor = cal.startOfDay(for: date)
        while result.count < count {
            if isWorkingDay(cursor) { result.append(cursor) }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor)!
        }
        return result
    }

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
