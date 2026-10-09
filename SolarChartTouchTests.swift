import XCTest
import UIKit
@testable import NamSolar

final class SolarChartTouchTests: XCTestCase {
    @MainActor func testHoldStartsBeforeDraggingAndAllowsNormalFingerJitter() {
        let view = SolarChartTouchView()
        XCTAssertEqual(view.holdRecognizer.minimumPressDuration, 0.18, accuracy: 0.001)
        XCTAssertEqual(view.holdRecognizer.allowableMovement, 18)
        XCTAssertEqual(view.holdRecognizer.numberOfTouchesRequired, 1)
        XCTAssertEqual(view.doubleTapRecognizer.numberOfTapsRequired, 2)
        XCTAssertTrue(view.holdRecognizer.delegate === view)
        XCTAssertTrue(view.pinchRecognizer.delegate === view)
        XCTAssertEqual(view.gestureRecognizers?.count, 5)
        XCTAssertFalse(view.panRecognizer.isEnabled)
        XCTAssertEqual(view.panRecognizer.minimumNumberOfTouches, 1)
        XCTAssertEqual(view.panRecognizer.maximumNumberOfTouches, 1)
    }

    @MainActor func testHoldAndPinchTakePriorityOnlyOverAncestorScrolling() {
        let outer = UIScrollView()
        let inner = UIScrollView()
        let view = SolarChartTouchView()
        outer.addSubview(inner)
        inner.addSubview(view)
        for scroll in [inner, outer] {
            XCTAssertTrue(view.gestureRecognizer(view.holdRecognizer, shouldBeRequiredToFailBy: scroll.panGestureRecognizer))
            XCTAssertTrue(view.gestureRecognizer(view.pinchRecognizer, shouldBeRequiredToFailBy: scroll.panGestureRecognizer))
            XCTAssertTrue(view.gestureRecognizer(view.panRecognizer, shouldBeRequiredToFailBy: scroll.panGestureRecognizer))
            XCTAssertFalse(view.gestureRecognizer(view.tapRecognizer, shouldBeRequiredToFailBy: scroll.panGestureRecognizer))
        }
    }

    @MainActor func testPanRejectsVerticalDiagonalAndNonFiniteMovement() {
        XCTAssertTrue(SolarChartTouchView.isHorizontal(CGPoint(x: -100, y: 10)))
        XCTAssertTrue(SolarChartTouchView.isHorizontal(CGPoint(x: 100, y: -10)))
        XCTAssertFalse(SolarChartTouchView.isHorizontal(CGPoint(x: 10, y: 100)))
        XCTAssertFalse(SolarChartTouchView.isHorizontal(CGPoint(x: 100, y: 100)))
        XCTAssertFalse(SolarChartTouchView.isHorizontal(.zero))
        XCTAssertFalse(SolarChartTouchView.isHorizontal(CGPoint(x: CGFloat.nan, y: 0)))
    }

    @MainActor func testUnrelatedScrollingAndButtonsKeepTheirOwnGestures() {
        let view = SolarChartTouchView()
        let unrelated = UIScrollView()
        XCTAssertFalse(view.gestureRecognizer(view.holdRecognizer, shouldBeRequiredToFailBy: unrelated.panGestureRecognizer))
        XCTAssertFalse(view.gestureRecognizer(view.holdRecognizer, shouldBeRequiredToFailBy: UITapGestureRecognizer()))
        XCTAssertFalse(view.gestureRecognizer(view.holdRecognizer, shouldBeRequiredToFailBy: view.pinchRecognizer))
    }

    @MainActor func testInspectionTracksAndClampsActualFingerCoordinates() {
        let view = SolarChartTouchView()
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 80)
        var positions: [CGFloat] = []
        view.onSelect = { positions.append($0) }
        let coordinates: [CGFloat] = [-40, 20, 80, 17, 140, .nan, .infinity]
        for x in coordinates { view.inspect(at: x) }
        XCTAssertEqual(positions, [0, 20, 80, 17, 100])
    }
}
