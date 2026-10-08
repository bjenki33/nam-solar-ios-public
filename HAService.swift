import Foundation
import Security

struct LoginSession: Codable {
    var accessToken: String
    let refreshToken: String
    var expiresAt: Date
}

enum SessionKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "me.bocphot.namsolar.auth",
         kSecAttrAccount as String: "solar.bocphot.me"]
    }

    static func load() throws -> LoginSession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw SolarError.secureStorage }
        return try JSONDecoder().decode(LoginSession.self, from: data)
    }

    static func save(_ session: LoginSession) throws {
        let data = try JSONEncoder().encode(session)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw SolarError.secureStorage }
        } else if status != errSecSuccess { throw SolarError.secureStorage }
    }

    static func remove() { SecItemDelete(query as CFDictionary) }
}

@MainActor
final class HAService {
    private(set) var session: LoginSession?
    private var refreshTask: Task<LoginSession, Error>?
    private var generation = UUID()
    private let http: URLSession

    init() {
        session = try? SessionKeychain.load()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.urlCache = nil
        config.httpCookieStorage = nil
        http = URLSession(configuration: config, delegate: SameHostRedirects(), delegateQueue: nil)
    }

    func exchange(code: String) async throws {
        let epoch = generation
        let result = try await tokenRequest(["grant_type": "authorization_code", "code": code, "client_id": SolarConfig.clientID])
        guard generation == epoch, let refresh = result.refresh_token else { throw SolarError.expiredLogin }
        let value = LoginSession(accessToken: result.access_token, refreshToken: refresh, expiresAt: Date().addingTimeInterval(result.expires_in))
        try SessionKeychain.save(value)
        session = value
    }

    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let session else { throw SolarError.expiredLogin }
        if !forceRefresh && session.expiresAt.timeIntervalSinceNow > 60 { return session.accessToken }
        let epoch = generation
        let work: Task<LoginSession, Error>
        if let refreshTask { work = refreshTask }
        else {
            work = Task {
                let result = try await self.tokenRequest(["grant_type": "refresh_token", "refresh_token": session.refreshToken, "client_id": SolarConfig.clientID])
                return LoginSession(accessToken: result.access_token, refreshToken: session.refreshToken,
                                    expiresAt: Date().addingTimeInterval(result.expires_in))
            }
            refreshTask = work
        }
        do {
            let value = try await work.value
            guard generation == epoch else { throw SolarError.expiredLogin }
            try SessionKeychain.save(value)
            self.session = value
            refreshTask = nil
            return value.accessToken
        } catch {
            if generation == epoch {
                refreshTask = nil
                if case SolarError.expiredLogin = error { clearSession() }
            }
            throw error
        }
    }

    func history(entities: [String], hours: Int) async throws -> [HistoryPoint] {
        let start = Date().addingTimeInterval(-Double(hours) * 3600)
        var components = URLComponents(url: SolarConfig.base.appendingPathComponent("api/history/period/" + SolarDate.iso(start)), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "filter_entity_id", value: entities.joined(separator: ",")),
                                 URLQueryItem(name: "minimal_response", value: ""), URLQueryItem(name: "no_attributes", value: "")]
        let data = try await authenticatedGET(components.url!)
        return try await SolarHistoryPreparation.decode(data, allowed: Set(entities))
    }

    func socket() -> URLSessionWebSocketTask {
        let socket = http.webSocketTask(with: URL(string: "wss://solar.bocphot.me/api/websocket")!)
        socket.resume()
        return socket
    }

    func clearSession() {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        session = nil
        SessionKeychain.remove()
    }

    func signOut() async {
        let refreshToken = session?.refreshToken
        clearSession()
        guard let refreshToken else { return }
        var request = URLRequest(url: SolarConfig.base.appendingPathComponent("auth/revoke"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(["token": refreshToken])
        _ = try? await http.data(for: request)
    }

    private func authenticatedGET(_ url: URL) async throws -> Data {
        for attempt in 0...1 {
            var request = URLRequest(url: url)
            request.setValue("Bearer \(try await accessToken(forceRefresh: attempt > 0))", forHTTPHeaderField: "Authorization")
            let (data, response) = try await http.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw SolarError.invalidResponse }
            if response.statusCode == 401 { continue }
            guard response.statusCode == 200 else { throw SolarError.server(response.statusCode) }
            return data
        }
        throw SolarError.expiredLogin
    }

    private struct TokenResult: Decodable {
        let access_token: String
        let expires_in: TimeInterval
        let refresh_token: String?
    }

    private func tokenRequest(_ values: [String: String]) async throws -> TokenResult {
        var request = URLRequest(url: SolarConfig.base.appendingPathComponent("auth/token"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(values)
        let (data, response) = try await http.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw SolarError.invalidResponse }
        if [400, 401, 403].contains(response.statusCode) { throw SolarError.expiredLogin }
        guard response.statusCode == 200 else { throw SolarError.server(response.statusCode) }
        let value = try JSONDecoder().decode(TokenResult.self, from: data)
        guard !value.access_token.isEmpty, value.expires_in > 0 else { throw SolarError.invalidResponse }
        return value
    }

    private static func form(_ values: [String: String]) -> Data {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: safe)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: safe)!)"
        }.joined(separator: "&").utf8)
    }
}

// Never forward a bearer token through a redirect to another origin.
private final class SameHostRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let url = request.url
        completionHandler(url?.scheme == "https" && url?.host == SolarConfig.base.host && url?.port == nil ? request : nil)
    }
}
