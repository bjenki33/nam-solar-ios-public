import Foundation

enum SolarEnergyMetric: String, CaseIterable, Identifiable, Sendable {
    case pv, charge, discharge, gridImport, gridExport, consumption
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pv: return "Sản lượng PV"
        case .charge: return "Sạc pin"
        case .discharge: return "Xả pin"
        case .gridImport: return "Mua từ lưới"
        case .gridExport: return "Phát lên lưới"
        case .consumption: return "Tiêu thụ ước tính"
        }
    }
    static let meters: [Self] = [.pv, .charge, .discharge, .gridImport, .gridExport]
}

enum SolarEnergyError: LocalizedError {
    case invalidDates, rangeTooLong, futureDate, notConfigured, invalidTimeZone, invalidStatistics, requestFailed
    var errorDescription: String? {
        switch self {
        case .invalidDates: return "Ngày kết thúc phải bằng hoặc sau ngày bắt đầu."
        case .rangeTooLong: return "Chọn tối đa 366 ngày mỗi lần để tải lịch sử ổn định."
        case .futureDate: return "Chỉ xem được ngày hôm nay hoặc ngày trong quá khứ."
        case .notConfigured: return "Tab Năng lượng trên web chưa có nguồn điện được cấu hình."
        case .invalidTimeZone: return "Chưa xác định được múi giờ hệ thống. Hãy tải lại."
        case .invalidStatistics: return "Dữ liệu thống kê chưa hợp lệ. Hãy tải lại; app không tự thay bằng số 0."
        case .requestFailed: return "Chưa tải được thống kê năng lượng. Kiểm tra kết nối và thử lại."
        }
    }
}

struct SolarEnergyRange: Equatable, Sendable {
    static let defaultTimeZone = "Asia/Ho_Chi_Minh"
    let start: Date
    let lastDay: Date
    let end: Date
    let timeZoneID: String
    let dayCount: Int
    var hourly: Bool { dayCount == 1 }
    var period: String { hourly ? "hour" : "day" }
    var calendar: Calendar { Self.calendar(timeZoneID) }

    init(from: Date, through: Date, timeZoneID: String = Self.defaultTimeZone, now: Date = Date()) throws {
        guard TimeZone(identifier: timeZoneID) != nil else { throw SolarEnergyError.invalidTimeZone }
        let calendar = Self.calendar(timeZoneID)
        let first = calendar.startOfDay(for: from)
        let last = calendar.startOfDay(for: through)
        guard last >= first else { throw SolarEnergyError.invalidDates }
        guard last <= calendar.startOfDay(for: now) else { throw SolarEnergyError.futureDate }
        let count = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        guard count <= 366 else { throw SolarEnergyError.rangeTooLong }
        guard let end = calendar.date(byAdding: .day, value: 1, to: last) else { throw SolarEnergyError.invalidDates }
        start = first; lastDay = last; self.end = end; dayCount = count; self.timeZoneID = timeZoneID
    }

    static func calendar(_ timeZoneID: String = defaultTimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func resolved(in timeZone: String, now: Date = Date()) throws -> Self {
        guard TimeZone(identifier: timeZone) != nil else { throw SolarEnergyError.invalidTimeZone }
        let target = Self.calendar(timeZone)
        guard let first = target.date(from: calendar.dateComponents([.year, .month, .day], from: start)),
              let last = target.date(from: calendar.dateComponents([.year, .month, .day], from: lastDay)) else {
            throw SolarEnergyError.invalidDates
        }
        return try Self(from: first, through: last, timeZoneID: timeZone, now: now)
    }

    // HA day grouping includes the calendar day containing end_time. Never send the next midnight.
    var requestEnd: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: end.addingTimeInterval(-0.001))
    }

    func label(_ date: Date, time: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = time ? "HH:mm" : "dd/MM/yyyy"
        return formatter.string(from: date)
    }
    var title: String { hourly ? label(start) : label(start) + " – " + label(lastDay) }
    var intervals: [DateInterval] {
        var result: [DateInterval] = []
        var cursor = start
        while cursor < end {
            guard let next = calendar.date(byAdding: hourly ? .hour : .day, value: 1, to: cursor), next > cursor else { break }
            result.append(DateInterval(start: cursor, end: min(next, end)))
            cursor = next
        }
        return result
    }
}

struct SolarEnergyPreferences: Decodable {
    struct Source: Decodable {
        let type: String
        let stat_energy_from: String?
        let stat_energy_to: String?
        let flow_from: [Flow]?
        let flow_to: [Flow]?
        struct Flow: Decodable { let stat_energy_from: String?; let stat_energy_to: String? }
    }
    let energy_sources: [Source]

