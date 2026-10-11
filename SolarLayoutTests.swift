import XCTest
@testable import NamSolar

final class SolarLayoutTests: XCTestCase {
    func testStatusAboveSummaryWithThreeSmallerEqualSectionGaps() {
        for summaryHeight in [CGFloat(202), 234, 300] {
            let m = SolarOverviewMetrics(viewportHeight: 763, summaryHeight: summaryHeight, statusHeight: 17)
            XCTAssertEqual(m.statusY, 6)
            XCTAssertEqual(m.summaryY - m.statusY - m.statusHeight, 5)
            XCTAssertEqual(m.summaryY, 28)
            XCTAssertEqual(m.flowY - m.summaryY - m.summaryHeight, m.summaryY)
            XCTAssertEqual(m.flowY, 56 + summaryHeight)
            XCTAssertEqual(m.totalHeight, 763)
            XCTAssertEqual(m.totalHeight - m.flowY - m.flowHeight, m.summaryY)
        }
    }

    func testChangingStatusHeightKeepsVisibleSectionGapsEqual() {
        for statusHeight in [CGFloat(0), 17, 29] {
            for summaryHeight in [CGFloat(202), 234, 300] {
                let m = SolarOverviewMetrics(viewportHeight: 763, summaryHeight: summaryHeight, statusHeight: statusHeight)
                XCTAssertEqual(m.summaryY, 11 + statusHeight)
                XCTAssertEqual(m.flowY - m.summaryY - m.summaryHeight, m.summaryY)
                XCTAssertEqual(m.summaryToFlowGap, m.summaryY)
                XCTAssertEqual(m.bottomGap, m.summaryY)
                XCTAssertEqual(m.totalHeight, 763)
                XCTAssertEqual(m.totalHeight - m.flowY - m.flowHeight, m.summaryY)
            }
        }
    }

    func testLargeScreenPreservesBalancedOuterMargins() {
        let m = SolarOverviewMetrics(viewportHeight: 763, summaryHeight: 202, statusHeight: 17)
        XCTAssertEqual(m.totalHeight, 763, accuracy: 0.1)
        XCTAssertEqual(m.flowY + m.flowHeight, 735, accuracy: 0.1)
        XCTAssertEqual(SolarOverviewMetrics.topGap, 6)
        XCTAssertEqual(m.bottomGap, 28)
    }

    func testCompactScreenFitsSmallerSummaryAndDeviceDiagram() {
        let m = SolarOverviewMetrics(viewportHeight: 598, summaryHeight: 202, statusHeight: 17)
        XCTAssertEqual(m.totalHeight, 598, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(m.flowHeight, 300)
        XCTAssertEqual(m.flowY + m.flowHeight, 570, accuracy: 0.1)
    }

    func testShortViewportScrollsInsteadOfClippingDevices() {
        let m = SolarOverviewMetrics(viewportHeight: 240, summaryHeight: 202, statusHeight: 17)
        XCTAssertEqual(m.flowHeight, 300)
        XCTAssertGreaterThan(m.totalHeight, 240)
        XCTAssertEqual(m.totalHeight - m.flowY - m.flowHeight, m.sectionGap, accuracy: 0.1)
    }

    func testLargerSummaryMovesDiagramDownWithoutExtendingItsBottom() {
        let before = SolarOverviewMetrics(viewportHeight: 763, summaryHeight: 202, statusHeight: 17)
        let after = SolarOverviewMetrics(viewportHeight: 763, summaryHeight: 234, statusHeight: 17)
        XCTAssertEqual(after.flowY - before.flowY, 32, accuracy: 0.1)
        XCTAssertEqual(before.flowHeight - after.flowHeight, 32, accuracy: 0.1)
        XCTAssertEqual(after.totalHeight, before.totalHeight, accuracy: 0.1)
        XCTAssertEqual(after.totalHeight - after.flowY - after.flowHeight, after.sectionGap, accuracy: 0.1)
    }

    func testLargerSummaryKeepsMinimumDiagramSizeOnCompactScreens() {
        let m = SolarOverviewMetrics(viewportHeight: 598, summaryHeight: 234, statusHeight: 17)
        XCTAssertEqual(m.totalHeight, 618, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(m.flowHeight, 300)
        let preview = SolarOverviewMetrics(viewportHeight: 598, summaryHeight: 254, statusHeight: 17)
        XCTAssertEqual(preview.flowHeight, 300)
        XCTAssertGreaterThan(preview.totalHeight, 598)
    }

    func testReadableConsumptionKeepsLargeScreenBottomMargin() {
        let m = SolarOverviewMetrics(viewportHeight: 763, summaryHeight: 300, statusHeight: 17)
        XCTAssertEqual(m.totalHeight, 763, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(m.flowHeight, 300)
        XCTAssertEqual(m.totalHeight - m.flowY - m.flowHeight, m.sectionGap, accuracy: 0.1)
    }

    func testTallConsumptionReflowsByScrollingNotClippingOrShrinkingDiagram() {
        let m = SolarOverviewMetrics(viewportHeight: 598, summaryHeight: 300, statusHeight: 17)
        XCTAssertEqual(m.flowHeight, 300)
        XCTAssertGreaterThan(m.totalHeight, 598)
        XCTAssertEqual(m.totalHeight - m.flowY - m.flowHeight, m.sectionGap, accuracy: 0.1)
    }
}
