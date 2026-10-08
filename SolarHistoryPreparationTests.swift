import XCTest
#if canImport(SolarCore)
@testable import SolarCore
#else
@testable import NamSolar
#endif

final class SolarHistoryPreparationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1800000000)

    func testBackgroundDecodePreservesFractionalTimesAndUnavailableGaps() async throws {
        let json = """
        [[{"entity_id":"sensor.lux_battery_power","state":"-240","last_updated":"2026-10-08T05:00:00.123Z"},
        {"state":"unavailable","last_updated":"2026-10-08T05:01:00Z"},
        {"state":"240","last_updated":"2026-10-08T05:02:00+00:00"}]]
        """
        let points = try await SolarHistoryPreparation.decode(Data(json.utf8), allowed: [SolarBatteryPower.entity])
        XCTAssertEqual(points.map(\.value), [-240, 240], "Decode must not change raw signs")
        XCTAssertEqual(points.map(\.segment), [0, 1])
        XCTAssertEqual(points.first?.date, SolarDate.parse("2026-10-08T05:00:00.123Z"))
    }

    func testPreparedChartsConvertBatteryExactlyOnceAndKeepSOCAndCell() async throws {
        let power = [HistoryPoint(entity: SolarBatteryPower.entity, date: now, value: -240, segment: 0)]
        let battery = [HistoryPoint(entity: "sensor.lux_battery_soc", date: now, value: 86, segment: 0),
                       HistoryPoint(entity: "sensor.lux_cell_delta", date: now, value: 64, segment: 0)]
        let charts = try await SolarHistoryPreparation.general(power: power, battery: battery)
        XCTAssertEqual(charts.power.points.map(\.value), [240])
        XCTAssertEqual(charts.soc.points.map(\.value), [86])
        XCTAssertEqual(charts.cell.points.map(\.value), [64])
        XCTAssertEqual(power.first?.value, -240)
        XCTAssertEqual(charts.power.sample(at: now, entity: SolarBatteryPower.entity)?.value, 240)
    }

    func testPreparedDeviceChartsKeepOnlyTheirOwnSamples() async throws {
        let input = [HistoryPoint(entity: SolarDevice.inverter.entity, date: now, value: 1577, segment: 0),
                     HistoryPoint(entity: SolarDevice.home.entity, date: now, value: 1578, segment: 0),
                     HistoryPoint(entity: SolarDevice.grid.entity, date: now, value: -420, segment: 0)]
        let charts = try await SolarHistoryPreparation.devices(input, devices: SolarDevice.allCases)
        XCTAssertEqual(charts[.inverter]?.points.map(\.value), [1577])
        XCTAssertEqual(charts[.home]?.points.map(\.value), [1578])
        XCTAssertEqual(charts[.grid]?.points.map(\.value), [-420])
        XCTAssertTrue(charts[.solar]?.points.isEmpty == true)
    }

    func testCachedFullPlotKeepsSpikesWhileZoomUsesOriginalResolution() async throws {
        let points: [HistoryPoint] = (0..<10000).map { i -> HistoryPoint in
            let value: Double
            if i == 4321 { value = 9000 }
            else if i == 7654 { value = -900 }
            else { value = Double(i % 50) }
            let date = now.addingTimeInterval(Double(i))
            return HistoryPoint(entity: SolarDevice.inverter.entity, date: date, value: value, segment: 0)
        }
        let model = try await SolarHistoryPreparation.chart(points)
        XCTAssertLessThanOrEqual(model.renderingPoints.count, 2048)
        XCTAssertEqual(model.drawingPoints(in: model.domain).map(\.id), model.renderingPoints.map(\.id))
        XCTAssertTrue(model.renderingPoints.contains { $0.value == 9000 })
        XCTAssertTrue(model.renderingPoints.contains { $0.value == -900 })
        let window = now.addingTimeInterval(6100)...now.addingTimeInterval(6150)
        XCTAssertEqual(model.drawingPoints(in: window).map(\.id), model.visiblePoints(in: window).map(\.id))
        XCTAssertEqual(model.sample(at: points[6789].date, entity: SolarDevice.inverter.entity)?.id, points[6789].id)
    }

    func testCancelledCallerDoesNotPrepareOrReturnHistory() async {
        let work = Task {
            await Task.yield()
            return try await SolarHistoryPreparation.chart([])
        }
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled preparation must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testDenseDecodeUsesBoundedFormatterWorkAndRejectsMalformedJSON() async throws {
        let records = (0..<6000).map { i in
            let entity = i == 0 ? "\"entity_id\":\"sensor.lux_home_power\"," : ""
            return "{\(entity)\"state\":\"\(i)\",\"last_updated\":\"2026-10-08T05:00:00.123456Z\"}"
        }.joined(separator: ",")
        let start = Date()
        let points = try await SolarHistoryPreparation.decode(Data(("[[" + records + "]]").utf8), allowed: [SolarDevice.home.entity])
        XCTAssertEqual(points.count, 6000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5, "History timestamp parsing must not rebuild formatters per record")
        do {
            _ = try await SolarHistoryPreparation.decode(Data("not JSON".utf8), allowed: [])
            XCTFail("Bad responses must not become an empty successful chart")
        } catch { XCTAssertTrue(error is DecodingError) }
    }
}
