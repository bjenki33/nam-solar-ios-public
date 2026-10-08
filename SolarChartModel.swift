import Foundation

struct SolarHistorySeries: Identifiable, Sendable {
    let entity: String
    let points: [HistoryPoint]
    var id: String { entity }
}

struct SolarChartModel: Sendable {
    let series: [SolarHistorySeries]
    let points: [HistoryPoint]
    let domain: ClosedRange<Date>
    let renderingPoints: [HistoryPoint]
    private let valueBounds: ClosedRange<Double>

    init(points input: [HistoryPoint]) {
        var unique: [String: HistoryPoint] = [:]
        for point in input where point.value.isFinite && point.date.timeIntervalSince1970.isFinite {
            unique[point.id] = point
        }
        let sorted = unique.values.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.entity != $1.entity { return $0.entity < $1.entity }
            return $0.segment < $1.segment
        }
        points = sorted
        renderingPoints = SolarChartRendering.reduced(sorted)
        let groups = Dictionary(grouping: sorted, by: \.entity)
        series = groups.keys.sorted().map { SolarHistorySeries(entity: $0, points: groups[$0]!) }
        let start = sorted.first?.date ?? Date(timeIntervalSince1970: 0)
        let end = sorted.last?.date ?? start
        domain = start == end ? start.addingTimeInterval(-30)...end.addingTimeInterval(30) : start...end
        let values = sorted.map(\.value)
        valueBounds = (values.min() ?? 0)...(values.max() ?? 1)
    }

    var duration: TimeInterval { domain.upperBound.timeIntervalSince(domain.lowerBound) }

    static func axisTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    func yDomain(unit: String) -> ClosedRange<Double> {
        if unit == "%" { return min(0, valueBounds.lowerBound)...max(100, valueBounds.upperBound) }
        let padding = max(1, (valueBounds.upperBound - valueBounds.lowerBound) * 0.08)
        return (valueBounds.lowerBound - padding)...(valueBounds.upperBound + padding)
    }

    func inspectionDate(at date: Date) -> Date {
        if let first = points.first, first.date == points.last?.date { return first.date }
        return min(domain.upperBound, max(domain.lowerBound, date))
    }

    // Match the chart's step-end line: hold a recorded value, never interpolate
    // a percentage or carry a reading across an unavailable-data segment.
    func sample(at date: Date, entity: String) -> HistoryPoint? {
        guard let items = series.first(where: { $0.entity == entity })?.points else { return nil }
        let index = insertionIndex(in: items, date: date, afterEqual: true) - 1
        guard index >= 0 else { return nil }
        let point = items[index]
        if point.date == date { return point }
        guard index + 1 < items.count, items[index + 1].segment == point.segment else { return nil }
        return point
    }

    func visiblePoints(in window: ClosedRange<Date>) -> [HistoryPoint] {
        series.flatMap { item in
            let start = max(0, insertionIndex(in: item.points, date: window.lowerBound, afterEqual: false) - 1)
            let end = min(item.points.count, insertionIndex(in: item.points, date: window.upperBound, afterEqual: true) + 1)
            return Array(item.points[start..<end])
        }
    }

    func drawingPoints(in window: ClosedRange<Date>) -> [HistoryPoint] {
        if window == domain { return renderingPoints }
        // Zoom still uses original samples, not an already downsampled line.
        return SolarChartRendering.reduced(visiblePoints(in: window))
    }

    func zoomed(_ window: ClosedRange<Date>, factor: Double, around anchor: Date) -> ClosedRange<Date> {
        guard factor.isFinite, factor > 0 else { return window }
        let oldSpan = window.upperBound.timeIntervalSince(window.lowerBound)
        guard oldSpan > 0 else { return domain }
        let minimumSpan = min(duration, max(60, duration / 1024))
        let span = min(duration, max(minimumSpan, oldSpan / factor))
        let focus = min(window.upperBound, max(window.lowerBound, anchor))
        let fraction = focus.timeIntervalSince(window.lowerBound) / oldSpan
        return boundedWindow(start: focus.addingTimeInterval(-fraction * span), span: span)
    }

    func shifted(_ window: ClosedRange<Date>, by fraction: Double) -> ClosedRange<Date> {
        guard fraction.isFinite else { return window }
        let span = min(duration, window.upperBound.timeIntervalSince(window.lowerBound))
        return boundedWindow(start: window.lowerBound.addingTimeInterval(span * fraction), span: span)
    }

    private func boundedWindow(start: Date, span: TimeInterval) -> ClosedRange<Date> {
        let lower = min(domain.upperBound.addingTimeInterval(-span), max(domain.lowerBound, start))
        return lower...lower.addingTimeInterval(span)
    }

    private func insertionIndex(in items: [HistoryPoint], date: Date, afterEqual: Bool) -> Int {
        var lower = 0
        var upper = items.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if items[middle].date < date || (afterEqual && items[middle].date == date) { lower = middle + 1 }
            else { upper = middle }
        }
        return lower
    }
}
