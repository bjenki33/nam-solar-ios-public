import Foundation
import Observation

@MainActor @Observable
final class SolarStore {
    private(set) var states: [String: HAState] = [:]
    private(set) var loggedIn: Bool
    private(set) var transportLive = false
    private(set) var connecting = false
    private(set) var connectionMessage = "Đang kết nối"
    private(set) var receivedAt: Date?
    private(set) var powerHistory: [HistoryPoint] = []
    private(set) var batteryHistory: [HistoryPoint] = []
    private(set) var preparedHistory: SolarPreparedHistory?
    private var historyLoadedAt: Date?
    private(set) var historyError: String?
    private(set) var historyLoading = false
    let deviceHistory = SolarDeviceHistoryStore()
    let energyHistory = SolarEnergyStore()
    private var historyTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var epoch = UUID()
    private let service = HAService()
    private(set) var previewMode = false

    init() {
        loggedIn = service.session != nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-preview") {
            previewMode = true
            loggedIn = true
            transportLive = true
            connectionMessage = "Dữ liệu kiểm thử"
            let discharging = ProcessInfo.processInfo.arguments.contains("--ui-battery-discharge")
            let rawBatteryPower = discharging ? 240.0 : -240.0
            let sample = ["local_connection": "online", "bms_connection": "online",
                          "pv_power": "1820", "home_power": "1578", "battery_power": String(rawBatteryPower), "grid_power": "0",
                          "pv1_power": "800", "pv2_power": "1020", "pv1_voltage": "354", "pv2_voltage": "410",
                          "pv_today": "21", "pv_total": "507.9", "charge_today": "13.7", "charge_total": "269.5",
                          "discharge_today": "1.8", "discharge_total": "280.4", "grid_import_today": "0",
                          "grid_import_total": "159", "grid_export_today": "0", "grid_export_total": "0",
                          "battery_soc": "86", "battery_voltage": "54.7", "battery_charge": discharging ? "0" : "240", "battery_discharge": discharging ? "240" : "0",
                          "cell_min_voltage": "3.391", "cell_max_voltage": "3.455", "cell_delta": "64", "battery_cycles": "0",
                          "bms_capacity": "327", "battery_temperature_min": "28", "battery_temperature_max": "29",
                          "radiator1_temperature": "50", "radiator2_temperature": "47", "inverter_power": "1577",
                          "grid_voltage": "252.3", "grid_frequency": "50.1", "grid_side_load": "1591", "eps_power": "0",
                          "state_code": "20", "fault_raw": "00000000", "warning_raw": "00000000",
                          "bms_fault_raw": "0000", "bms_warning_raw": "0000"]
            states = Dictionary(uniqueKeysWithValues: sample.map { (SolarSnapshot.prefix + $0.key, HAState(entity_id: SolarSnapshot.prefix + $0.key, state: $0.value)) })
            let now = Date()
            powerHistory = SolarConfig.powerEntities.enumerated().flatMap { index, entity in
                (0..<60).map { minute in
                    HistoryPoint(entity: entity, date: now.addingTimeInterval(Double(minute - 60) * 120),
                                 value: index == 0 ? 1800 + sin(Double(minute) / 8) * 500 : index == 1 ? 1500 : index == 2 ? 0 : rawBatteryPower, segment: 0)
                }
            }
            batteryHistory = (0..<60).map { minute in
                HistoryPoint(entity: "sensor.lux_battery_soc", date: now.addingTimeInterval(Double(minute - 60) * 1440), value: 40 + Double(minute) * 0.77, segment: 0)
            }
            batteryHistory += (0..<60).map { minute in
                HistoryPoint(entity: "sensor.lux_cell_delta", date: now.addingTimeInterval(Double(minute - 60) * 1440), value: 64, segment: 0)
            }
            preparedHistory = SolarPreparedHistory(power: SolarChartModel(points: SolarBatteryPower.history(powerHistory)),
                soc: SolarChartModel(points: batteryHistory.filter { $0.entity == "sensor.lux_battery_soc" }),
                cell: SolarChartModel(points: batteryHistory.filter { $0.entity == "sensor.lux_cell_delta" }))
        }
        #endif
    }

    func snapshot(now: Date = Date()) -> SolarSnapshot {
        #if DEBUG
        if previewMode {
            var sample = states
            for key in ["local_last_read", "bms_last_read"] {
                sample[SolarSnapshot.prefix + key] = HAState(entity_id: SolarSnapshot.prefix + key, state: SolarDate.iso(now))
            }
            return SolarSnapshot(states: sample, now: now, transportLive: true)
        }
        #endif
        return SolarSnapshot(states: states, now: now, transportLive: transportLive)
    }

    func login(code: String) async throws {
        try await service.exchange(code: code)
        loggedIn = true
        start()
    }

    func start(force: Bool = false) {
        if previewMode { return }
        if !force, runTask != nil { return }
        stop()
        guard loggedIn else { return }
        let id = epoch
        runTask = Task {
            var retry = 0
            var forced = false
            while !Task.isCancelled && self.epoch == id {
                self.connecting = true
                self.connectionMessage = retry == 0 ? "Đang kết nối" : "Đang kết nối lại"
                do {
                    let token = try await self.service.accessToken(forceRefresh: forced)
                    try Task.checkCancellation()
                    guard self.epoch == id else { return }
                    let channel = self.service.socket()
                    self.socket = channel
                    defer { channel.cancel(with: .goingAway, reason: nil) }
                    guard try await self.receive(channel, timeout: 15).type == "auth_required" else { throw SolarError.invalidResponse }
                    try await self.send(["type": "auth", "access_token": token], to: channel)
                    let auth = try await self.receive(channel, timeout: 15)
                    if auth.type == "auth_invalid" {
                        if forced { throw SolarError.expiredLogin }
                        forced = true
                        continue
                    }
                    guard auth.type == "auth_ok" else { throw SolarError.invalidResponse }
                    forced = false
                    try await self.send(["id": 1, "type": "subscribe_events", "event_type": "state_changed"], to: channel)
                    let ack = try await self.receive(channel, timeout: 15)
                    guard ack.type == "result", ack.id == 1, ack.success == true else { throw SolarError.invalidResponse }
                    try await self.send(["id": 2, "type": "get_states"], to: channel)
                    var hasSnapshot = false
                    let heartbeat = Task {
                        var command = 3
                        while !Task.isCancelled {
                            do {
                                try await Task.sleep(for: .seconds(20))
                                try await self.send(["id": command, "type": "ping"], to: channel)
                                command += 1
                            } catch { channel.cancel(with: .goingAway, reason: nil); return }
                        }
                    }
                    defer { heartbeat.cancel() }
                    while !Task.isCancelled && self.epoch == id {
                        let message = try await self.receive(channel, timeout: hasSnapshot ? 45 : 15)
                        if message.type == "result", message.id == 2 {
                            guard message.success == true else { throw SolarError.invalidResponse }
                            let list = try message.snapshotStates().filter { $0.entity_id.hasPrefix(SolarSnapshot.prefix) }
                            self.states = Dictionary(list.map { ($0.entity_id, $0) }, uniquingKeysWith: { _, last in last })
                            self.transportLive = true
                            self.connecting = false
                            self.connectionMessage = "Trực tiếp"
                            self.receivedAt = Date()
                            hasSnapshot = true
                            retry = 0
                            self.preloadHistories()
                        } else if hasSnapshot, let event = message.event?.data, event.entity_id.hasPrefix(SolarSnapshot.prefix) {
                            self.states[event.entity_id] = event.new_state
                            self.receivedAt = Date()
                        }
                    }
                } catch {
                    guard !Task.isCancelled, self.epoch == id else { return }
                    self.transportLive = false
                    self.connecting = false
                    if case SolarError.expiredLogin = error {
                        self.stop()
                        self.service.clearSession()
                        self.deviceHistory.reset()
                        self.energyHistory.reset()
                        self.loggedIn = false
                        self.states = [:]
                        self.powerHistory = []
                        self.batteryHistory = []
                        self.preparedHistory = nil
                        self.historyLoadedAt = nil
                        self.historyError = nil
                        self.receivedAt = nil
                        self.connectionMessage = error.localizedDescription
                        return
                    }
                    self.connectionMessage = "Mất kết nối. App sẽ tự thử lại."
                    retry += 1
                    let seconds = min(30, pow(2, Double(min(retry - 1, 5)))) + Double.random(in: 0...0.5)
                    do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
                }
            }
        }
    }

    func stop() {
        energyHistory.cancel()
        epoch = UUID()
        preloadTask?.cancel()
        preloadTask = nil
        deviceHistory.cancelLoading()
        historyTask?.cancel()
        historyTask = nil
        historyLoading = false
        runTask?.cancel()
        runTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        transportLive = false
        connecting = false
    }

    func logout() async {
        stop()
        deviceHistory.reset()
        energyHistory.reset()
        historyTask?.cancel()
        historyTask = nil
        historyLoading = false
        loggedIn = false
        states = [:]
        powerHistory = []
        batteryHistory = []
        preparedHistory = nil
        historyLoadedAt = nil
        historyError = nil
        receivedAt = nil
        await service.signOut()
    }

    func loadDeviceHistory(_ device: SolarDevice, force: Bool = false) async {
        guard loggedIn, !Task.isCancelled else { return }
        await deviceHistory.load(device, force: force) { entities, hours in
            #if DEBUG
            if self.previewMode {
                if ProcessInfo.processInfo.arguments.contains("--ui-history-slow") { try await Task.sleep(for: .seconds(8)) }
                return SolarDeviceHistoryStore.previewPoints(for: device, now: Date())
            }
            #endif
            return try await self.service.history(entities: entities, hours: hours)
        }
    }

    private func preloadHistories() {
        guard loggedIn, preloadTask == nil else { return }
        let id = epoch
        preloadTask = Task {
            defer { if self.epoch == id { self.preloadTask = nil } }
            async let devices: Void = self.deviceHistory.preload { entities, hours in
                try await self.service.history(entities: entities, hours: hours)
            }
            async let common: Void = self.loadHistory()
            _ = await (devices, common)
        }
    }

    func loadEnergyHistory(_ range: SolarEnergyRange, force: Bool = false) async {
        guard loggedIn else { return }
        await energyHistory.load(range, force: force) { selected in
            #if DEBUG
            if self.previewMode {
                if ProcessInfo.processInfo.arguments.contains("--ui-energy-error") { throw SolarEnergyError.requestFailed }
                return try SolarEnergyPreview.report(selected,
                    empty: ProcessInfo.processInfo.arguments.contains("--ui-energy-empty"))
            }
            #endif
            return try await self.service.energyHistory(selected)
        }
    }

    func loadHistory(force: Bool = false) async {
        if previewMode { return }
        guard loggedIn, !Task.isCancelled else { return }
        if let historyTask { await historyTask.value; return }
        if !force, historyError == nil, let loaded = historyLoadedAt,
           (0..<SolarDeviceHistoryStore.cacheLifetime).contains(Date().timeIntervalSince(loaded)) { return }
        let id = epoch
        historyLoading = true
        historyError = nil
        let work = Task {
            defer {
                if self.epoch == id { self.historyLoading = false; self.historyTask = nil }
            }
            do {
                async let power = self.service.history(entities: SolarConfig.powerEntities, hours: 2)
                async let cell = self.service.history(entities: ["sensor.lux_cell_delta"], hours: 24)
                async let soc = self.service.preferredSOCHistory()
                let result = try await (power, cell, soc)
                let battery = result.1 + result.2
                let charts = try await SolarHistoryPreparation.general(power: result.0, battery: battery)
                guard self.loggedIn, self.epoch == id, !Task.isCancelled else { return }
                self.powerHistory = result.0
                self.batteryHistory = battery
                self.preparedHistory = charts
                self.historyLoadedAt = Date()
            } catch {
                guard !Task.isCancelled, self.loggedIn, self.epoch == id else { return }
                self.historyError = "Chưa tải được lịch sử. Bạn có thể thử lại; số liệu trực tiếp vẫn độc lập."
            }
        }
        historyTask = work
        await work.value
    }

    private func send(_ value: [String: Any], to socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: value)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func receive(_ socket: URLSessionWebSocketTask, timeout: TimeInterval) async throws -> HAFrame {
        let watchdog = Task {
            do {
                try await Task.sleep(for: .seconds(timeout))
                socket.cancel(with: .goingAway, reason: nil)
            } catch { }
        }
        defer { watchdog.cancel() }
        let message = try await socket.receive()
        let data: Data
        switch message {
        case .data(let value): data = value
        case .string(let value): data = Data(value.utf8)
        @unknown default: throw SolarError.invalidResponse
        }
        return try JSONDecoder().decode(HAFrame.self, from: data)
    }
}
