import XCTest
#if canImport(SolarCore)
@testable import SolarCore
#else
@testable import NamSolar
#endif

final class SolarDeviceHistoryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1800000000)
    private enum Failure: Error { case offline }
    private func point(_ device: SolarDevice, value: Double = 100) -> HistoryPoint {
        HistoryPoint(entity: device.entity, date: now, value: value, segment: 0)
    }

    func testEachIconMapsToItsOwnSensor() {
        XCTAssertEqual(SolarDevice.inverter.entity, "sensor.lux_inverter_power")
        XCTAssertEqual(SolarDevice.home.entity, "sensor.lux_home_power")
        XCTAssertEqual(SolarDevice.grid.entity, "sensor.lux_grid_power")
        XCTAssertEqual(SolarDevice.solar.entity, "sensor.lux_pv_power")
        XCTAssertEqual(Set(SolarDevice.allCases.map(\.entity)).count, 4)
        XCTAssertFalse(SolarDevice.allCases.map(\.entity).contains("sensor.lux_battery_power"))
    }

    func testDenseChartRenderingRetainsSpikesAndOriginalInspectionSamples() {
        var points: [HistoryPoint] = []
        for index in 0..<10000 {
            let value: Double
            if index == 4321 { value = 9000 }
            else if index == 7654 { value = -900 }
            else { value = Double(index % 50) }
            points.append(HistoryPoint(entity: SolarDevice.inverter.entity,
                date: now.addingTimeInterval(Double(index)), value: value, segment: 0))
        }
        let drawn = SolarChartRendering.reduced(points)
        XCTAssertLessThanOrEqual(drawn.count, 2048)
        XCTAssertEqual(drawn.first?.id, points.first?.id)
        XCTAssertEqual(drawn.last?.id, points.last?.id)
        XCTAssertTrue(drawn.contains { $0.value == 9000 })
        XCTAssertTrue(drawn.contains { $0.value == -900 })
        let originalIDs = Set(points.map(\.id))
        XCTAssertTrue(drawn.allSatisfy { originalIDs.contains($0.id) })
        let model = SolarChartModel(points: points)
        XCTAssertEqual(model.sample(at: points[6789].date, entity: SolarDevice.inverter.entity)?.id, points[6789].id)
    }

    func testDrawingReductionKeepsDisconnectedSegmentsSeparate() {
        let first = (0..<100).map { index in
            HistoryPoint(entity: SolarDevice.grid.entity, date: now.addingTimeInterval(Double(index)), value: 100, segment: 0)
        }
        let second = (200..<300).map { index in
            HistoryPoint(entity: SolarDevice.grid.entity, date: now.addingTimeInterval(Double(index)), value: -100, segment: 1)
        }
        let drawn = SolarChartRendering.reduced(first + second, buckets: 4)
        XCTAssertEqual(Set(drawn.map(\.segment)), [0, 1])
        XCTAssertTrue(drawn.contains { $0.id == first.last?.id })
        XCTAssertTrue(drawn.contains { $0.id == second.first?.id })
        XCTAssertNil(SolarChartModel(points: first + second).sample(at: now.addingTimeInterval(150), entity: SolarDevice.grid.entity))
    }

    @MainActor func testOnlySelectedEntityAnd24HoursAreRequested() async {
        let cache = SolarDeviceHistoryStore()
        await cache.load(.inverter, now: now) { entities, hours in
            XCTAssertEqual(entities, [SolarDevice.inverter.entity])
            XCTAssertEqual(hours, 24)
            return [self.point(.home), self.point(.inverter, value: 1577), self.point(.inverter, value: .nan)]
        }
        XCTAssertEqual(cache.state(for: .inverter).points.map(\.value), [1577])
        XCTAssertFalse(cache.state(for: .inverter).loading)
        XCTAssertNil(cache.state(for: .inverter).error)
        XCTAssertTrue(cache.state(for: .home).points.isEmpty)
    }

    @MainActor func testCacheExpiresAndManualRefreshBypassesIt() async {
        let cache = SolarDeviceHistoryStore()
        var calls = 0
        let fetch: @MainActor ([String], Int) async throws -> [HistoryPoint] = { _, _ in
            calls += 1
            return [self.point(.solar)]
        }
        await cache.load(.solar, now: now, fetch: fetch)
        await cache.load(.solar, now: now.addingTimeInterval(59), fetch: fetch)
        XCTAssertEqual(calls, 1)
        await cache.load(.solar, now: now.addingTimeInterval(60), fetch: fetch)
        XCTAssertEqual(calls, 2)
        await cache.load(.solar, force: true, now: now.addingTimeInterval(61), fetch: fetch)
        XCTAssertEqual(calls, 3)
    }

    @MainActor func testConcurrentRequestsForSameDeviceAreCoalesced() async {
        let cache = SolarDeviceHistoryStore()
        var calls = 0
        let fetch: @MainActor ([String], Int) async throws -> [HistoryPoint] = { _, _ in
            calls += 1
            try await Task.sleep(for: .milliseconds(30))
            return [self.point(.home)]
        }
        let first = Task { await cache.load(.home, now: now, fetch: fetch) }
        let second = Task { await cache.load(.home, now: now, fetch: fetch) }
        await first.value
        await second.value
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(cache.state(for: .home).points.count, 1)
    }

    @MainActor func testFailureKeepsPreviousHistoryAndAllowsRetry() async {
        let cache = SolarDeviceHistoryStore()
        await cache.load(.grid, now: now) { _, _ in [self.point(.grid, value: -420)] }
        await cache.load(.grid, force: true, now: now.addingTimeInterval(1)) { _, _ in throw Failure.offline }
        XCTAssertNotNil(cache.state(for: .grid).error)
        XCTAssertFalse(cache.state(for: .grid).loading)
        XCTAssertEqual(cache.state(for: .grid).points.first?.value, -420)
        XCTAssertEqual(cache.state(for: .grid).loadedAt, now)
        await cache.load(.grid, now: now.addingTimeInterval(2)) { _, _ in [self.point(.grid, value: 12)] }
        XCTAssertNil(cache.state(for: .grid).error)
        XCTAssertEqual(cache.state(for: .grid).points.first?.value, 12)
    }

    @MainActor func testEmptyHistoryDoesNotInventZeroSamples() async {
        let cache = SolarDeviceHistoryStore()
        await cache.load(.solar, now: now) { _, _ in [] }
        XCTAssertTrue(cache.state(for: .solar).points.isEmpty)
        XCTAssertNil(cache.state(for: .solar).error)
        XCTAssertEqual(cache.state(for: .solar).loadedAt, now)
    }

    @MainActor func testResetRejectsLateResultsFromPreviousSession() async {
        let cache = SolarDeviceHistoryStore()
        let pending = Task {
            await cache.load(.inverter, now: now) { _, _ in
                // Simulate a response arriving even after cancellation.
                try? await Task.sleep(for: .milliseconds(50))
                return [self.point(.inverter)]
            }
        }
        for _ in 0..<100 { if cache.state(for: .inverter).loading { break }; await Task.yield() }
        XCTAssertTrue(cache.state(for: .inverter).loading)
        cache.reset()
        await pending.value
        XCTAssertTrue(cache.entries.isEmpty)
        await cache.load(.inverter, now: now) { _, _ in [self.point(.inverter, value: 900)] }
        XCTAssertEqual(cache.state(for: .inverter).points.first?.value, 900)
    }

    @MainActor func testDifferentDevicesHaveIndependentCachesAndErrors() async {
        let cache = SolarDeviceHistoryStore()
        await cache.load(.inverter, now: now) { _, _ in [self.point(.inverter, value: 1577)] }
        await cache.load(.home, now: now) { _, _ in throw Failure.offline }
        XCTAssertEqual(cache.state(for: .inverter).points.first?.value, 1577)
        XCTAssertNil(cache.state(for: .inverter).error)
        XCTAssertNotNil(cache.state(for: .home).error)
        XCTAssertTrue(cache.state(for: .home).points.isEmpty)
    }

    @MainActor func testPreloadBatchesAllIconsAndTapJoinsPendingRequest() async {
        let cache = SolarDeviceHistoryStore()
        var calls = 0
        let fetch: @MainActor ([String], Int) async throws -> [HistoryPoint] = { entities, hours in
            calls += 1
            XCTAssertEqual(Set(entities), Set(SolarDevice.allCases.map(\.entity)))
            XCTAssertEqual(hours, 24)
            try await Task.sleep(for: .milliseconds(40))
            return SolarDevice.allCases.map { self.point($0) }
        }
        let warm = Task { await cache.preload(now: now, fetch: fetch) }
        for _ in 0..<100 { if cache.state(for: .inverter).loading { break }; await Task.yield() }
        XCTAssertTrue(cache.state(for: .inverter).loading)
        await cache.load(.inverter, now: now, fetch: fetch)
        await warm.value
        XCTAssertEqual(calls, 1)
        for device in SolarDevice.allCases {
            XCTAssertEqual(cache.state(for: device).chart?.points.count, 1)
            await cache.load(device, now: now.addingTimeInterval(1), fetch: fetch)
        }
        XCTAssertEqual(calls, 1, "Warm icon taps must not make new HTTP requests")
    }

    @MainActor func testPreloadRequestsOnlyMissingOrExpiredCharts() async {
        let cache = SolarDeviceHistoryStore()
        await cache.load(.inverter, now: now) { _, _ in [self.point(.inverter)] }
        var calls = 0
        let fetch: @MainActor ([String], Int) async throws -> [HistoryPoint] = { entities, _ in
            calls += 1
            XCTAssertEqual(Set(entities), Set([SolarDevice.solar, .home, .grid].map(\.entity)))
            return SolarDevice.allCases.map { self.point($0) }
        }
        await cache.preload(now: now.addingTimeInterval(1), fetch: fetch)
        await cache.preload(now: now.addingTimeInterval(2), fetch: fetch)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(cache.state(for: .inverter).loadedAt, now)
    }

    @MainActor func testCachedChartStaysVisibleDuringSlowBackgroundRefresh() async {
        let cache = SolarDeviceHistoryStore()
        await cache.load(.grid, now: now) { _, _ in [self.point(.grid, value: -420)] }
        let warm = Task {
            await cache.preload(now: now.addingTimeInterval(61)) { _, _ in
                try await Task.sleep(for: .milliseconds(40))
                return [self.point(.grid, value: 100)]
            }
        }
        for _ in 0..<100 { if cache.state(for: .grid).loading { break }; await Task.yield() }
        XCTAssertTrue(cache.state(for: .grid).loading)
        XCTAssertEqual(cache.state(for: .grid).chart?.points.first?.value, -420)
        await warm.value
        XCTAssertEqual(cache.state(for: .grid).chart?.points.first?.value, 100)
    }

    @MainActor func testCancelledPreloadCannotOverwriteRestartedSession() async {
        let cache = SolarDeviceHistoryStore()
        let old = Task {
            await cache.preload(now: now) { _, _ in
                try? await Task.sleep(for: .milliseconds(80))
                return [self.point(.inverter, value: 100)]
            }
        }
        for _ in 0..<100 { if cache.state(for: .inverter).loading { break }; await Task.yield() }
        cache.cancelLoading()
        XCTAssertFalse(cache.state(for: .inverter).loading)
        await cache.load(.inverter, now: now) { _, _ in [self.point(.inverter, value: 900)] }
        await old.value
        XCTAssertEqual(cache.state(for: .inverter).chart?.points.first?.value, 900)
        XCTAssertNil(cache.state(for: .inverter).error)
    }

    @MainActor func testFailedPreloadRetainsChartAndAllowsRetry() async {
        let cache = SolarDeviceHistoryStore()
        await cache.load(.home, now: now) { _, _ in [self.point(.home, value: 1578)] }
        await cache.preload(now: now.addingTimeInterval(61)) { _, _ in throw Failure.offline }
        XCTAssertEqual(cache.state(for: .home).chart?.points.first?.value, 1578)
        XCTAssertNotNil(cache.state(for: .home).error)
        XCTAssertFalse(cache.state(for: .home).loading)
        await cache.load(.home, now: now.addingTimeInterval(62)) { _, _ in [self.point(.home, value: 1600)] }
        XCTAssertEqual(cache.state(for: .home).chart?.points.first?.value, 1600)
        XCTAssertNil(cache.state(for: .home).error)
    }
}
