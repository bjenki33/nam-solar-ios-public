import XCTest
#if canImport(SolarCore)
@testable import SolarCore
#else
@testable import NamSolar
#endif

final class SolarHistoryRegressionTests: XCTestCase {
    private let entity = SolarSOCStatistics.entity
    private let origin = Date(timeIntervalSince1970: 1791504000)

    private func date(_ seconds: Double) -> Date { origin.addingTimeInterval(seconds) }
    private func history(_ records: [(Double, String)], end: Double? = nil) throws -> SolarChartModel {
        let rows = records.enumerated().map { index, item in
            var row = ["state": item.1, "last_updated": SolarDate.iso(date(item.0))]
            if index == 0 { row["entity_id"] = entity }
            return row
        }
        let data = try JSONSerialization.data(withJSONObject: [rows])
        return SolarChartModel(points: try HistoryParser.parse(data, allowed: [entity], end: end.map(date)))
    }
    private func bucket(_ start: Double, _ mean: Double?) -> SolarSOCStatistic {
        SolarSOCStatistic(start: date(start).timeIntervalSince1970 * 1000,
                          end: date(start + 300).timeIntervalSince1970 * 1000, mean: mean)
    }

    func testThreeHourPlateauEndsAtActualUnavailableNotLastChange() throws {
        let model = try history([(0, "21"), (10800, "unavailable"), (10842, "22")], end: 12000)
        XCTAssertEqual(model.sample(at: date(10799), entity: entity)?.value, 21)
        XCTAssertNil(model.sample(at: date(10800), entity: entity))
        XCTAssertNil(model.sample(at: date(10841), entity: entity))
        XCTAssertEqual(model.sample(at: date(10842), entity: entity)?.value, 22)
        XCTAssertEqual(model.points.filter(\.isBoundary).map(\.date), [date(10800), date(12000)])
        XCTAssertEqual(model.sample(at: date(10799), entity: entity)?.date, date(0))
    }

    func testFourHourFullBatteryKeepsShortRealGap() throws {
        let model = try history([(0, "100"), (14400, "unknown"), (14403, "100")], end: 15000)
        XCTAssertEqual(model.sample(at: date(14399), entity: entity)?.value, 100)
        XCTAssertNil(model.sample(at: date(14401), entity: entity))
        XCTAssertEqual(model.sample(at: date(14999), entity: entity)?.value, 100)
    }

    func testLongAndConsecutiveUnavailableRecordsNeverGetFilled() throws {
        let model = try history([(0, "80"), (60, "unavailable"), (120, "unknown"), (7200, "30")], end: 7500)
        XCTAssertEqual(model.sample(at: date(59), entity: entity)?.value, 80)
        for t in [60.0, 120, 1000, 7199] { XCTAssertNil(model.sample(at: date(t), entity: entity)) }
        XCTAssertEqual(model.sample(at: date(7200), entity: entity)?.value, 30)
        XCTAssertEqual(model.points.filter(\.isBoundary).count, 2)
    }

    func testRequestEndExtendsOnlyAnAvailableLastState() throws {
        let available = try history([(0, "21")], end: 3600)
        XCTAssertEqual(available.sample(at: date(3599), entity: entity)?.value, 21)
        XCTAssertNil(available.sample(at: date(3600), entity: entity))
        XCTAssertNil(available.sample(at: date(3601), entity: entity))
        let missing = try history([(0, "21"), (60, "unavailable")], end: 3600)
        XCTAssertNil(missing.sample(at: date(100), entity: entity))
        XCTAssertEqual(missing.points.last?.date, date(60))
    }

    func testUnavailableAtSameTimestampDoesNotExposeNumericValue() throws {
        let model = try history([(0, "21"), (0, "unavailable"), (60, "22")], end: 120)
        XCTAssertNil(model.sample(at: date(0), entity: entity))
        XCTAssertNil(model.sample(at: date(30), entity: entity))
        XCTAssertEqual(model.sample(at: date(60), entity: entity)?.value, 22)
    }

    func testMalformedTimestampDoesNotInventBoundaryOrCarryValue() throws {
        let json = """
        [[{"entity_id":"sensor.lux_battery_soc","state":"21","last_updated":"2026-10-09T00:00:00Z"},
        {"state":"unavailable","last_updated":"not-a-date"},
        {"state":"30","last_updated":"2026-10-09T04:00:00Z"}]]
        """
        let model = SolarChartModel(points: try HistoryParser.parse(Data(json.utf8), allowed: [entity]))
        XCTAssertNil(model.sample(at: SolarDate.parse("2026-10-09T03:00:00Z")!, entity: entity))
        XCTAssertFalse(model.points.contains(where: \.isBoundary))
    }

