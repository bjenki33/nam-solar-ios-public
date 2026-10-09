import Foundation

struct SolarPreparedHistory: Sendable {
    let power: SolarChartModel
    let soc: SolarChartModel
    let cell: SolarChartModel
}

enum SolarHistoryPreparation {
    static func socStatistics(_ buckets: [SolarSOCStatistic]) async throws -> [HistoryPoint] {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) { try SolarSOCStatistics.points(buckets) }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    static func decode(_ data: Data, allowed: Set<String>, end: Date? = nil) async throws -> [HistoryPoint] {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let result = try HistoryParser.parse(data, allowed: allowed, end: end)
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    static func chart(_ points: [HistoryPoint]) async throws -> SolarChartModel {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let result = SolarChartModel(points: SolarBatteryPower.history(points))
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    static func devices(_ points: [HistoryPoint], devices: [SolarDevice]) async throws -> [SolarDevice: SolarChartModel] {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            let groups = Dictionary(grouping: points, by: \.entity)
            var result: [SolarDevice: SolarChartModel] = [:]
            for device in devices {
                try Task.checkCancellation()
                result[device] = SolarChartModel(points: groups[device.entity] ?? [])
            }
            return result
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }

    static func general(power: [HistoryPoint], battery: [HistoryPoint]) async throws -> SolarPreparedHistory {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let result = SolarPreparedHistory(power: SolarChartModel(points: SolarBatteryPower.history(power)),
                soc: SolarChartModel(points: battery.filter { $0.entity == "sensor.lux_battery_soc" }),
                cell: SolarChartModel(points: battery.filter { $0.entity == "sensor.lux_cell_delta" }))
            try Task.checkCancellation()
            return result
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}
