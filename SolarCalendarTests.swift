import XCTest
#if canImport(SolarCore)
@testable import SolarCore
#else
@testable import NamSolar
#endif

final class SolarCalendarTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int, zone: String = SolarEnergyRange.defaultTimeZone) -> Date {
        SolarEnergyRange.calendar(zone).date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testBrowsingPreviousMonthDoesNotChangeSelectedDay() {
        let now = date(2026, 10, 9)
        var draft = SolarCalendarDraft(selection: now, timeZoneID: SolarEnergyRange.defaultTimeZone, now: now)
        let selected = draft.selectedDay
        draft.moveMonth(-1)
        for _ in 0..<20 {
            XCTAssertEqual(draft.monthTitle, "09/2026")
            XCTAssertEqual(draft.selectedDay, selected)
            XCTAssertEqual(draft.days.compactMap { $0 }.count, 30)
        }
    }

    func testMonthNavigationCrossesYearAndDoesNotSkipFebruary() {
        let now = date(2026, 3, 31)
        var draft = SolarCalendarDraft(selection: now, timeZoneID: SolarEnergyRange.defaultTimeZone, now: now)
        draft.moveMonth(-1)
        XCTAssertEqual(draft.monthTitle, "02/2026")
        XCTAssertEqual(draft.days.compactMap { $0 }.count, 28)
        draft.moveMonth(-2)
        XCTAssertEqual(draft.monthTitle, "12/2025")
        draft.moveMonth(1)
        XCTAssertEqual(draft.monthTitle, "01/2026")
    }

    func testCannotBrowseOrSelectFutureDays() {
        let now = date(2026, 10, 9)
        var draft = SolarCalendarDraft(selection: now, timeZoneID: SolarEnergyRange.defaultTimeZone, now: now)
        XCTAssertFalse(draft.canMoveForward)
        draft.moveMonth(1)
        XCTAssertEqual(draft.monthTitle, "10/2026")
        draft.select(date(2026, 10, 10))
        XCTAssertEqual(draft.label(draft.selectedDay), "09/10/2026")
        draft.moveMonth(-1)
        XCTAssertTrue(draft.canMoveForward)
    }

    func testGridUsesMondayFirstAndContainsExactlyOneOfEveryDay() {
        let now = date(2026, 10, 9)
        let draft = SolarCalendarDraft(selection: date(2026, 9, 5), timeZoneID: SolarEnergyRange.defaultTimeZone, now: now)
        XCTAssertEqual(draft.days.count, 42)
        XCTAssertNil(draft.days[0])
        XCTAssertEqual(draft.days[1].map(draft.label), "01/09/2026")
        XCTAssertEqual(Set(draft.days.compactMap { $0 }).count, 30)
        XCTAssertEqual(draft.days.compactMap { $0 }.last.map(draft.label), "30/09/2026")
    }

    func testLeapMonthIncludesFebruary29() {
        let draft = SolarCalendarDraft(selection: date(2024, 2, 29), timeZoneID: SolarEnergyRange.defaultTimeZone, now: date(2026, 10, 9))
        XCTAssertEqual(draft.days.compactMap { $0 }.count, 29)
        XCTAssertEqual(draft.days.compactMap { $0 }.last.map(draft.label), "29/02/2024")
    }

    func testDayGridSurvivesDaylightSavingTransition() {
        let zone = "America/New_York"
        let draft = SolarCalendarDraft(selection: date(2026, 3, 8, zone: zone), timeZoneID: zone, now: date(2026, 10, 9, zone: zone))
        let days = draft.days.compactMap { $0 }
        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(Set(days.map(draft.label)).count, 31)
        XCTAssertEqual(days.last.map(draft.label), "31/03/2026")
    }

    func testSelectionNormalizesInServerTimeZoneAndTodayRestoresMonth() {
        let now = date(2026, 10, 9)
        var draft = SolarCalendarDraft(selection: now, timeZoneID: SolarEnergyRange.defaultTimeZone, now: now)
        draft.moveMonth(-1)
        draft.select(date(2026, 9, 5))
        XCTAssertEqual(draft.calendar.component(.hour, from: draft.selectedDay), 0)
        XCTAssertEqual(draft.label(draft.selectedDay), "05/09/2026")
        XCTAssertEqual(draft.monthTitle, "09/2026")
        draft.showToday()
        XCTAssertEqual(draft.monthTitle, "10/2026")
        XCTAssertEqual(draft.selectedDay, draft.today)
    }

    func testFutureInitialSelectionIsClampedToSessionToday() {
        let draft = SolarCalendarDraft(selection: date(2026, 11, 5), timeZoneID: SolarEnergyRange.defaultTimeZone, now: date(2026, 10, 9))
        XCTAssertEqual(draft.label(draft.selectedDay), "09/10/2026")
        XCTAssertEqual(draft.monthTitle, "10/2026")
    }
}