    func testBoundaryProvenanceSurvivesBatterySignConversionAndReduction() {
        let point = HistoryPoint(entity: SolarBatteryPower.entity, date: date(60), value: -240,
                                 segment: 0, recordedAt: date(0), isBoundary: true)
        let converted = SolarBatteryPower.history([point])[0]
        XCTAssertEqual(converted.value, 240)
        XCTAssertTrue(converted.isBoundary)
        XCTAssertEqual(converted.recordedAt, date(0))
        XCTAssertTrue(SolarChartRendering.reduced([converted])[0].isBoundary)
    }

    func testStatisticsDecodeMillisecondsAndUseMeanNotMinMax() throws {
        let json = "[{\"start\":1791504000000,\"end\":1791504300000,\"mean\":96.5,\"min\":95,\"max\":99}]"
        let decoded = try JSONDecoder().decode([SolarSOCStatistic].self, from: Data(json.utf8))
        let points = try SolarSOCStatistics.points(decoded)
        XCTAssertEqual(points.last?.date, date(300))
        XCTAssertEqual(points.last?.value, 96.5)
        XCTAssertEqual(points.last?.recordedAt, date(0))
        XCTAssertEqual(points.last?.aggregation, 300)
    }

    func testStatisticsPreserveFlat21And100PercentBuckets() throws {
        let buckets = (0..<84).map { bucket(Double($0) * 300, $0 < 36 ? 21 : 100) }
        let model = SolarChartModel(points: try SolarSOCStatistics.points(buckets))
        XCTAssertEqual(Set(model.points.map(\.segment)).count, 1)
        for t in [0.0, 1000, 10799] { XCTAssertEqual(model.sample(at: date(t), entity: entity)?.value, 21) }
        for t in [10800.0, 14400, 25199] { XCTAssertEqual(model.sample(at: date(t), entity: entity)?.value, 100) }
        XCTAssertNil(model.sample(at: date(25201), entity: entity))
    }

    func testMissingAndNullStatisticsRemainRealGaps() throws {
        let buckets = [bucket(0, 21), bucket(300, nil), bucket(600, 30), bucket(1200, 40)]
        let model = SolarChartModel(points: try SolarSOCStatistics.points(buckets))
        XCTAssertEqual(Set(model.points.map(\.segment)).count, 3)
        XCTAssertEqual(model.sample(at: date(299), entity: entity)?.value, 21)
        XCTAssertNil(model.sample(at: date(301), entity: entity))
        XCTAssertEqual(model.sample(at: date(601), entity: entity)?.value, 30)
        XCTAssertNil(model.sample(at: date(1000), entity: entity))
        XCTAssertEqual(model.sample(at: date(1201), entity: entity)?.value, 40)
    }

    func testStatisticsSortDeduplicateAndRejectImpossibleValues() throws {
        let model = SolarChartModel(points: try SolarSOCStatistics.points([
            bucket(600, 50), bucket(0, 21), bucket(300, 101), bucket(600, 60), bucket(900, -.infinity)]))
        XCTAssertEqual(model.points.filter { $0.date == date(900) }.map(\.value), [60])
        XCTAssertEqual(model.sample(at: date(700), entity: entity)?.value, 60)
        XCTAssertNil(model.sample(at: date(400), entity: entity))
    }

    func testCancelledStatisticsPreparationDoesNotPublish() async {
        let work = Task { try await SolarHistoryPreparation.socStatistics([bucket(0, 21)]) }
        work.cancel()
        do { _ = try await work.value; XCTFail("Cancelled statistics must not publish") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testZoomAndFingerPanningPreserveSpanAndClampBothEnds() throws {
        let model = try history([(0, "21"), (86400, "100")])
        let zoomed = model.zoomed(model.domain, factor: 4, around: date(43200))
        let moved = model.shifted(zoomed, by: 0.6)
        let reversed = model.shifted(moved, by: -0.6)
        XCTAssertEqual(moved.upperBound.timeIntervalSince(moved.lowerBound), 21600, accuracy: 0.001)
        XCTAssertEqual(reversed.lowerBound.timeIntervalSince(zoomed.lowerBound), 0, accuracy: 0.001)
        XCTAssertEqual(model.shifted(moved, by: 100).upperBound, model.domain.upperBound)
        XCTAssertEqual(model.shifted(moved, by: -100).lowerBound, model.domain.lowerBound)
        XCTAssertEqual(model.shifted(moved, by: .nan), moved)
    }
}
