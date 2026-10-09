import Foundation

// HA records discharge as positive. Convert only at presentation boundaries;
// keep raw states, recorder history and positive energy counters unchanged.
enum SolarBatteryPower {
    static let entity = "sensor.lux_battery_power"

    static func display(_ raw: Double?) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        return raw == 0 ? 0 : -raw
    }

    static func history(_ raw: [HistoryPoint]) -> [HistoryPoint] {
        raw.compactMap { point in
            guard point.entity == entity else { return point }
            guard let value = display(point.value) else { return nil }
            return HistoryPoint(entity: point.entity, date: point.date, value: value, segment: point.segment,
                                recordedAt: point.recordedAt, isBoundary: point.isBoundary, aggregation: point.aggregation)
        }
    }
}

extension SolarSnapshot {
    var batteryPower: Double? { SolarBatteryPower.display(number("battery_power")) }
    // The battery wire runs from inverter to battery; reverse only for discharge.
    var batteryFlowReversed: Bool { (batteryPower ?? 0) < 0 }
}
