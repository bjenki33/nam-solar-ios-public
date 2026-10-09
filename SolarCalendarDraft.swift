import Foundation

// A picker session owns its month and date limit; live readings cannot reset it.
struct SolarCalendarDraft {
    let calendar: Calendar
    let today: Date
    private(set) var selectedDay: Date
    private(set) var visibleMonth: Date

    init(selection: Date, timeZoneID: String, now: Date = Date()) {
        let calendar = SolarEnergyRange.calendar(timeZoneID)
        self.calendar = calendar
        today = calendar.startOfDay(for: now)
        selectedDay = min(calendar.startOfDay(for: selection), today)
        visibleMonth = calendar.dateInterval(of: .month, for: selectedDay)!.start
    }

    var monthTitle: String {
        let parts = calendar.dateComponents([.year, .month], from: visibleMonth)
        return String(format: "%02d/%04d", parts.month ?? 1, parts.year ?? 1)
    }

    var canMoveForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: visibleMonth) else { return false }
        return next <= today
    }

    var days: [Date?] {
        let offset = (calendar.component(.weekday, from: visibleMonth) + 5) % 7
        let count = calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 0
        return (0..<42).map { index in
            guard index >= offset, index < offset + count else { return nil }
            return calendar.date(byAdding: .day, value: index - offset, to: visibleMonth)
        }
    }

    func label(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%02d/%02d/%04d", parts.day ?? 1, parts.month ?? 1, parts.year ?? 1)
    }

    mutating func moveMonth(_ offset: Int) {
        guard let next = calendar.date(byAdding: .month, value: offset, to: visibleMonth),
              next <= today, calendar.component(.year, from: next) >= 1 else { return }
        visibleMonth = next
    }

    mutating func select(_ day: Date) {
        let normalized = calendar.startOfDay(for: day)
        guard normalized <= today else { return }
        selectedDay = normalized
    }

    mutating func showToday() {
        selectedDay = today
        visibleMonth = calendar.dateInterval(of: .month, for: today)!.start
    }
}
