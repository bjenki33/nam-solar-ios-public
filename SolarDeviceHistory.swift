import Foundation
import Observation

enum SolarDevice: String, CaseIterable, Identifiable, Sendable {
    case solar, inverter, home, grid
    var id: String { rawValue }
    var key: String {
        switch self {
        case .solar: return "pv_power"
        case .inverter: return "inverter_power"
        case .home: return "home_power"
        case .grid: return "grid_power"
        }
    }
    var entity: String { SolarSnapshot.prefix + key }
    var title: String {
        switch self {
        case .solar: return "Điện mặt trời"
        case .inverter: return "Biến tần Luxpower"
        case .home: return "Nhà đang sử dụng"
        case .grid: return "Điện lưới"
        }
    }
    var sensorName: String {
        switch self {
        case .solar: return "Lux PV power"
        case .inverter: return "Lux inverter power"
        case .home: return "Lux home power"
        case .grid: return "Lux grid power"
        }
    }
    var chartTitle: String { sensorName + " · 24 giờ" }
}

struct SolarDeviceHistoryState {
    var points: [HistoryPoint] = []
    var chart: SolarChartModel?
    var loading = false
    var error: String?
    var loadedAt: Date?
}

@MainActor @Observable
final class SolarDeviceHistoryStore {
    static let hours = 24
    static let cacheLifetime: TimeInterval = 60
    private(set) var entries: [SolarDevice: SolarDeviceHistoryState] = [:]
    @ObservationIgnored private var tasks: [SolarDevice: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = UUID()

    func state(for device: SolarDevice) -> SolarDeviceHistoryState {
        entries[device] ?? SolarDeviceHistoryState()
    }

    private func isFresh(_ state: SolarDeviceHistoryState, now: Date) -> Bool {
        guard state.error == nil, let loaded = state.loadedAt else { return false }
        return (0..<Self.cacheLifetime).contains(now.timeIntervalSince(loaded))
    }

    // One bounded batch warms all four icon charts after the live snapshot.
    // A tap during preload joins the same task rather than starting another GET.
    func preload(now: Date = Date(),
                 fetch: @escaping @MainActor ([String], Int) async throws -> [HistoryPoint]) async {
        guard !Task.isCancelled else { return }
        let devices = SolarDevice.allCases.filter { tasks[$0] == nil && !isFresh(state(for: $0), now: now) }
        guard !devices.isEmpty else { return }
        let ticket = generation
        let previous = Dictionary(uniqueKeysWithValues: devices.map { ($0, state(for: $0)) })
        for device in devices {
            let old = previous[device]!
            entries[device] = SolarDeviceHistoryState(points: old.points, chart: old.chart, loading: true, loadedAt: old.loadedAt)
        }
        let work = Task {
            defer {
                if self.generation == ticket { for device in devices { self.tasks[device] = nil } }
            }
            do {
                let points = try await fetch(devices.map(\.entity), Self.hours)
                let charts = try await SolarHistoryPreparation.devices(points, devices: devices)
                guard self.generation == ticket, !Task.isCancelled else { return }
                for device in devices {
                    let chart = charts[device]!
                    self.entries[device] = SolarDeviceHistoryState(points: chart.points, chart: chart, loadedAt: now)
                }
            } catch {
                guard self.generation == ticket, !Task.isCancelled else { return }
                for device in devices {
                    let old = previous[device]!
                    self.entries[device] = SolarDeviceHistoryState(points: old.points, chart: old.chart,
                        error: "Chưa tải được lịch sử. Bấm tải lại; công suất hiện tại vẫn cập nhật độc lập.", loadedAt: old.loadedAt)
                }
            }
        }
        for device in devices { tasks[device] = work }
        await work.value
    }

    func load(_ device: SolarDevice, force: Bool = false, now: Date = Date(),
              fetch: @escaping @MainActor ([String], Int) async throws -> [HistoryPoint]) async {
        guard !Task.isCancelled else { return }
        if let work = tasks[device] { await work.value; return }
        let previous = state(for: device)
        if !force, isFresh(previous, now: now) { return }
        let ticket = generation
        entries[device] = SolarDeviceHistoryState(points: previous.points, chart: previous.chart, loading: true, loadedAt: previous.loadedAt)
        let work = Task {
            defer { if self.generation == ticket { self.tasks[device] = nil } }
            do {
                let result = try await fetch([device.entity], Self.hours)
                guard self.generation == ticket, !Task.isCancelled else { return }
                // Never let another device's series leak into this detail chart.
                let charts = try await SolarHistoryPreparation.devices(result, devices: [device])
                guard self.generation == ticket, !Task.isCancelled else { return }
                let chart = charts[device]!
                self.entries[device] = SolarDeviceHistoryState(points: chart.points, chart: chart, loadedAt: now)
            } catch {
                guard self.generation == ticket, !Task.isCancelled else { return }
                self.entries[device] = SolarDeviceHistoryState(points: previous.points, chart: previous.chart,
                    error: "Chưa tải được lịch sử. Bấm tải lại; công suất hiện tại vẫn cập nhật độc lập.",
                    loadedAt: previous.loadedAt)
            }
        }
        tasks[device] = work
        await work.value
    }

    func cancelLoading() {
        generation = UUID()
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        for device in Array(entries.keys) { entries[device]?.loading = false }
    }

    func reset() {
        cancelLoading()
        entries.removeAll()
    }

    #if DEBUG
    static func previewPoints(for device: SolarDevice, now: Date) -> [HistoryPoint] {
        let base: Double
        let amplitude: Double
        switch device {
        case .solar: (base, amplitude) = (1820, 700)
        case .inverter: (base, amplitude) = (1577, 350)
        case .home: (base, amplitude) = (1578, 400)
        case .grid: (base, amplitude) = (0, 120)
        }
        return (0...288).map { index in
            HistoryPoint(entity: device.entity, date: now.addingTimeInterval(Double(index - 288) * 300),
                value: base + sin(Double(index - 288) / 12) * amplitude, segment: 0)
        }
    }
    #endif
}
