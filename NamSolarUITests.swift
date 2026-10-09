import XCTest
import UIKit

final class NamSolarUITests: XCTestCase {
    func testLoginScreenAndLandscape() {
        let app = XCUIApplication()
        app.launch()
        let login = app.buttons["Đăng nhập Nam Solar"]
        XCTAssertTrue(login.waitForExistence(timeout: 10))
        XCTAssertTrue(login.isHittable)
        XCTAssertTrue(app.staticTexts["Chỉ theo dõi. Không điều khiển biến tần."].exists)
        saveScreenshot("NamSolar-login-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        saveScreenshot("NamSolar-login-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    private func saveScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertEnergyColumnsReachBaseline(_ app: XCUIApplication, plot: XCUIElement) {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return XCTFail("Missing screenshot") }
        let screen = app.windows.firstMatch.frame
        let frame = plot.frame
        let scaleX = CGFloat(image.width) / screen.width
        let scaleY = CGFloat(image.height) / screen.height
        // Synthetic consumption is positive on all seven days. Test the body, not just each column's top edge.
        for x in [1.5 / 7, 3.5 / 7, 5.5 / 7] {
            for y in [0.45, 0.72, 0.93] {
                let pixel = CGRect(x: floor((frame.minX + frame.width * x) * scaleX),
                                   y: floor((frame.minY + frame.height * y) * scaleY), width: 1, height: 1)
                guard let sample = image.cropping(to: pixel) else { XCTFail("Plot outside screenshot"); continue }
                var rgba = [UInt8](repeating: 0, count: 4)
                let rendered = rgba.withUnsafeMutableBytes { bytes -> Bool in
                    guard let context = CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                        bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                    context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                    return true
                }
                XCTAssertTrue(rendered)
                XCTAssertTrue(Double(rgba[1]) > Double(rgba[0]) * 1.6 && rgba[1] > rgba[2] && rgba[1] > 70,
                              "Energy must render a filled column from zero; floating horizontal marks are incorrect")
            }
        }
    }

    private func revealOverviewBattery(in app: XCUIApplication) {
        let battery = app.buttons["Chi tiết pin lưu trữ"]
        for _ in 0..<4 {
            if battery.isHittable && battery.frame.maxY <= app.windows.firstMatch.frame.maxY { return }
            app.swipeUp()
        }
    }

    private func chartDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy HH:mm:ss"
        return formatter.date(from: text.replacingOccurrences(of: "Thời điểm ", with: "")
            .replacingOccurrences(of: " · ", with: " "))
    }

    private func assertChartSelection(_ app: XCUIApplication, fraction: Double, selected: Date? = nil,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let bounds = app.staticTexts["chart-visible-range"].label.components(separatedBy: " → ")
        guard bounds.count == 2, let low = chartDate(bounds[0]), let high = chartDate(bounds[1]),
              let date = selected ?? chartDate(app.staticTexts["chart-selected-time"].label) else {
            XCTFail("Missing readable chart time/range", file: file, line: line)
            return
        }
        let actual = date.timeIntervalSince(low) / high.timeIntervalSince(low)
        XCTAssertEqual(actual, fraction, accuracy: 0.025,
                       "The cursor must reach the finger's final position, not just touch-down", file: file, line: line)
    }

