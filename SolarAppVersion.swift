import Foundation

enum SolarAppVersion {
    static func description(info: [String: Any]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "--"
        let build = info["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    static var current: String { description(info: Bundle.main.infoDictionary ?? [:]) }
}
