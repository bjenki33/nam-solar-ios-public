import XCTest
#if canImport(SolarCore)
@testable import SolarCore
#else
@testable import NamSolar
#endif

final class SolarChartModelTests: XCTestCase {
    private func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
    private func point(_ time: Double, _ value: Double, entity: String = "soc", segment: Int = 0) -> HistoryPoint {
        HistoryPoint(entity: entity, date: date(time), value: value, segment: segment)
    }

    func testTimeAxisUses24HourClockAndRequestedTimeZone() {
        let utc = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 20, minute: 5))!
        XCTAssertEqual(SolarChartModel.axisTime(evening, timeZone: utc), "20:05")
        XCTAssertEqual(SolarChartModel.axisTime(evening, timeZone: TimeZone(secondsFromGMT: 7 * 3600)!), "03:05")
        XCTAssertEqual(SolarChartModel.axisTime(evening, timeZone: .current), String(solarLocalTime(evening).prefix(5)))
    }

    private func solarLocalTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    func testInspectionUsesRecordedStepValueNotInterpolation() {
        let model = SolarChartModel(points: [point(0, 40), point(100, 80)])
        XCTAssertEqual(model.sample(at: date(50), entity: "soc")?.value, 40)
        XCTAssertEqual(model.sample(at: date(100), entity: "soc")?.value, 80)
        XCTAssertNil(model.sample(at: date(-1), entity: "soc"))
        XCTAssertNil(model.sample(at: date(101), entity: "soc"))
    }

    func testUnavailableSegmentsNeverSupplyAValueInTheGap() {
        let model = SolarChartModel(points: [point(0, 40), point(20, 42), point(40, 50, segment: 1), point(60, 55, segment: 1)])
        XCTAssertNil(model.sample(at: date(30), entity: "soc"))
        XCTAssertEqual(model.sample(at: date(50), entity: "soc")?.value, 50)
        XCTAssertEqual(model.sample(at: date(20), entity: "soc")?.value, 42)
    }

    func testAsynchronousSeriesRetainTheirActualSampleTimes() {
        let model = SolarChartModel(points: [point(0, 400, entity: "pv"), point(100, 600, entity: "pv"),
                                            point(10, -240, entity: "battery"), point(110, -200, entity: "battery")])
        XCTAssertEqual(model.sample(at: date(50), entity: "pv")?.date, date(0))
        XCTAssertEqual(model.sample(at: date(50), entity: "battery")?.date, date(10))
        XCTAssertEqual(model.sample(at: date(50), entity: "battery")?.value, -240)
        XCTAssertNil(model.sample(at: date(105), entity: "pv"))
    }

    func testVisibleWindowKeepsEdgeContextAndSegmentIdentity() {
        let model = SolarChartModel(points: [point(0, 40), point(20, 42), point(60, 50, segment: 1), point(80, 55, segment: 1)])
        let visible = model.visiblePoints(in: date(25)...date(55))
        XCTAssertEqual(visible.map(\.date), [date(20), date(60)])
        XCTAssertEqual(visible.map(\.segment), [0, 1])
    }

    func testZoomPreservesTheFocusPosition() {
        let model = SolarChartModel(points: [point(0, 40), point(3600, 80)])
        let window = model.zoomed(model.domain, factor: 2, around: date(900))
        XCTAssertEqual(window.lowerBound, date(450))
        XCTAssertEqual(window.upperBound, date(2250))
    }

    func testZoomClampsToHistoryAndMinimumDuration() {
        let model = SolarChartModel(points: [point(0, 40), point(3600, 80)])
        let window = model.zoomed(model.domain, factor: 10000, around: date(3600))
        XCTAssertEqual(window.lowerBound, date(3540))
        XCTAssertEqual(window.upperBound, date(3600))
        XCTAssertEqual(model.zoomed(window, factor: 0.001, around: date(3600)), model.domain)
    }

    func testPanCannotMoveOutsideLoadedHistory() {
        let model = SolarChartModel(points: [point(0, 40), point(3600, 80)])
        let window = model.zoomed(model.domain, factor: 2, around: date(900))
        XCTAssertEqual(model.shifted(window, by: 10), date(1800)...date(3600))
        XCTAssertEqual(model.shifted(window, by: -10), date(0)...date(1800))
    }

    func testInvalidZoomFactorsAreIgnored() {
        let model = SolarChartModel(points: [point(0, 40), point(3600, 80)])
        for factor in [Double.nan, Double.infinity, 0, -1] {
            XCTAssertEqual(model.zoomed(model.domain, factor: factor, around: date(100)), model.domain)
        }
    }

    func testSingleSampleHasUsableDomainAndExactInspectionDate() {
        let model = SolarChartModel(points: [point(100, 75.42)])
        XCTAssertEqual(model.duration, 60)
        XCTAssertEqual(model.inspectionDate(at: date(90)), date(100))
        XCTAssertEqual(model.sample(at: model.inspectionDate(at: date(90)), entity: "soc")?.value, 75.42)
        XCTAssertEqual(model.zoomed(model.domain, factor: 2, around: date(100)), model.domain)
    }

    func testInvalidAndDuplicateSamplesAreSanitized() {
        let model = SolarChartModel(points: [point(0, 40), point(0, 42), point(100, 80), point(50, .nan)])
        XCTAssertEqual(model.points.count, 2)
        XCTAssertEqual(model.sample(at: date(0), entity: "soc")?.value, 42)
        XCTAssertEqual(SolarChartModel(points: []).visiblePoints(in: date(0)...date(10)).count, 0)
        XCTAssertEqual(model.yDomain(unit: "%"), 0...100)
    }
}