    private func scrubChart(_ app: XCUIApplication, plot: XCUIElement) {
        let frame = plot.frame
        let left = plot.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45))
        left.press(forDuration: 0.45)
        XCTAssertTrue(app.staticTexts["chart-selected-time"].waitForExistence(timeout: 5))
        assertChartSelection(app, fraction: 0.2)
        let right = plot.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.55))
        left.press(forDuration: 0.45, thenDragTo: right)
        assertChartSelection(app, fraction: 0.8)
        right.press(forDuration: 0.45, thenDragTo: left)
        assertChartSelection(app, fraction: 0.2)
        XCTAssertEqual(plot.frame.minY, frame.minY, accuracy: 2, "Holding must not scroll the chart away")
        XCTAssertEqual(plot.frame.width, frame.width, accuracy: 2)
    }

    func testFourDashboardTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["Chi tiết pin lưu trữ"].waitForExistence(timeout: 10))
        revealOverviewBattery(in: app)
        XCTAssertTrue(app.buttons["Chi tiết pin lưu trữ"].isHittable)
        XCTAssertLessThanOrEqual(app.buttons["Chi tiết pin lưu trữ"].frame.maxY, app.windows.firstMatch.frame.maxY, "Battery diagram must not be clipped below the screen")
        XCTAssertTrue(app.buttons["Chi tiết điện lưới"].isHittable)
        XCTAssertTrue(app.staticTexts["Sản lượng PV"].exists)
        XCTAssertTrue(app.staticTexts["Dữ liệu kiểm thử"].exists)
        saveScreenshot("NamSolar-overview")
        app.buttons["Pin"].tap()
        XCTAssertTrue(app.staticTexts["Pin RPT · 16,08 kWh"].waitForExistence(timeout: 5))
        saveScreenshot("NamSolar-battery")
        app.buttons["Lịch sử"].tap()
        for _ in 0..<12 { if app.staticTexts["Công suất · 2 giờ"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Công suất · 2 giờ"].waitForExistence(timeout: 5))
        saveScreenshot("NamSolar-history")
        app.buttons["Hệ thống"].tap()
        XCTAssertTrue(app.staticTexts["Kết nối trực tiếp"].waitForExistence(timeout: 5))
        saveScreenshot("NamSolar-diagnostics")
    }

    func testLargerWebNavigationCenteredBrandAndCurrentVersionFooter() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview", "--ui-layout-clean"]
        app.launch()
        let nam = app.staticTexts["brand-nam"]
        let solar = app.staticTexts["brand-solar"]
        XCTAssertTrue(nam.waitForExistence(timeout: 10))
        XCTAssertTrue(solar.exists)
        XCTAssertEqual(nam.label, "NAM")
        XCTAssertEqual(solar.label, "SOLAR")
        XCTAssertEqual(nam.frame.midX, solar.frame.midX, accuracy: 0.5)
        XCTAssertLessThan(nam.frame.maxY, solar.frame.minY + 1)
        let items = [("Tổng quan", "solar-power"), ("Pin", "battery-heart-variant"),
                     ("Lịch sử", "chart-line"), ("Hệ thống", "lan-check")]
        var lastFrame = solar.frame
        for (title, icon) in items {
            let button = app.buttons[title]
            let label = app.staticTexts["tab-label-" + icon]
            XCTAssertTrue(button.isHittable)
            XCTAssertTrue(label.exists)
            XCTAssertEqual(label.label, title)
            XCTAssertGreaterThanOrEqual(label.frame.height, 14, "Tab labels must not retain the former 9pt font")
            // Accessibility button frames round through Float; text frames retain Double precision.
            XCTAssertGreaterThanOrEqual(label.frame.minX + 0.01, button.frame.minX)
            XCTAssertLessThanOrEqual(label.frame.maxX, button.frame.maxX + 0.01)
            XCTAssertGreaterThan(label.frame.minX, lastFrame.maxX)
            lastFrame = label.frame
        }
        saveScreenshot("NamSolar-web-navigation-centered-brand")
        app.buttons["Hệ thống"].tap()
        let footer = app.staticTexts["app-version-footer"]
        for _ in 0..<8 { if footer.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(footer.isHittable)
        XCTAssertTrue(footer.label.contains("Nam Solar 1.4.3 (14)"))
        XCTAssertFalse(footer.label.contains("Nam Solar 1.1 "))
        saveScreenshot("NamSolar-current-version-footer")
    }

    func testDiagramNavigationAndSourceNote() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"]
        app.launch()
        let battery = app.buttons["Chi tiết pin lưu trữ"]
        XCTAssertTrue(battery.waitForExistence(timeout: 10))
        revealOverviewBattery(in: app)
        battery.tap()
        XCTAssertTrue(app.staticTexts["Pin RPT · 16,08 kWh"].waitForExistence(timeout: 5))
        app.buttons["Tổng quan"].tap()
        app.buttons["Cách ước tính nguồn tiêu thụ"].tap()
        XCTAssertTrue(app.alerts["Nguồn tiêu thụ ước tính"].waitForExistence(timeout: 5))
        app.alerts.buttons["Đóng"].tap()
        app.buttons["Chi tiết điện lưới"].tap()
        XCTAssertTrue(app.staticTexts["Điện lưới"].waitForExistence(timeout: 5))
        saveScreenshot("NamSolar-grid-detail")
    }

    func testBalancedOverviewMarginsWithoutDebugBanner() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview", "--ui-layout-clean"]
        app.launch()
        let battery = app.buttons["Chi tiết pin lưu trữ"]
        XCTAssertTrue(battery.waitForExistence(timeout: 10))
        let pvTile = app.descendants(matching: .any)["daily-pv"].firstMatch
        XCTAssertTrue(pvTile.exists)
        // Accessibility reports the card's contents inside its 7-point top padding.
        let gap = pvTile.frame.minY - 7 - app.buttons["Tổng quan"].frame.maxY
        XCTAssertGreaterThanOrEqual(gap, 10, "Data cards need breathing room below navigation")
        XCTAssertLessThanOrEqual(gap, 16, "Navigation must not leave an excessive empty band")
        let flow = app.descendants(matching: .any)["energy-flow"].firstMatch
        XCTAssertTrue(flow.exists)
        let summary = app.descendants(matching: .any)["daily-summary"].firstMatch
        XCTAssertTrue(summary.exists)
        XCTAssertGreaterThanOrEqual(pvTile.frame.height, 54, "Larger metric type and row spacing must be retained")
        XCTAssertGreaterThanOrEqual(summary.frame.height, 215, "Summary cards must have more visual weight")
        XCTAssertLessThanOrEqual(flow.frame.height, summary.frame.height * 2.25, "Diagram must not stretch disproportionately below the summary")
        // Short screens keep readable type and scroll, rather than shrink or clip.
        if flow.frame.maxY > app.windows.firstMatch.frame.maxY - 14 { app.swipeUp() }
        let screen = app.windows.firstMatch.frame
        let bottomGap = screen.maxY - flow.frame.maxY
        XCTAssertGreaterThanOrEqual(bottomGap, 14, "Diagram must retain a visible bottom margin")
        XCTAssertLessThanOrEqual(bottomGap, 18, "Bottom margin must not leave the diagram floating")
        XCTAssertLessThanOrEqual(battery.frame.maxY, flow.frame.maxY, "Battery must stay inside the diagram")
        XCTAssertTrue(battery.isHittable)
        XCTAssertFalse(app.staticTexts["Dữ liệu kiểm thử"].exists)
        saveScreenshot("NamSolar-overview-balanced-test-data")
    }

    func testConsumptionNumbersAndLabelsMatchUpperCardsWithoutShrinking() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview", "--ui-layout-clean"]
        app.launch()
        let reference = app.staticTexts["daily-pv-today-value"]
        XCTAssertTrue(reference.waitForExistence(timeout: 10))
        let referenceTitle = app.staticTexts["daily-pv-title"]
        let panel = app.descendants(matching: .any)["consumption-panel"].firstMatch
        XCTAssertTrue(panel.exists)
        XCTAssertGreaterThanOrEqual(reference.frame.height, 20)
        let expected = [("today", "≈ 9,10"), ("total", "≈ 677,80"),
                        ("pv", "≈ 7,30"), ("battery", "≈ 1,80"), ("grid", "≈ 0,00")]
        for (key, value) in expected {
            let number = app.staticTexts["consumption-" + key + "-value"]
            let title = app.staticTexts["consumption-" + key + "-title"]
            let unit = app.staticTexts["consumption-" + key + "-unit"]
            XCTAssertTrue(number.exists)
            XCTAssertEqual(number.label, value, "Typography changes must not change calculations")
            XCTAssertEqual(number.frame.height, reference.frame.height, accuracy: 1, "Consumption numbers must be as large as PV")
            XCTAssertGreaterThanOrEqual(title.frame.height, referenceTitle.frame.height - 2, "Consumption labels must match upper card titles")
            XCTAssertTrue(unit.exists)
            XCTAssertEqual(unit.label, "kWh")
            XCTAssertGreaterThanOrEqual(unit.frame.height, 11)
            for element in [number, title, unit] {
                XCTAssertTrue(element.isHittable)
                XCTAssertGreaterThanOrEqual(element.frame.minX, panel.frame.minX - 1)
                XCTAssertLessThanOrEqual(element.frame.maxX, panel.frame.maxX + 1)
                XCTAssertGreaterThanOrEqual(element.frame.minY, panel.frame.minY - 1)
                XCTAssertLessThanOrEqual(element.frame.maxY, panel.frame.maxY + 1)
            }
        }
        saveScreenshot("NamSolar-readable-consumption-test-data")
    }

    func testConsumptionHeaderHasThreeEqualColumnsAlignedWithSources() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview", "--ui-layout-clean"]
        app.launch()
        XCTAssertTrue(app.staticTexts["consumption-today-value"].waitForExistence(timeout: 10))
        func readingFrame(_ key: String) -> CGRect {
            app.staticTexts["consumption-" + key + "-value"].frame
                .union(app.staticTexts["consumption-" + key + "-unit"].frame)
        }
        let sourceKeys = ["pv", "battery", "grid"]
        let centers = sourceKeys.map { readingFrame($0).midX }
        let width = (app.windows.firstMatch.frame.width - 32) / 3
        XCTAssertEqual(centers[1] - centers[0], width, accuracy: 1)
        XCTAssertEqual(centers[2] - centers[1], width, accuracy: 1)
        for (index, key) in ["today", "total"].enumerated() {
            let center = centers[index + 1]
            let title = app.staticTexts["consumption-" + key + "-title"]
            XCTAssertEqual(title.frame.midX, center, accuracy: 1, "Header and source column centers must align")
            XCTAssertEqual(readingFrame(key).midX, center, accuracy: 1)
            for element in [title, app.staticTexts["consumption-" + key + "-value"],
                            app.staticTexts["consumption-" + key + "-unit"]] {
                XCTAssertTrue(element.isHittable)
                XCTAssertGreaterThanOrEqual(element.frame.minX, center - width / 2 + 2)
                XCTAssertLessThanOrEqual(element.frame.maxX, center + width / 2 - 2)
            }
        }
        for element in [app.staticTexts["consumption-heading"], app.buttons["Cách ước tính nguồn tiêu thụ"]] {
            XCTAssertTrue(element.isHittable)
            XCTAssertGreaterThanOrEqual(element.frame.minX, centers[0] - width / 2 + 2)
            XCTAssertLessThanOrEqual(element.frame.maxX, centers[0] + width / 2 - 2)
        }
        saveScreenshot("NamSolar-three-column-consumption-test-data")
    }

    func testAllDeviceIconsShowTheirOwnPowerAndZoomableHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview", "--ui-layout-clean"]
        app.launch()
        XCTAssertTrue(app.buttons["Chi tiết biến tần"].waitForExistence(timeout: 10))
        let devices = [
            ("Chi tiết biến tần", "inverter", "Lux inverter power", "sensor.lux_inverter_power", "1.577 W"),
            ("Chi tiết công suất nhà", "home", "Lux home power", "sensor.lux_home_power", "1.578 W"),
            ("Chi tiết điện lưới", "grid", "Lux grid power", "sensor.lux_grid_power", "0 W"),
            ("Chi tiết điện mặt trời", "solar", "Lux PV power", "sensor.lux_pv_power", "1.820 W")
        ]
        for (button, id, sensor, entity, watts) in devices {
            app.buttons[button].tap()
            XCTAssertTrue(app.staticTexts[sensor].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["Pin RPT · 16,08 kWh"].exists, "Inverter and power icons must not open the battery tab")
            let current = app.descendants(matching: .any)["device-current-power"].firstMatch
            XCTAssertTrue(current.exists)
            XCTAssertEqual(current.value as? String, watts)
            XCTAssertTrue(app.descendants(matching: .any)["device-history-" + id].firstMatch.exists)
            let plot = app.descendants(matching: .any)["chart-plot-W"].firstMatch
            XCTAssertTrue(plot.waitForExistence(timeout: 10))
            for _ in 0..<4 {
                if plot.isHittable && plot.frame.maxY < app.windows.firstMatch.frame.maxY - 20 { break }
                app.swipeUp()
            }
            XCTAssertTrue(plot.isHittable)
            saveScreenshot("NamSolar-device-" + id + "-history-test-data")
            plot.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45)).press(forDuration: 0.45)
            XCTAssertTrue(app.staticTexts["chart-compact-selected-time"].waitForExistence(timeout: 5))
            let compactHold = chartDate(app.staticTexts["chart-compact-selected-time"].label)
            XCTAssertNotNil(compactHold, "Hold without dragging must immediately show the time")
            plot.doubleTap()
            XCTAssertTrue(app.buttons["Đóng biểu đồ"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["chart-value-" + entity].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["chart-value-" + entity].label.contains("W"))
            XCTAssertTrue(app.staticTexts["chart-selected-time"].exists)
            assertChartSelection(app, fraction: 0.2, selected: compactHold)
            let expandedPlot = app.descendants(matching: .any)["chart-expanded-plot-W"].firstMatch
            XCTAssertTrue(expandedPlot.waitForExistence(timeout: 5))
            scrubChart(app, plot: expandedPlot)
            app.buttons["Phóng to trục thời gian"].tap()
            XCTAssertEqual(Double(app.staticTexts["chart-zoom-level"].value as? String ?? "0") ?? 0, 2, accuracy: 0.05)
            scrubChart(app, plot: expandedPlot)
            saveScreenshot("NamSolar-device-" + id + "-zoom-test-data")
            app.buttons["Đóng biểu đồ"].tap()
            app.buttons["close-device-detail"].tap()
            XCTAssertTrue(app.buttons["Tổng quan"].waitForExistence(timeout: 5))
        }
        app.buttons["Tổng công suất PV"].tap()
        XCTAssertTrue(app.staticTexts["Lux PV power"].waitForExistence(timeout: 5))
        app.buttons["Tải lại lịch sử"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["chart-plot-W"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["close-device-detail"].tap()
        app.buttons["Chi tiết pin lưu trữ"].tap()
        XCTAssertTrue(app.staticTexts["Pin RPT · 16,08 kWh"].waitForExistence(timeout: 5))
    }

    func testPowerChartDoubleTapZoomPinchAndTimeInspection() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"]
        app.launch()
        app.buttons["Lịch sử"].tap()
        let plot = app.descendants(matching: .any)["chart-plot-W"].firstMatch
        for _ in 0..<12 { if plot.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(plot.waitForExistence(timeout: 10))
        XCTAssertTrue(plot.isHittable)
        plot.doubleTap()
        XCTAssertTrue(app.buttons["Đóng biểu đồ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["chart-selected-time"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["chart-value-sensor.lux_battery_power"].label, "240 W")

        let expandedPlot = app.descendants(matching: .any)["chart-expanded-plot-W"].firstMatch
        XCTAssertTrue(expandedPlot.waitForExistence(timeout: 5))
        expandedPlot.doubleTap()
        let zoom = app.staticTexts["chart-zoom-level"]
        XCTAssertEqual(Double(zoom.value as? String ?? "0") ?? 0, 2, accuracy: 0.05)
        expandedPlot.pinch(withScale: 2, velocity: 1)
        XCTAssertGreaterThan(Double(zoom.value as? String ?? "0") ?? 0, 2.1)
        let range = app.staticTexts["chart-visible-range"].label
        app.buttons["Mốc sau"].tap()
        XCTAssertNotEqual(app.staticTexts["chart-visible-range"].label, range)
        app.buttons["Đặt lại biểu đồ"].tap()
        XCTAssertEqual(Double(zoom.value as? String ?? "0") ?? 0, 1, accuracy: 0.05)

        expandedPlot.tap()
        XCTAssertTrue(app.staticTexts["chart-selected-time"].waitForExistence(timeout: 5))
        let selectedTime = app.staticTexts["chart-selected-time"].label
        let start = expandedPlot.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4))
        let end = expandedPlot.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.4))
        start.press(forDuration: 0.3, thenDragTo: end)
        XCTAssertNotEqual(app.staticTexts["chart-selected-time"].label, selectedTime)
        assertChartSelection(app, fraction: 0.8)
        saveScreenshot("NamSolar-power-chart-inspection-test-data")

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["Đóng biểu đồ"].isHittable)
        saveScreenshot("NamSolar-power-chart-landscape-test-data")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["Đóng biểu đồ"].tap()
        app.buttons["Tổng quan"].tap()
        revealOverviewBattery(in: app)
        XCTAssertTrue(app.buttons["Chi tiết pin lưu trữ"].isHittable)
    }

    func testDeviceReadingsAppearWhileHistoryIsDeliberatelySlow() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview", "--ui-layout-clean", "--ui-history-slow"]
        app.launch()
        XCTAssertTrue(app.buttons["Chi tiết biến tần"].waitForExistence(timeout: 10))
        let devices = [("Chi tiết biến tần", "inverter", "1.577 W"),
                       ("Chi tiết công suất nhà", "home", "1.578 W"),
                       ("Chi tiết điện lưới", "grid", "0 W"),
                       ("Chi tiết điện mặt trời", "solar", "1.820 W")]
        for (button, id, watts) in devices {
            app.buttons[button].tap()
            let current = app.descendants(matching: .any)["device-current-power"].firstMatch
            XCTAssertTrue(current.waitForExistence(timeout: 2), "Current power must not wait for 24-hour history")
            XCTAssertEqual(current.value as? String, watts)
            XCTAssertTrue(app.descendants(matching: .any)["device-history-loading"].firstMatch.exists)
            XCTAssertFalse(app.descendants(matching: .any)["chart-plot-W"].firstMatch.exists,
                           "This fixture must really be waiting for history, not immediately return a fake chart")
            if id == "inverter" { saveScreenshot("NamSolar-immediate-inverter-history-still-loading-test-data") }
            XCTAssertTrue(app.descendants(matching: .any)["chart-plot-W"].firstMatch.waitForExistence(timeout: 12))
            XCTAssertEqual(current.value as? String, watts)
            app.buttons["close-device-detail"].tap()
        }
    }

    func testBatteryChargePositiveDischargeNegativeInOverviewAndBothChartSizes() {
        for discharging in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-preview", "--ui-layout-clean"]
            if discharging { app.launchArguments.append("--ui-battery-discharge") }
            app.launch()
            let battery = app.buttons["Chi tiết pin lưu trữ"]
            XCTAssertTrue(battery.waitForExistence(timeout: 10))
            revealOverviewBattery(in: app)
            let watts = discharging ? "-240 W" : "240 W"
            let status = discharging ? "Đang xả" : "Đang sạc"
            XCTAssertEqual(battery.value as? String, watts + " · " + status)
            XCTAssertTrue(battery.isHittable)
            let mode = discharging ? "discharging-negative" : "charging-positive"
            saveScreenshot("NamSolar-battery-" + mode + "-overview-test-data")

            app.buttons["Lịch sử"].tap()
            let plot = app.descendants(matching: .any)["chart-plot-W"].firstMatch
            for _ in 0..<12 { if plot.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(plot.waitForExistence(timeout: 10))
            XCTAssertTrue(plot.isHittable)
            plot.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45)).press(forDuration: 0.45)
            let compactValue = app.staticTexts["chart-compact-value-sensor.lux_battery_power"]
            XCTAssertTrue(compactValue.waitForExistence(timeout: 5))
            XCTAssertEqual(compactValue.label, watts)
            plot.doubleTap()
            XCTAssertTrue(app.buttons["Đóng biểu đồ"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["chart-value-sensor.lux_battery_power"].label, watts)
            let expanded = app.descendants(matching: .any)["chart-expanded-plot-W"].firstMatch
            scrubChart(app, plot: expanded)
            XCTAssertEqual(app.staticTexts["chart-value-sensor.lux_battery_power"].label, watts)
            saveScreenshot("NamSolar-battery-" + mode + "-history-test-data")
            app.terminate()
        }
    }

    func testEnergyDayAndInclusiveRangeChartsAndDateControls() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"]
        app.launch()
        app.buttons["Lịch sử"].tap()
        XCTAssertTrue(app.buttons["energy-yesterday"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["energy-from-date"].firstMatch.exists)
        app.buttons["energy-yesterday"].tap()
        XCTAssertTrue(app.staticTexts["Điện năng từng giờ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["energy-total-pv"].exists)
        XCTAssertFalse(app.staticTexts["energy-total-pv"].label.contains("--"))
        let dayLabel = app.staticTexts["energy-loaded-range"].label
        XCTAssertFalse(dayLabel.contains(" – "))
        saveScreenshot("NamSolar-energy-day-controls-test-data")
        app.buttons["energy-last-seven"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["energy-through-date"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Điện năng từng ngày"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["energy-loaded-range"].label.contains(" – "))
        saveScreenshot("NamSolar-energy-range-controls-test-data")
        let expand = app.buttons["Phóng to điện năng"]
        for _ in 0..<6 { if expand.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(expand.isHittable)
        saveScreenshot("NamSolar-energy-range-chart-test-data")
        expand.tap()
        let plot = app.descendants(matching: .any)["energy-expanded-plot"].firstMatch
        XCTAssertTrue(plot.waitForExistence(timeout: 5))
        assertEnergyColumnsReachBaseline(app, plot: plot)
        let left = plot.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let right = plot.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        left.press(forDuration: 0.4)
        XCTAssertTrue(app.staticTexts["energy-selected-time"].waitForExistence(timeout: 5))
        let selected = app.staticTexts["energy-selected-time"].label
        left.press(forDuration: 0.4, thenDragTo: right)
        XCTAssertNotEqual(app.staticTexts["energy-selected-time"].label, selected)
        XCTAssertEqual(app.staticTexts.matching(identifier: "energy-selected-consumption").count, 1)
        XCTAssertTrue(app.staticTexts["energy-selected-consumption"].label.contains("kWh"))
        XCTAssertLessThan(app.staticTexts["energy-selected-consumption"].frame.maxY, plot.frame.minY)
        plot.doubleTap()
        right.press(forDuration: 0.4)
        let zoomedDate = app.staticTexts["energy-selected-time"].label
        plot.swipeRight()
        right.press(forDuration: 0.4)
        XCTAssertNotEqual(app.staticTexts["energy-selected-time"].label, zoomedDate)
        app.buttons["energy-reset-chart"].tap()
        saveScreenshot("NamSolar-energy-expanded-inspection-test-data")
        app.buttons["energy-close-chart"].tap()
        let table = app.descendants(matching: .any)["energy-detail-table"].firstMatch
        for _ in 0..<5 { if table.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(table.isHittable)
        table.tap()
        let drill = app.buttons.matching(NSPredicate(format: "label == %@", "Xem ngày")).firstMatch
        XCTAssertTrue(drill.waitForExistence(timeout: 5))
        if !drill.isHittable { app.swipeUp() }
        XCTAssertTrue(drill.isHittable)
        drill.tap()
        XCTAssertTrue(app.staticTexts["Điện năng từng giờ"].waitForExistence(timeout: 5))
        // A single-day selection must not retain totals from the previous seven-day range.
        XCTAssertFalse(app.staticTexts["energy-loaded-range"].label.contains(" – "))
    }

    func testEnergyEmptyAndFailedRequestsNeverShowSyntheticZeroTotals() {
        for flag in ["--ui-energy-empty", "--ui-energy-error"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-preview", flag]
            app.launch()
            app.buttons["Lịch sử"].tap()
            let id = flag == "--ui-energy-empty" ? "energy-empty" : "energy-error"
            XCTAssertTrue(app.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["energy-total-pv"].exists)
            XCTAssertFalse(app.staticTexts["energy-total-consumption"].exists)
            if flag == "--ui-energy-error" { XCTAssertTrue(app.buttons["Thử lại"].exists) }
            saveScreenshot("NamSolar" + flag + "-test-data")
            app.terminate()
        }
    }

    func testBatteryPercentAndCellChartsCanBeExpandedAndInspected() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"]
        app.launch()
        app.buttons["Pin"].tap()
        let plot = app.descendants(matching: .any)["chart-plot-%"].firstMatch
        XCTAssertTrue(plot.waitForExistence(timeout: 10))
        for _ in 0..<8 {
            if plot.isHittable && plot.frame.maxY < app.windows.firstMatch.frame.maxY { break }
            app.swipeUp()
        }
        XCTAssertTrue(plot.isHittable)
        let beforeSwipe = plot.frame.minY
        plot.swipeDown(velocity: .fast)
        XCTAssertGreaterThan(plot.frame.minY, beforeSwipe + 20, "A quick swipe on the chart must still scroll its page")
        for _ in 0..<8 {
            if plot.isHittable && plot.frame.maxY < app.windows.firstMatch.frame.maxY { break }
            app.swipeUp()
        }
        XCTAssertTrue(plot.isHittable)
        plot.doubleTap()
        XCTAssertTrue(app.buttons["Đóng biểu đồ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["chart-selected-time"].waitForExistence(timeout: 5))
        let soc = app.staticTexts["chart-value-sensor.lux_battery_soc"]
        XCTAssertTrue(soc.label.contains("%"))
        scrubChart(app, plot: app.descendants(matching: .any)["chart-expanded-plot-%"].firstMatch)
        app.buttons["Phóng to trục thời gian"].tap()
        XCTAssertEqual(Double(app.staticTexts["chart-zoom-level"].value as? String ?? "0") ?? 0, 2, accuracy: 0.05)
        saveScreenshot("NamSolar-SOC-chart-zoom-test-data")
        app.buttons["Đóng biểu đồ"].tap()

        let expandCell = app.buttons["Phóng to Chênh cell · 24 giờ"]
        for _ in 0..<5 {
            if expandCell.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(expandCell.isHittable)
        expandCell.tap()
        XCTAssertTrue(app.buttons["Đóng biểu đồ"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["chart-expanded-plot-mV"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["chart-selected-time"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["chart-value-sensor.lux_cell_delta"].label.contains("64 mV"))
        scrubChart(app, plot: app.descendants(matching: .any)["chart-expanded-plot-mV"].firstMatch)
        saveScreenshot("NamSolar-cell-chart-inspection-test-data")
        app.buttons["Đóng biểu đồ"].tap()
    }

    func testZoomedSOCSwipesPanWithoutChangingZoomAndInspectorStaysAbovePlot() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-preview"]
        app.launch()
        app.buttons["Pin"].tap()
        let open = app.buttons["Phóng to Dung lượng pin · 24 giờ"]
        for _ in 0..<10 { if open.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(open.isHittable)
        open.tap()
        let plot = app.descendants(matching: .any)["chart-expanded-plot-%"].firstMatch
        XCTAssertTrue(plot.waitForExistence(timeout: 5))
        let initialFrame = plot.frame
        plot.tap()
        XCTAssertTrue(app.staticTexts["chart-selected-time"].waitForExistence(timeout: 5))
        XCTAssertLessThan(app.staticTexts["chart-selected-time"].frame.maxY, plot.frame.minY)
        XCTAssertLessThan(app.staticTexts["chart-value-sensor.lux_battery_soc"].frame.maxY, plot.frame.minY)
        XCTAssertEqual(plot.frame.minY, initialFrame.minY, accuracy: 2, "Inspector must reserve its space before touch-down")
        app.buttons["Phóng to trục thời gian"].tap()
        let zoom = app.staticTexts["chart-zoom-level"].value as? String
        let before = app.staticTexts["chart-visible-range"].label
        plot.swipeLeft(velocity: .fast)
        let later = app.staticTexts["chart-visible-range"].label
        XCTAssertNotEqual(later, before, "A fast one-finger horizontal swipe must pan a zoomed chart")
        XCTAssertEqual(app.staticTexts["chart-zoom-level"].value as? String, zoom)
        plot.swipeRight(velocity: .fast)
        XCTAssertNotEqual(app.staticTexts["chart-visible-range"].label, later)
        XCTAssertEqual(app.staticTexts["chart-zoom-level"].value as? String, zoom)
        let beforeScrub = app.staticTexts["chart-visible-range"].label
        scrubChart(app, plot: plot)
        XCTAssertEqual(app.staticTexts["chart-visible-range"].label, beforeScrub, "Hold-and-drag must scrub, not pan")
        XCTAssertLessThan(app.staticTexts["chart-selected-time"].frame.maxY, plot.frame.minY)
        saveScreenshot("NamSolar-SOC-pan-inspector-above-test-data")
        app.buttons["Đặt lại biểu đồ"].tap()
        XCTAssertEqual(Double(app.staticTexts["chart-zoom-level"].value as? String ?? "0") ?? 0, 1, accuracy: 0.01)
    }
}
