import XCTest
#if canImport(SolarCore)
@testable import SolarCore
#else
@testable import NamSolar
#endif

final class SolarEnergyTests: XCTestCase {
    private let now = SolarDate.parse("2026-10-08T05:00:00Z")!
    private let day = SolarDate.parse("2026-10-06T17:00:00Z")!
    private var meters: [SolarEnergyMetric: [String]] {
        [.pv: ["meter.pv"], .charge: ["meter.charge"], .discharge: ["meter.discharge"],
         .gridImport: ["meter.import"], .gridExport: ["meter.export"]]
    }
    private var metadata: [SolarEnergyMetadata] {
        meters.values.flatMap { $0 }.map {
            SolarEnergyMetadata(statistic_id: $0, has_sum: true, unit_class: "energy", statistics_unit_of_measurement: "Wh")
        }
    }
    private func range(_ count: Int = 1) throws -> SolarEnergyRange {
        let start = SolarEnergyRange.calendar().date(byAdding: .day, value: 1 - count, to: day)!
        return try SolarEnergyRange(from: start, through: day, now: now)
    }
    private func statistics(_ range: SolarEnergyRange) -> [String: [SolarEnergyStatistic]] {
        let samples: [SolarEnergyMetric: Double] = [.pv: 5, .charge: 2, .discharge: 1, .gridImport: 0.5, .gridExport: 0.2]
        return Dictionary(uniqueKeysWithValues: meters.map { metric, ids in
            (ids[0], range.intervals.map { interval in
                SolarEnergyStatistic(start: interval.start.timeIntervalSince1970 * 1000,
                    end: interval.end.timeIntervalSince1970 * 1000, change: samples[metric])
            })
        })
    }
    private func report(_ range: SolarEnergyRange) throws -> SolarEnergyReport {
        try SolarEnergyReport.build(range: range, meters: meters, metadata: metadata, statistics: statistics(range), now: now)
    }

    func testSingleDayIncludesFullVietnamDayNotDeviceMidnight() throws {
        let selected = try range()
        XCTAssertEqual(SolarDate.iso(selected.start), "2026-10-06T17:00:00Z")
        XCTAssertEqual(selected.requestEnd, "2026-10-07T16:59:59.999Z")
        XCTAssertEqual(selected.intervals.count, 24)
        XCTAssertEqual(selected.period, "hour")
        XCTAssertEqual(selected.title, "07/10/2026")
    }

    func testDateRangeIncludesLastDayAndCrossesMonth() throws {
        let first = SolarDate.parse("2026-09-29T17:00:00Z")!
        let last = SolarDate.parse("2026-10-01T17:00:00Z")!
        let selected = try SolarEnergyRange(from: first, through: last, now: now)
        XCTAssertEqual(selected.dayCount, 3)
        XCTAssertEqual(selected.intervals.count, 3)
        XCTAssertEqual(selected.period, "day")
        XCTAssertEqual(selected.requestEnd, "2026-10-02T16:59:59.999Z")
    }

    func testInvalidFutureReversedAndExcessiveRangesAreRejected() {
        XCTAssertThrowsError(try SolarEnergyRange(from: now, through: day, now: now))
        XCTAssertThrowsError(try SolarEnergyRange(from: now.addingTimeInterval(86400), through: now.addingTimeInterval(86400), now: now))
        XCTAssertThrowsError(try SolarEnergyRange(from: day.addingTimeInterval(-366 * 86400), through: day, now: now))
        XCTAssertThrowsError(try SolarEnergyRange(from: day, through: day, timeZoneID: "not-a-zone", now: now))
    }

    func testServerTimeZoneResolutionPreservesPickedCalendarDatesAndDST() throws {
        let selected = try range()
        let resolved = try selected.resolved(in: "America/New_York", now: now)
        XCTAssertEqual(resolved.title, selected.title)
        XCTAssertEqual(SolarDate.iso(resolved.start), "2026-10-07T04:00:00Z")
        let fallback = SolarDate.parse("2026-11-01T04:00:00Z")!
        let dst = try SolarEnergyRange(from: fallback, through: fallback, timeZoneID: "America/New_York", now: fallback.addingTimeInterval(86400 * 3))
        XCTAssertEqual(dst.intervals.count, 25)
        XCTAssertEqual(dst.end.timeIntervalSince(dst.start), 25 * 3600)
    }

