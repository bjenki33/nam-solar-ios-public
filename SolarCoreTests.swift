import XCTest
#if canImport(SolarCore)
@testable import SolarCore
#else
@testable import NamSolar
#endif

final class SolarCoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1800000000)
    func snapshot(_ changes: [String: String] = [:], live: Bool = true) -> SolarSnapshot {
        var values = ["local_connection": "online", "bms_connection": "online",
                      "local_last_read": SolarDate.iso(now), "bms_last_read": SolarDate.iso(now),
                      "pv_today": "21", "charge_today": "13.7", "discharge_today": "1.8",
                      "grid_import_today": "0", "grid_export_today": "0"]
        values.merge(changes) { _, value in value }
        let states = Dictionary(uniqueKeysWithValues: values.map { (SolarSnapshot.prefix + $0.key, HAState(entity_id: SolarSnapshot.prefix + $0.key, state: $0.value)) })
        return SolarSnapshot(states: states, now: now, transportLive: live)
    }
    func testConsumptionIncludesLosses() {
        XCTAssertEqual(snapshot().consumption("today"), 9.1)
        XCTAssertEqual(snapshot().estimatedSources, [7.3, 1.8, 0])
    }
    func testMissingAndInvalidAreNotZero() {
        for raw in ["", " ", "unknown", "unavailable", "NaN", "Infinity"] {
            XCTAssertNil(snapshot(["pv_today": raw]).number("pv_today"))
            XCTAssertNil(snapshot(["pv_today": raw]).consumption("today"))
        }
        XCTAssertEqual(snapshot(["pv_today": "0"]).number("pv_today"), 0)
    }
    func testDisconnectedDoesNotShowOldValuesAsLive() {
        XCTAssertNil(snapshot(live: false).number("pv_today"))
        XCTAssertNil(snapshot(["local_last_read": SolarDate.iso(now.addingTimeInterval(-16))]).number("pv_today"))
        XCTAssertNil(snapshot(["local_last_read": SolarDate.iso(now.addingTimeInterval(6))]).number("pv_today"))
        XCTAssertFalse(snapshot(["local_connection": "offline"]).online)
    }
    func testIndependentBMSFreshness() {
        let data = snapshot(["bms_last_read": SolarDate.iso(now.addingTimeInterval(-96)), "cell_delta": "64"])
        XCTAssertTrue(data.online)
        XCTAssertFalse(data.bmsOnline)
        XCTAssertNil(data.number("cell_delta", slow: true))
        XCTAssertEqual(data.number("pv_today"), 21)
    }
    func testCachedReadDatesKeepExactFreshnessBoundariesAndUnknowns() {
        let valid = snapshot(["local_last_read": SolarDate.iso(now.addingTimeInterval(-15)),
                              "bms_last_read": SolarDate.iso(now.addingTimeInterval(-95))])
        XCTAssertEqual(valid.date("local_last_read"), now.addingTimeInterval(-15))
        XCTAssertTrue(valid.online)
        XCTAssertTrue(valid.bmsOnline)
        let invalid = snapshot(["local_last_read": "unavailable", "bms_last_read": "unknown"])
        XCTAssertNil(invalid.date("local_last_read"))
        XCTAssertNil(invalid.date("bms_last_read"))
        XCTAssertFalse(invalid.online)
        XCTAssertFalse(invalid.bmsOnline)
        XCTAssertNil(invalid.number("pv_today"))
    }
    func testImpossibleEnergyAllocationIsHidden() {
        XCTAssertNil(snapshot(["charge_today": "30"]).estimatedSources)
        XCTAssertNil(snapshot(["pv_today": "-1"]).consumption("today"))
    }
    func testDirectionAndCurrent() {
        XCTAssertEqual(snapshot(["battery_power": "-250"]).batteryStatus, "Đang sạc")
        XCTAssertEqual(snapshot(["battery_power": "250"]).batteryStatus, "Đang xả")
        XCTAssertEqual(snapshot(["grid_power": "-250"]).gridStatus, "Đang phát lưới")
        XCTAssertEqual(snapshot(["pv1_power": "1000", "pv1_voltage": "400"]).estimatedCurrent(power: "pv1_power", voltage: "pv1_voltage"), 2.5)
        XCTAssertNil(snapshot(["pv1_power": "1000", "pv1_voltage": "0"]).estimatedCurrent(power: "pv1_power", voltage: "pv1_voltage"))
    }
    func testFractionalTimestamp() {
        XCTAssertNotNil(SolarDate.parse("2026-10-07T05:50:12.123456+00:00"))
        XCTAssertNotNil(SolarDate.parse("2026-10-07T12:50:12+07:00"))
        XCTAssertNil(SolarDate.parse("unknown"))
    }
    func testMinimalHistoryAndUnavailableGap() throws {
        let json = """
        [[{"entity_id":"sensor.lux_pv_power","state":"10","last_changed":"2026-10-07T05:00:00Z"},
        {"state":"unavailable","last_changed":"2026-10-07T05:01:00Z"},
        {"state":"20","last_changed":"2026-10-07T05:02:00Z"}]]
        """
        let points = try HistoryParser.parse(Data(json.utf8), allowed: ["sensor.lux_pv_power"])
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points.map(\.segment), [0, 1])
        XCTAssertEqual(points.map(\.value), [10, 20])
    }
    func testOAuthRejectsWrongHostOrState() {
        let valid = URL(string: SolarConfig.redirect + "?code=abc&state=test")!
        XCTAssertEqual(SolarConfig.authorizationCode(from: valid, expectedState: "test"), "abc")
        XCTAssertNil(SolarConfig.authorizationCode(from: valid, expectedState: "other"))
        XCTAssertNil(SolarConfig.authorizationCode(from: URL(string: "https://evil.example/nam-solar/auth-callback?code=abc&state=test")!, expectedState: "test"))
        XCTAssertNil(SolarConfig.authorizationCode(from: URL(string: SolarConfig.redirect + "?code=abc&state=test&state=test")!, expectedState: "test"))
    }
    func testStateRemovalEventAndMissingAttributes() throws {
        let frame = try JSONDecoder().decode(HAFrame.self, from: Data("{\"type\":\"event\",\"event\":{\"data\":{\"entity_id\":\"sensor.lux_pv_power\",\"new_state\":null}}}".utf8))
        XCTAssertNil(frame.event?.data.new_state)
        let state = try JSONDecoder().decode(HAState.self, from: Data("{\"entity_id\":\"sensor.lux_pv_power\",\"state\":\"12\"}".utf8))
        XCTAssertTrue(state.attributes.isEmpty)
    }
}
