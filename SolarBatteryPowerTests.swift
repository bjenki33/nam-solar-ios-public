import XCTest
#if canImport(SolarCore)
@testable import SolarCore
#else
@testable import NamSolar
#endif

final class SolarBatteryPowerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1800000000)

    private func snapshot(_ raw: String, live: Bool = true, age: TimeInterval = 0) -> SolarSnapshot {
        let values = ["local_connection": "online", "local_last_read": SolarDate.iso(now.addingTimeInterval(-age)),
                      "battery_power": raw, "battery_voltage": "54.3", "grid_power": "250",
                      "pv_today": "21", "charge_today": "13.7", "discharge_today": "1.8",
                      "grid_import_today": "0", "grid_export_today": "0"]
        let states = Dictionary(uniqueKeysWithValues: values.map {
            (SolarSnapshot.prefix + $0.key, HAState(entity_id: SolarSnapshot.prefix + $0.key, state: $0.value))
        })
        return SolarSnapshot(states: states, now: now, transportLive: live)
    }

    func testChargingIsPositiveWithoutChangingRawReadingOrStatus() {
        let data = snapshot("-3784")
        XCTAssertEqual(data.batteryPower, 3784)
        XCTAssertEqual(data.number("battery_power"), -3784)
        XCTAssertEqual(data.raw("battery_power"), "-3784")
        XCTAssertEqual(data.batteryStatus, "Đang sạc")
        XCTAssertFalse(data.batteryFlowReversed)
    }

    func testDischargingIsNegativeWithoutChangingRawReadingOrStatus() {
        let data = snapshot("3784")
        XCTAssertEqual(data.batteryPower, -3784)
        XCTAssertEqual(data.number("battery_power"), 3784)
        XCTAssertEqual(data.batteryStatus, "Đang xả")
        XCTAssertTrue(data.batteryFlowReversed)
    }

    func testZeroNeverDisplaysNegativeZeroAndDeadbandIsPreserved() {
        for raw in [0.0, -0.0] {
            XCTAssertEqual(SolarBatteryPower.display(raw), 0)
            XCTAssertEqual(SolarBatteryPower.display(raw)?.sign, .plus)
        }
        for raw in ["-5", "0", "5"] { XCTAssertEqual(snapshot(raw).batteryStatus, "Chờ") }
        XCTAssertEqual(snapshot("-5.01").batteryStatus, "Đang sạc")
        XCTAssertEqual(snapshot("5.01").batteryStatus, "Đang xả")
    }

    func testUnknownInvalidAndDisconnectedAreNotConvertedToZero() {
        for raw in ["unavailable", "unknown", "NaN", "Infinity", ""] {
            XCTAssertNil(snapshot(raw).batteryPower)
            XCTAssertEqual(snapshot(raw).batteryStatus, "Chưa có dữ liệu mới")
        }
        XCTAssertNil(SolarBatteryPower.display(nil))
        XCTAssertNil(SolarBatteryPower.display(.nan))
        XCTAssertNil(SolarBatteryPower.display(.infinity))
        XCTAssertNil(snapshot("-3784", live: false).batteryPower)
        XCTAssertNil(snapshot("-3784", age: 16).batteryPower)
        XCTAssertFalse(snapshot("3784", live: false).batteryFlowReversed)
    }

    func testCurrentAndEnergyMagnitudesAndGridConventionDoNotChange() {
        for raw in ["-3784", "3784"] {
            let data = snapshot(raw)
            XCTAssertEqual(data.estimatedCurrent(power: "battery_power", voltage: "battery_voltage")!, 3784 / 54.3, accuracy: 0.001)
            XCTAssertEqual(data.number("charge_today"), 13.7)
            XCTAssertEqual(data.number("discharge_today"), 1.8)
            XCTAssertEqual(data.consumption("today"), 9.1)
            XCTAssertEqual(data.estimatedSources, [7.3, 1.8, 0])
            XCTAssertEqual(data.number("grid_power"), 250)
            XCTAssertEqual(data.gridStatus, "Đang mua lưới")
        }
    }

    func testHistoryNormalizesOnlyBatteryAndPreservesMetadataAndSource() {
        let raw = [HistoryPoint(entity: SolarBatteryPower.entity, date: now, value: -3784, segment: 0),
                   HistoryPoint(entity: SolarBatteryPower.entity, date: now.addingTimeInterval(60), value: 1200, segment: 1),
                   HistoryPoint(entity: "sensor.lux_grid_power", date: now, value: -50, segment: 0),
                   HistoryPoint(entity: "sensor.lux_battery_soc", date: now, value: 99, segment: 0),
                   HistoryPoint(entity: "sensor.lux_charge_total", date: now, value: 281.8, segment: 0),
                   HistoryPoint(entity: "sensor.lux_cell_delta", date: now, value: 55, segment: 0)]
        let displayed = SolarBatteryPower.history(raw)
        XCTAssertEqual(displayed.map(\.value), [3784, -1200, -50, 99, 281.8, 55])
        XCTAssertEqual(raw.map(\.value), [-3784, 1200, -50, 99, 281.8, 55])
        XCTAssertEqual(displayed.map(\.id), raw.map(\.id))
        XCTAssertEqual(displayed.map(\.date), raw.map(\.date))
        XCTAssertEqual(displayed.map(\.segment), raw.map(\.segment))
        XCTAssertEqual(displayed.map(\.entity), raw.map(\.entity))
    }

    func testHistoryPlotAxisAndInspectorUseTheSameConvertedSigns() {
        let raw = [HistoryPoint(entity: SolarBatteryPower.entity, date: now, value: -3784, segment: 0),
                   HistoryPoint(entity: SolarBatteryPower.entity, date: now.addingTimeInterval(60), value: 1200, segment: 0)]
        let model = SolarChartModel(points: SolarBatteryPower.history(raw))
        XCTAssertEqual(model.points.map(\.value), [3784, -1200])
        XCTAssertEqual(model.sample(at: now.addingTimeInterval(30), entity: SolarBatteryPower.entity)?.value, 3784)
        XCTAssertEqual(model.sample(at: now.addingTimeInterval(60), entity: SolarBatteryPower.entity)?.value, -1200)
        XCTAssertLessThan(model.yDomain(unit: "W").lowerBound, -1200)
        XCTAssertGreaterThan(model.yDomain(unit: "W").upperBound, 3784)
    }

    func testHistoryKeepsUnavailableGapsAndRejectsInvalidBatteryValues() {
        let raw = [HistoryPoint(entity: SolarBatteryPower.entity, date: now, value: -240, segment: 0),
                   HistoryPoint(entity: SolarBatteryPower.entity, date: now.addingTimeInterval(60), value: 240, segment: 1),
                   HistoryPoint(entity: SolarBatteryPower.entity, date: now.addingTimeInterval(120), value: .nan, segment: 1)]
        let model = SolarChartModel(points: SolarBatteryPower.history(raw))
        XCTAssertEqual(model.points.count, 2)
        XCTAssertNil(model.sample(at: now.addingTimeInterval(30), entity: SolarBatteryPower.entity))
        XCTAssertEqual(model.sample(at: now.addingTimeInterval(60), entity: SolarBatteryPower.entity)?.value, -240)
    }
}
