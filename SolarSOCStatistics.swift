import Foundation

struct SolarSOCStatistic: Decodable, Sendable {
    let start: Double
    let end: Double
    let mean: Double?
}

enum SolarSOCStatistics {
    static let entity = "sensor.lux_battery_soc"

    // Recorder timestamps are milliseconds; preserve actual five-minute buckets.
    static func points(_ buckets: [SolarSOCStatistic]) throws -> [HistoryPoint] {
        var unique: [Double: SolarSOCStatistic] = [:]
        for bucket in buckets where bucket.start.isFinite && bucket.end.isFinite {
            unique[bucket.start] = bucket
        }
        var result: [HistoryPoint] = []
        var previousEnd: Double?
        var segment = 0
        for bucket in unique.values.sorted(by: { $0.start < $1.start }) {
            try Task.checkCancellation()
            guard let value = bucket.mean, value.isFinite, (0...100).contains(value),
                  abs((bucket.end - bucket.start) / 1000 - 300) < 0.001 else {
                segment += 1; previousEnd = nil; continue
            }
            let start = Date(timeIntervalSince1970: bucket.start / 1000)
            let end = Date(timeIntervalSince1970: bucket.end / 1000)
            if previousEnd == nil || abs(bucket.start - previousEnd!) > 1 {
                segment += 1
                // Start each contiguous run at its actual bucket boundary, not across a missing bucket.
                result.append(HistoryPoint(entity: entity, date: start, value: value, segment: segment,
                                           recordedAt: start, aggregation: 300))
            }
            result.append(HistoryPoint(entity: entity, date: end, value: value, segment: segment,
                                       recordedAt: start, aggregation: 300))
            previousEnd = bucket.end
        }
        return result
    }
}
