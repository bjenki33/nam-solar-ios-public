import Foundation

#if DEBUG
enum SolarEnergyPreview {
    static func report(_ range: SolarEnergyRange, empty: Bool = false, now: Date = Date()) throws -> SolarEnergyReport {
        let ids: [SolarEnergyMetric: [String]] = [.pv: ["test.pv"], .charge: ["test.charge"], .discharge: ["test.discharge"],
            .gridImport: ["test.import"], .gridExport: ["test.export"]]
        let metadata = ids.values.flatMap { $0 }.map {
            SolarEnergyMetadata(statistic_id: $0, has_sum: true, unit_class: "energy", statistics_unit_of_measurement: "kWh")
        }
        var stats: [String: [SolarEnergyStatistic]] = [:]
        if !empty {
            for (index, interval) in range.intervals.enumerated() where interval.start < now {
                let hour = range.calendar.component(.hour, from: interval.start)
                let pv = range.hourly ? max(0, sin(Double(hour - 6) / 12 * .pi)) * 3 : 18 + Double(index % 7)
                let values: [SolarEnergyMetric: Double] = [.pv: pv, .charge: pv * 0.4,
                    .discharge: range.hourly ? (hour < 6 || hour > 17 ? 0.6 : 0) : 7,
                    .gridImport: range.hourly ? 0.05 : 1.2, .gridExport: 0]
                for (metric, ids) in ids {
                    stats[ids[0], default: []].append(SolarEnergyStatistic(start: interval.start.timeIntervalSince1970 * 1000,
                        end: interval.end.timeIntervalSince1970 * 1000, change: values[metric]))
                }
            }
        }
        return try SolarEnergyReport.build(range: range, meters: ids, metadata: metadata, statistics: stats, now: now)
    }
}
#endif
