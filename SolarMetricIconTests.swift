import XCTest
import SwiftUI
@testable import NamSolar

final class SolarMetricIconTests: XCTestCase {
    func testExactWebIconNamesAndDistinctChargeDirections() {
        XCTAssertEqual(SolarMetricKind.solar.rawValue, "solar-power")
        XCTAssertEqual(SolarMetricKind.charge.rawValue, "battery-arrow-up")
        XCTAssertEqual(SolarMetricKind.discharge.rawValue, "battery-arrow-down")
        XCTAssertEqual(SolarMetricKind.grid.rawValue, "transmission-tower-import")
        XCTAssertEqual(SolarMetricKind.home.rawValue, "home-lightning-bolt")
        XCTAssertNotEqual(SolarMetricKind.charge.svgPath, SolarMetricKind.discharge.svgPath)
    }

    func testAllWebPathsDecodeAndStayWithinThe24PointViewbox() throws {
        for kind in SolarMetricKind.allCases {
            let path = try XCTUnwrap(SolarMetricPath.parse(kind.svgPath), kind.rawValue)
            XCTAssertFalse(path.isEmpty)
            let box = path.boundingBoxOfPath
            XCTAssertGreaterThanOrEqual(box.minX, 0)
            XCTAssertGreaterThanOrEqual(box.minY, 0)
            XCTAssertLessThanOrEqual(box.maxX, 24)
            XCTAssertLessThanOrEqual(box.maxY, 24)
            XCTAssertGreaterThanOrEqual(box.width, 10)
            XCTAssertGreaterThanOrEqual(box.height, 17)
        }
    }

    func testVectorScalingPreservesAspectRatioAndDoesNotClip() {
        for kind in SolarMetricKind.allCases {
            for rect in [CGRect(x: 0, y: 0, width: 18, height: 18), CGRect(x: 5, y: 9, width: 36, height: 18)] {
                let box = SolarMetricShape(kind: kind).path(in: rect).boundingRect
                XCTAssertTrue(rect.contains(box), kind.rawValue)
                XCTAssertEqual(box.width / box.height, kind.path.boundingBoxOfPath.width / kind.path.boundingBoxOfPath.height, accuracy: 0.001)
            }
        }
    }

    func testUnsupportedOrIncompleteCommandsFailWithoutCrashing() {
        for data in ["", "M1", "M1 2C3 4", "M1 2A3 4", "garbage", "Mnan 2"] {
            XCTAssertNil(SolarMetricPath.parse(data))
        }
    }
}
