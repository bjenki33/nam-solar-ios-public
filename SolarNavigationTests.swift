import XCTest
import SwiftUI
import UIKit
@testable import NamSolar

final class SolarNavigationTests: XCTestCase {
    func testTabsUseExactWebIconsRatherThanSFSymbols() {
        XCTAssertEqual(SolarTab.overview.icon.rawValue, "solar-power")
        XCTAssertEqual(SolarTab.battery.icon.rawValue, "battery-heart-variant")
        XCTAssertEqual(SolarTab.history.icon.rawValue, "chart-line")
        XCTAssertEqual(SolarTab.diagnostics.icon.rawValue, "lan-check")
        XCTAssertEqual(SolarNavigationKind.overview.svgPath, SolarMetricKind.solar.svgPath)
        XCTAssertEqual(Set(SolarNavigationKind.allCases.map(\.svgPath)).count, 4)
    }

    func testAllNavigationPathsDecodeWithinTheirViewboxAndScaleWithoutClipping() throws {
        for kind in SolarNavigationKind.allCases {
            let path = try XCTUnwrap(SolarMetricPath.parse(kind.svgPath), kind.rawValue)
            XCTAssertFalse(path.isEmpty)
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 24, height: 24).contains(path.boundingBoxOfPath))
            for rect in [CGRect(x: 0, y: 0, width: 25, height: 25), CGRect(x: 7, y: 5, width: 50, height: 25)] {
                let scaled = SolarNavigationShape(kind: kind).path(in: rect).boundingRect
                XCTAssertTrue(rect.contains(scaled))
                XCTAssertEqual(scaled.width / scaled.height, path.boundingBoxOfPath.width / path.boundingBoxOfPath.height, accuracy: 0.001)
            }
        }
    }

    func testBatteryHeartAndComputerScreenCutoutsRemainVisible() {
        let battery = SolarNavigationKind.battery.path
        XCTAssertTrue(battery.contains(CGPoint(x: 7, y: 12)))
        XCTAssertFalse(battery.contains(CGPoint(x: 12, y: 12)), "Heart must be inside the battery, not an external badge")
        let computers = SolarNavigationKind.diagnostics.path
        XCTAssertTrue(computers.contains(CGPoint(x: 3, y: 4)))
        XCTAssertFalse(computers.contains(CGPoint(x: 7, y: 5)))
        XCTAssertFalse(computers.contains(CGPoint(x: 17, y: 17)))
    }

    func testSVGArcFlagsDegenerateRadiiAndRotations() throws {
        for flags in ["0 0", "0 1", "1 0", "1 1"] {
            let path = try XCTUnwrap(SolarMetricPath.parse("M10 0A10 10 0 \(flags) 0 10"))
            XCTAssertEqual(path.currentPoint.x, 0, accuracy: 0.001)
            XCTAssertEqual(path.currentPoint.y, 10, accuracy: 0.001)
            XCTAssertTrue(path.boundingBoxOfPath.width.isFinite)
            XCTAssertTrue(path.boundingBoxOfPath.height.isFinite)
        }
        let rotated = try XCTUnwrap(SolarMetricPath.parse("M10 0A5 3 45 0 1 0 10"))
        XCTAssertEqual(rotated.currentPoint.x, 0, accuracy: 0.001)
        XCTAssertEqual(rotated.currentPoint.y, 10, accuracy: 0.001)
        let line = try XCTUnwrap(SolarMetricPath.parse("M0 0A0 10 0 0 1 5 6"))
        XCTAssertEqual(line.currentPoint, CGPoint(x: 5, y: 6))
        let same = try XCTUnwrap(SolarMetricPath.parse("M5 6A10 10 0 0 1 5 6L7 8"))
        XCTAssertEqual(same.currentPoint, CGPoint(x: 7, y: 8))
        for input in ["M1 2A3 4", "M1 2A3 4 0 2 1 5 6", "M1 2A3 4 0 0 -1 5 6"] {
            XCTAssertNil(SolarMetricPath.parse(input))
        }
    }

    func testLabelsAreLargerAndFitEvenTheSmallestPhoneHeader() {
        XCTAssertGreaterThanOrEqual(SolarNavigationLayout.labelSize, 12)
        XCTAssertGreaterThanOrEqual(SolarNavigationLayout.iconSize, 24)
        let columnWidth = (CGFloat(320) - SolarNavigationLayout.brandWidth - SolarNavigationLayout.accountWidth) / 4
        for tab in SolarTab.allCases {
            let width = (tab.rawValue as NSString).size(withAttributes: [
                .font: UIFont.systemFont(ofSize: SolarNavigationLayout.labelSize, weight: .medium)
            ]).width
            XCTAssertLessThanOrEqual(width, columnWidth - 2)
        }
    }

    func testDisplayedVersionComesFromBundleAndChangesWithFutureReleases() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let version = try XCTUnwrap(info["CFBundleShortVersionString"] as? String)
        let build = try XCTUnwrap(info["CFBundleVersion"] as? String)
        XCTAssertEqual(SolarAppVersion.current, "\(version) (\(build))")
        XCTAssertEqual(SolarAppVersion.description(info: ["CFBundleShortVersionString": "9.8.7", "CFBundleVersion": "123"]), "9.8.7 (123)")
        XCTAssertEqual(SolarAppVersion.description(info: ["CFBundleShortVersionString": "9.8.7"]), "9.8.7")
        XCTAssertEqual(SolarAppVersion.description(info: [:]), "--")
    }
}
