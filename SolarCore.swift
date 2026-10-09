import Foundation

enum JSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var number: Double? {
        switch self {
        case .number(let value): return value.isFinite ? value : nil
        case .string(let value): return finiteNumber(value)
        default: return nil
        }
    }

    var string: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return String(value)
        default: return nil
        }
    }
}

func finiteNumber(_ raw: String) -> Double? {
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, let number = Double(value), number.isFinite else { return nil }
    return number
}

enum SolarDate {
    static func parse(_ raw: String?) -> Date? {
        Parser().parse(raw)
    }

    // Request-local formatters: reuse for thousands of history records without
    // sharing mutable Foundation formatters between concurrent workers.
    struct Parser {
        private let fractional: ISO8601DateFormatter
        private let standard: ISO8601DateFormatter

        init() {
            fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            standard = ISO8601DateFormatter()
        }

        func parse(_ raw: String?) -> Date? {
            guard let raw else { return nil }
            return raw.contains(".") ? fractional.date(from: raw) : standard.date(from: raw)
        }
    }

    static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}

struct HAState: Codable, Sendable {
    let entity_id: String
    let state: String
    var attributes: [String: JSONValue] = [:]
    var last_updated: String?
    var last_changed: String?

    init(entity_id: String, state: String, attributes: [String: JSONValue] = [:], last_updated: String? = nil, last_changed: String? = nil) {
        self.entity_id = entity_id
        self.state = state
        self.attributes = attributes
        self.last_updated = last_updated
        self.last_changed = last_changed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entity_id = try c.decode(String.self, forKey: .entity_id)
        state = try c.decode(String.self, forKey: .state)
        attributes = try c.decodeIfPresent([String: JSONValue].self, forKey: .attributes) ?? [:]
        last_updated = try c.decodeIfPresent(String.self, forKey: .last_updated)
        last_changed = try c.decodeIfPresent(String.self, forKey: .last_changed)
    }
}

struct SolarSnapshot: Sendable {
    let states: [String: HAState]
    let now: Date
    let transportLive: Bool
    private let readDates: [String: Date]
    static let prefix = "sensor.lux_"

    init(states: [String: HAState], now: Date, transportLive: Bool) {
        self.states = states
        self.now = now
        self.transportLive = transportLive
        let parser = SolarDate.Parser()
        var dates: [String: Date] = [:]
        for key in ["local_last_read", "bms_last_read"] {
            dates[key] = parser.parse(states[Self.prefix + key]?.state)
        }
        readDates = dates
    }

    func raw(_ key: String) -> String? { states[Self.prefix + key]?.state }
    func date(_ key: String) -> Date? {
        if key == "local_last_read" || key == "bms_last_read" { return readDates[key] }
        return SolarDate.parse(raw(key))
    }
    func fresh(_ key: String, seconds: TimeInterval) -> Bool {
        guard transportLive, let date = date(key) else { return false }
        let age = now.timeIntervalSince(date)
        return age >= -5 && age <= seconds
    }
    var online: Bool { raw("local_connection") == "online" && fresh("local_last_read", seconds: 15) }
    var bmsOnline: Bool { raw("bms_connection") == "online" && fresh("bms_last_read", seconds: 95) }
    func number(_ key: String, slow: Bool = false) -> Double? {
        guard slow ? bmsOnline : online, let raw = raw(key) else { return nil }
        return finiteNumber(raw)
    }
    func attribute(_ name: String) -> Double? { states[Self.prefix + "local_connection"]?.attributes[name]?.number }

    func consumption(_ period: String, slow: Bool = false) -> Double? {
        let values = ["pv_", "grid_import_", "discharge_", "charge_", "grid_export_"]
            .map { number($0 + period, slow: slow) }
        guard values.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let result = (values[0]! + values[1]! + values[2]! - values[3]! - values[4]!)
        let rounded = (result * 1000).rounded() / 1000
        return rounded >= 0 ? rounded : nil
    }

    var estimatedSources: [Double]? {
        let values = ["pv_today", "charge_today", "grid_export_today", "discharge_today", "grid_import_today"].map { number($0) }
        guard values.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        let direct = ((values[0]! - values[1]! - values[2]!) * 1000).rounded() / 1000
        guard direct >= 0 else { return nil }
        return [direct, values[3]!, values[4]!]
    }

    func estimatedCurrent(power: String, voltage: String) -> Double? {
        guard let watts = number(power), let volts = number(voltage), volts > 1 else { return nil }
        return abs(watts) / volts
    }
    var batteryStatus: String {
        guard let watts = batteryPower else { return "Chưa có dữ liệu mới" }
        return watts > 5 ? "Đang sạc" : watts < -5 ? "Đang xả" : "Chờ"
    }
    var gridStatus: String {
        guard let watts = number("grid_power") else { return "Chưa có dữ liệu mới" }
        return watts > 5 ? "Đang mua lưới" : watts < -5 ? "Đang phát lưới" : "Cân bằng lưới"
    }
}