    func testPreferencesUseWebMetersDeduplicateAndSupportLegacyGrid() throws {
        let json = #"{"energy_sources":[{"type":"solar","stat_energy_from":"pv"},{"type":"solar","stat_energy_from":"pv"},{"type":"battery","stat_energy_from":"out","stat_energy_to":"in"},{"type":"grid","flow_from":[{"stat_energy_from":"buy"}],"flow_to":[{"stat_energy_to":"sell"}]}]}"#
        let prefs = try JSONDecoder().decode(SolarEnergyPreferences.self, from: Data(json.utf8))
        let ids = try prefs.meters()
        XCTAssertEqual(ids[.pv], ["pv"])
        XCTAssertEqual(ids[.discharge], ["out"])
        XCTAssertEqual(ids[.charge], ["in"])
        XCTAssertEqual(ids[.gridImport], ["buy"])
        XCTAssertEqual(ids[.gridExport], ["sell"])
        let empty = try JSONDecoder().decode(SolarEnergyPreferences.self, from: Data(#"{"energy_sources":[]}"#.utf8))
        XCTAssertThrowsError(try empty.meters())
        let reused = try JSONDecoder().decode(SolarEnergyPreferences.self, from: Data(#"{"energy_sources":[{"type":"battery","stat_energy_from":"same","stat_energy_to":"same"}]}"#.utf8))
        XCTAssertThrowsError(try reused.meters())
    }

    func testMillisecondsAndServerChangeKWhAreUsedWithoutCounterDifferencing() throws {
        let result = try report(range())
        XCTAssertEqual(result.total(.pv)!, 120, accuracy: 0.000001)
        XCTAssertEqual(result.total(.consumption)!, 103.2, accuracy: 0.000001)
        XCTAssertEqual(result.buckets.first?.value(.consumption) ?? -1, 4.3, accuracy: 0.000001)
        XCTAssertFalse(result.incomplete)
        XCTAssertEqual(result.buckets.first?.start, day)
        // Metadata originally Wh, but the WS request asks HA to convert change to kWh.
        XCTAssertEqual(result.buckets.first?.value(.pv), 5)
    }

    func testUnknownAndMissingStatisticsAreNotZeroAndBalanceNeedsAllMeters() throws {
        let selected = try range()
        var stats = statistics(selected)
        stats["meter.charge"] = []
        let result = try SolarEnergyReport.build(range: selected, meters: meters, metadata: metadata, statistics: stats, now: now)
        XCTAssertNil(result.total(.charge))
        XCTAssertNil(result.total(.consumption))
        XCTAssertEqual(result.total(.pv), 120)
        XCTAssertTrue(result.incomplete)
        XCTAssertEqual(result.missingCount(.charge), 24)
        let noMetadata = try SolarEnergyReport.build(range: selected, meters: meters, metadata: [], statistics: stats, now: now)
        XCTAssertFalse(noMetadata.hasData)
        XCTAssertEqual(noMetadata.unavailableMeters.count, 5)
    }

    func testRealZerosRemainVisibleAndPartialTotalsAreFlagged() throws {
        let selected = try range()
        var stats = statistics(selected)
        stats["meter.export"] = selected.intervals.map { SolarEnergyStatistic(start: $0.start.timeIntervalSince1970 * 1000, end: $0.end.timeIntervalSince1970 * 1000, change: 0) }
        stats["meter.pv"]?.removeFirst()
        let result = try SolarEnergyReport.build(range: selected, meters: meters, metadata: metadata, statistics: stats, now: now)
        XCTAssertEqual(result.total(.gridExport), 0)
        XCTAssertEqual(result.total(.pv), 115)
        XCTAssertNil(result.buckets.first?.value(.pv))
        XCTAssertNil(result.buckets.first?.value(.consumption))
        XCTAssertTrue(result.incomplete)
        XCTAssertEqual(result.missingCount(.pv), 1)
    }

    func testDuplicateOrMisalignedIntervalsFailRatherThanDoubleCount() throws {
        let selected = try range()
        var stats = statistics(selected)
        let repeated = stats["meter.pv"]![0]
        stats["meter.pv"]?.append(repeated)
        XCTAssertThrowsError(try SolarEnergyReport.build(range: selected, meters: meters, metadata: metadata, statistics: stats, now: now))
        stats = statistics(selected)
        stats["meter.pv"] = [SolarEnergyStatistic(start: day.timeIntervalSince1970 * 1000 + 60000,
            end: day.addingTimeInterval(3600).timeIntervalSince1970 * 1000, change: 1)]
        XCTAssertThrowsError(try SolarEnergyReport.build(range: selected, meters: meters, metadata: metadata, statistics: stats, now: now))
    }

    func testNullNegativeNonfiniteValuesAndUnrequestedSeriesCannotCorruptTotals() throws {
        let selected = try range()
        var stats = statistics(selected)
        stats["meter.pv"] = selected.intervals.enumerated().map { index, interval in
            SolarEnergyStatistic(start: interval.start.timeIntervalSince1970 * 1000, end: interval.end.timeIntervalSince1970 * 1000,
                change: index == 0 ? nil : index == 1 ? -1 : index == 2 ? .nan : 5)
        }
        stats["unrequested"] = [SolarEnergyStatistic(start: .nan, end: .nan, change: 90000)]
        let result = try SolarEnergyReport.build(range: selected, meters: meters, metadata: metadata, statistics: stats, now: now)
        XCTAssertEqual(result.total(.pv), 105)
        XCTAssertEqual(result.missingCount(.pv), 3)
        XCTAssertNil(result.buckets.first?.value(.pv))
    }

    func testDailyAggregationUsesReturnedChangeAndEmptyRangeStaysEmpty() throws {
        let selected = try range(7)
        let result = try report(selected)
        XCTAssertEqual(result.buckets.count, 7)
        XCTAssertEqual(result.total(.pv), 35)
        let empty = try SolarEnergyReport.build(range: selected, meters: meters, metadata: metadata, statistics: [:], now: now)
        XCTAssertFalse(empty.hasData)
        XCTAssertNil(empty.total(.pv))
    }

    @MainActor func testCacheExpiresManualRefreshAndSameRangeCoalesces() async throws {
        let store = SolarEnergyStore()
        let selected = try range()
        var calls = 0
        let fetch: @MainActor (SolarEnergyRange) async throws -> SolarEnergyReport = { range in
            calls += 1
            try await Task.sleep(for: .milliseconds(20))
            return try self.report(range)
        }
        let first = Task { await store.load(selected, now: now, fetch: fetch) }
        let second = Task { await store.load(selected, now: now, fetch: fetch) }
        await first.value; await second.value
        XCTAssertEqual(calls, 1)
        await store.load(selected, now: now.addingTimeInterval(59), fetch: fetch)
        XCTAssertEqual(calls, 1)
        await store.load(selected, now: now.addingTimeInterval(60), fetch: fetch)
        XCTAssertEqual(calls, 2)
        await store.load(selected, force: true, now: now.addingTimeInterval(61), fetch: fetch)
        XCTAssertEqual(calls, 3)
        XCTAssertFalse(store.loading)
    }

    @MainActor func testLateCancelledRangeCannotReplaceNewSelection() async throws {
        let store = SolarEnergyStore()
        let oldRange = try range()
        let newRange = try range(7)
        let old = Task {
            await store.load(oldRange, now: now) { range in
                try? await Task.sleep(for: .milliseconds(100))
                return try self.report(range)
            }
        }
        await Task.yield()
        await store.load(newRange, now: now) { range in try self.report(range) }
        await old.value
        XCTAssertEqual(store.report?.range, newRange)
        XCTAssertFalse(store.loading)
        XCTAssertNil(store.error)
    }

    @MainActor func testLogoutResetDiscardsLateResponseAndAllowsReload() async throws {
        let store = SolarEnergyStore()
        let selected = try range()
        let old = Task {
            await store.load(selected, now: now) { range in
                try? await Task.sleep(for: .milliseconds(100))
                return try self.report(range)
            }
        }
        await Task.yield()
        store.reset()
        await old.value
        XCTAssertNil(store.report)
        XCTAssertNil(store.error)
        XCTAssertFalse(store.loading)
        await store.load(selected, now: now) { range in try self.report(range) }
        XCTAssertNotNil(store.report)
    }

    @MainActor func testFailedNewRangeDoesNotDisplayOldTotals() async throws {
        let store = SolarEnergyStore()
        await store.load(try range(), now: now) { range in try self.report(range) }
        await store.load(try range(7), now: now) { _ in throw SolarEnergyError.requestFailed }
        XCTAssertNil(store.report)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.loading)
    }
}