    func meters() throws -> [SolarEnergyMetric: [String]] {
        var result: [SolarEnergyMetric: Set<String>] = [:]
        func add(_ metric: SolarEnergyMetric, _ id: String?) {
            if let id, !id.isEmpty { result[metric, default: []].insert(id) }
        }
        for source in energy_sources {
            switch source.type {
            case "solar": add(.pv, source.stat_energy_from)
            case "battery": add(.discharge, source.stat_energy_from); add(.charge, source.stat_energy_to)
            case "grid":
                add(.gridImport, source.stat_energy_from); add(.gridExport, source.stat_energy_to)
                source.flow_from?.forEach { add(.gridImport, $0.stat_energy_from) }
                source.flow_to?.forEach { add(.gridExport, $0.stat_energy_to) }
            default: break
            }
        }
        guard !result.isEmpty else { throw SolarEnergyError.notConfigured }
        let ids = result.values.flatMap { $0 }
        guard Set(ids).count == ids.count else { throw SolarEnergyError.invalidStatistics }
        return result.mapValues { $0.sorted() }
    }
}

struct SolarEnergyMetadata: Decodable {
    let statistic_id: String
    let has_sum: Bool
    let unit_class: String?
    let statistics_unit_of_measurement: String?
    var energyCompatible: Bool {
        has_sum && (unit_class == "energy" || ["Wh", "kWh", "MWh", "GJ"].contains(statistics_unit_of_measurement ?? ""))
    }
}

struct SolarEnergyStatistic: Decodable, Sendable {
    let start: Double
    let end: Double
    let change: Double?
}

struct SolarEnergyBucket: Identifiable, Sendable {
    let start: Date
    let end: Date
    let values: [SolarEnergyMetric: Double]
    var id: Date { start }
    func value(_ metric: SolarEnergyMetric) -> Double? { values[metric] }
}

struct SolarEnergyReport: Sendable {
    let range: SolarEnergyRange
    let buckets: [SolarEnergyBucket]
    let loadedAt: Date
    let unavailableMeters: [SolarEnergyMetric]
    var hasData: Bool { buckets.contains { !$0.values.isEmpty } }
    func total(_ metric: SolarEnergyMetric) -> Double? {
        let values = buckets.compactMap { $0.value(metric) }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    func missingCount(_ metric: SolarEnergyMetric) -> Int {
        buckets.filter { $0.start < loadedAt && $0.value(metric) == nil }.count
    }
    var incomplete: Bool { SolarEnergyMetric.meters.contains { missingCount($0) > 0 } }
    var latestEnd: Date? { buckets.last { !$0.values.isEmpty }?.end }

    static func build(range: SolarEnergyRange, meters: [SolarEnergyMetric: [String]],
                      metadata: [SolarEnergyMetadata], statistics: [String: [SolarEnergyStatistic]],
                      now: Date = Date()) throws -> Self {
        let validIDs = Set(metadata.filter(\.energyCompatible).map(\.statistic_id))
        let unavailable = SolarEnergyMetric.meters.filter { metric in
            let ids = meters[metric] ?? []
            return ids.isEmpty || !ids.allSatisfy { validIDs.contains($0) }
        }
        let intervals = range.intervals
        let intervalEnds = Dictionary(uniqueKeysWithValues: intervals.map { ($0.start, $0.end) })
        var indexed: [String: [Date: Double]] = [:]
        for id in Set(meters.values.flatMap { $0 }) where validIDs.contains(id) {
            var seen = Set<Date>()
            for row in statistics[id] ?? [] {
                guard row.start.isFinite, row.end.isFinite else { throw SolarEnergyError.invalidStatistics }
                // WebSocket timestamps are milliseconds, not seconds; change is server-normalized kWh.
                let date = Date(timeIntervalSince1970: row.start / 1000)
                guard date >= range.start, date < range.end, date < now else { continue }
                guard let expectedEnd = intervalEnds[date], row.end > row.start,
                      abs(row.end / 1000 - expectedEnd.timeIntervalSince1970) < 0.001,
                      seen.insert(date).inserted else { throw SolarEnergyError.invalidStatistics }
                guard let value = row.change, value.isFinite, value >= -0.000001 else { continue }
                indexed[id, default: [:]][date] = max(0, value)
            }
        }
        let buckets = intervals.map { interval in
            var values: [SolarEnergyMetric: Double] = [:]
            for metric in SolarEnergyMetric.meters where !unavailable.contains(metric) {
                let samples = (meters[metric] ?? []).compactMap { indexed[$0]?[interval.start] }
                if samples.count == meters[metric]?.count { values[metric] = samples.reduce(0, +) }
            }
            if let pv = values[.pv], let charge = values[.charge], let discharge = values[.discharge],
               let buy = values[.gridImport], let sell = values[.gridExport] {
                let balance = pv + discharge + buy - charge - sell
                if balance >= -0.000001 { values[.consumption] = max(0, balance) }
            }
            return SolarEnergyBucket(start: interval.start, end: interval.end, values: values)
        }
        return Self(range: range, buckets: buckets, loadedAt: now, unavailableMeters: unavailable)
    }
}