struct HistoryPoint: Identifiable, Sendable {
    let entity: String
    let date: Date
    let value: Double
    let segment: Int
    var recordedAt: Date? = nil
    var isBoundary: Bool = false
    var aggregation: TimeInterval? = nil
    var id: String { "\(entity)|\(date.timeIntervalSince1970)|\(segment)|\(isBoundary)" }
}

enum HistoryParser {
    static func parse(_ data: Data, allowed: Set<String>, end: Date? = nil) throws -> [HistoryPoint] {
        let groups = try JSONDecoder().decode([[HistoryRecord]].self, from: data)
        var points: [HistoryPoint] = []
        let dates = SolarDate.Parser()
        for group in groups {
            try Task.checkCancellation()
            guard let entity = group.first?.entity_id, allowed.contains(entity) else { continue }
            var segment = 0
            var last: HistoryPoint?
            for (index, record) in group.enumerated() {
                if index % 128 == 0 { try Task.checkCancellation() }
                guard let date = dates.parse(record.last_updated ?? record.last_changed) else {
                    // An unknown boundary cannot safely extend a previous reading.
                    segment += 1; last = nil; continue
                }
                if let end, date > end { break }
                if let previous = last, date < previous.date { segment += 1; last = nil }
                guard let value = finiteNumber(record.state) else {
                    if let previous = last, date >= previous.date {
                        if date == previous.date { points.removeLast() }
                        points.append(HistoryPoint(entity: entity, date: date, value: previous.value,
                            segment: segment, recordedAt: previous.date, isBoundary: true))
                    }
                    segment += 1; last = nil; continue
                }
                let point = HistoryPoint(entity: entity, date: date, value: value, segment: segment)
                points.append(point)
                last = point
            }
            if let end, let previous = last, end > previous.date {
                points.append(HistoryPoint(entity: entity, date: end, value: previous.value,
                    segment: segment, recordedAt: previous.date, isBoundary: true))
            }
        }
        return points.sorted { $0.date < $1.date }
    }

    private struct HistoryRecord: Decodable {
        let entity_id: String?
        let state: String
        let last_updated: String?
        let last_changed: String?
    }
}

struct HAFrame: Decodable {
    let type: String
    let id: Int?
    let success: Bool?
    let result: JSONValue?
    let event: StateEvent?
    struct StateEvent: Decodable {
        let data: StateData
        struct StateData: Decodable {
            let entity_id: String
            let new_state: HAState?
        }
    }

    func snapshotStates() throws -> [HAState] {
        guard let result else { throw SolarError.invalidResponse }
        return try JSONDecoder().decode([HAState].self, from: JSONEncoder().encode(result))
    }
}

enum SolarError: LocalizedError {
    case invalidResponse, expiredLogin, server(Int), secureStorage, cancelledLogin
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Máy chủ trả dữ liệu không hợp lệ."
        case .expiredLogin: return "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại."
        case .server(let code): return "Máy chủ chưa phản hồi được (HTTP \(code))."
        case .secureStorage: return "Không thể lưu phiên đăng nhập an toàn trên iPhone."
        case .cancelledLogin: return "Đã hủy đăng nhập."
        }
    }
}

enum SolarConfig {
    static let base = URL(string: "https://solar.bocphot.me")!
    static let clientID = "https://solar.bocphot.me/"
    static let redirect = "https://solar.bocphot.me/nam-solar/auth-callback"
    static let powerEntities = ["pv_power", "home_power", "grid_power", "battery_power"].map { SolarSnapshot.prefix + $0 }
    static let batteryEntities = ["battery_soc", "cell_delta"].map { SolarSnapshot.prefix + $0 }

    static func authorizeURL(state: String) -> URL {
        var url = URLComponents(url: base.appendingPathComponent("auth/authorize"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "redirect_uri", value: redirect), URLQueryItem(name: "state", value: state)]
        return url.url!
    }

    static func authorizationCode(from url: URL, expectedState: String) -> String? {
        guard let redirectURL = URL(string: redirect), url.scheme == redirectURL.scheme,
              url.host == redirectURL.host, url.port == redirectURL.port, url.path == redirectURL.path,
              let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              query.filter({ $0.name == "state" }).count == 1,
              query.first(where: { $0.name == "state" })?.value == expectedState,
              query.filter({ $0.name == "code" }).count == 1,
              let code = query.first(where: { $0.name == "code" })?.value, !code.isEmpty else { return nil }
        return code
    }
}
