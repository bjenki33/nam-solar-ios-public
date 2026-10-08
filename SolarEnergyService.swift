import Foundation

// A separate short-lived, read-only channel: statistics cannot consume live state frames.
@MainActor
extension HAService {
    func energyHistory(_ selected: SolarEnergyRange) async throws -> SolarEnergyReport {
        for attempt in 0...1 {
            let token = try await accessToken(forceRefresh: attempt > 0)
            try Task.checkCancellation()
            let channel = socket()
            let deadline = Task {
                do { try await Task.sleep(for: .seconds(45)); channel.cancel(with: .goingAway, reason: nil) }
                catch { }
            }
            defer { deadline.cancel(); channel.cancel(with: .goingAway, reason: nil) }
            do {
                return try await withTaskCancellationHandler {
                    guard try await Self.energyReceive(channel).type == "auth_required" else { throw SolarError.invalidResponse }
                    try await Self.energySend(["type": "auth", "access_token": token], channel)
                    let auth = try await Self.energyReceive(channel)
                    if auth.type == "auth_invalid" { throw SolarError.expiredLogin }
                    guard auth.type == "auth_ok" else { throw SolarError.invalidResponse }
                    struct Config: Decodable { let time_zone: String }
                    let config: Config = try await Self.energyRequest(1, type: "get_config", channel: channel)
                    let range = try selected.resolved(in: config.time_zone)
                    let preferences: SolarEnergyPreferences = try await Self.energyRequest(2, type: "energy/get_prefs", channel: channel)
                    let meters = try preferences.meters()
                    let ids = Set(meters.values.flatMap { $0 }).sorted()
                    let metadata: [SolarEnergyMetadata] = try await Self.energyRequest(3, type: "recorder/get_statistics_metadata",
                        parameters: ["statistic_ids": ids], channel: channel)
                    let statistics: [String: [SolarEnergyStatistic]] = try await Self.energyRequest(4,
                        type: "recorder/statistics_during_period", parameters: [
                            "statistic_ids": ids, "start_time": SolarDate.iso(range.start), "end_time": range.requestEnd,
                            "period": range.period, "units": ["energy": "kWh"], "types": ["change"]
                        ], channel: channel)
                    try Task.checkCancellation()
                    return try SolarEnergyReport.build(range: range, meters: meters, metadata: metadata, statistics: statistics)
                } onCancel: {
                    channel.cancel(with: .goingAway, reason: nil)
                }
            } catch SolarError.expiredLogin where attempt == 0 { continue }
        }
        throw SolarError.expiredLogin
    }

    private static func energyRequest<T: Decodable>(_ id: Int, type: String, parameters: [String: Any] = [:],
                                                    channel: URLSessionWebSocketTask) async throws -> T {
        // Deliberately no generic public RPC surface, services, save_prefs or recorder mutation.
        guard ["get_config", "energy/get_prefs", "recorder/get_statistics_metadata", "recorder/statistics_during_period"].contains(type)
        else { throw SolarError.invalidResponse }
        var payload = parameters
        payload["id"] = id; payload["type"] = type
        try await energySend(payload, channel)
        let frame = try await energyReceive(channel)
        guard frame.id == id, frame.type == "result", frame.success == true, let value = frame.result else {
            throw SolarEnergyError.requestFailed
        }
        return try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private static func energySend(_ payload: [String: Any], _ channel: URLSessionWebSocketTask) async throws {
        try Task.checkCancellation()
        let data = try JSONSerialization.data(withJSONObject: payload)
        try await channel.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private static func energyReceive(_ channel: URLSessionWebSocketTask) async throws -> HAFrame {
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(15)); channel.cancel(with: .goingAway, reason: nil) }
            catch { }
        }
        defer { timeout.cancel() }
        let message = try await channel.receive()
        let data: Data
        switch message {
        case .data(let bytes): data = bytes
        case .string(let text): data = Data(text.utf8)
        @unknown default: throw SolarError.invalidResponse
        }
        try Task.checkCancellation()
        return try JSONDecoder().decode(HAFrame.self, from: data)
    }
}
