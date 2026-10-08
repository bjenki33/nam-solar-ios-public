import XCTest
@testable import NamSolar

final class SolarLayoutTests: XCTestCase {
    func testLargeScreenPreservesBalancedOuterMargins() {
        let m = SolarOverviewMetrics(viewportHeight: 763, summaryHeight: 202, statusHeight: 17)
        XCTAssertEqual(m.totalHeight, 763, accuracy: 0.1)
        XCTAssertEqual(m.flowY + m.flowHeight, 747, accuracy: 0.1)
        XCTAssertEqual(SolarOverviewMetrics.topGap, 12)
        XCTAssertEqual(SolarOverviewMetrics.bottomGap, 16)
    }

    func testCompactScreenFitsPreviewAndDeviceDiagram() {
        let m = SolarOverviewMetrics(viewportHeight: 598, summaryHeight: 223, statusHeight: 17)
        XCTAssertEqual(m.totalHeight, 598, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(m.flowHeight, 300)
        XCTAssertEqual(m.flowY + m.flowHeight, 582, accuracy: 0.1)
    }

    func testShortViewportScrollsInsteadOfClippingDevices() {
        let m = SolarOverviewMetrics(viewportHeight: 240, summaryHeight: 202, statusHeight: 17)
        XCTAssertEqual(m.flowHeight, 300)
        XCTAssertGreaterThan(m.totalHeight, 240)
        XCTAssertEqual(m.totalHeight - m.flowY - m.flowHeight, 16, accuracy: 0.1)
    }

    func testLargerSummaryMovesDiagramDownWithoutExtendingItsBottom() {
        let before = SolarOverviewMetrics(viewportHeight: 763, summaryHeight: 202, statusHeight: 17)
        let after = SolarOverviewMetrics(viewportHeight: 763, summaryHeight: 234, statusHeight: 17)
        XCTAssertEqual(after.flowY - before.flowY, 32, accuracy: 0.1)
        XCTAssertEqual(before.flowHeight - after.flowHeight, 32, accuracy: 0.1)
        XCTAssertEqual(after.totalHeight, before.totalHeight, accuracy: 0.1)
        XCTAssertEqual(after.totalHeight - after.flowY - after.flowHeight, 16, accuracy: 0.1)
    }

    func testLargerSummaryKeepsMinimumDiagramSizeOnCompactScreens() {
        let m = SolarOverviewMetrics(viewportHeight: 598, summaryHeight: 234, statusHeight: 17)
        XCTAssertEqual(m.totalHeight, 598, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(m.flowHeight, 300)
        let preview = SolarOverviewMetrics(viewportHeight: 598, summaryHeight: 254, statusHeight: 17)
        XCTAssertEqual(preview.flowHeight, 300)
        XCTAssertGreaterThan(preview.totalHeight, 598)
    }

    func testReadableConsumptionKeepsLargeScreenBottomMargin() {
        let m = SolarOverviewMetrics(viewportHeight: 763, summaryHeight: 300, statusHeight: 17)
        XCTAssertEqual(m.totalHeight, 763, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(m.flowHeight, 300)
        XCTAssertEqual(m.totalHeight - m.flowY - m.flowHeight, 16, accuracy: 0.1)
    }

    func testTallConsumptionReflowsByScrollingNotClippingOrShrinkingDiagram() {
        let m = SolarOverviewMetrics(viewportHeight: 598, summaryHeight: 300, statusHeight: 17)
        XCTAssertEqual(m.flowHeight, 300)
        XCTAssertGreaterThan(m.totalHeight, 598)
        XCTAssertEqual(m.totalHeight - m.flowY - m.flowHeight, 16, accuracy: 0.1)
    }
}
