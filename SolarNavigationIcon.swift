import SwiftUI

// Exact web navigation silhouettes. Attribution: SolarMetricIcon-NOTICE.txt.
enum SolarNavigationKind: String, CaseIterable {
    case overview = "solar-power"
    case battery = "battery-heart-variant"
    case history = "chart-line"
    case diagnostics = "lan-check"

    var svgPath: String {
        switch self {
        case .overview: return SolarMetricKind.solar.svgPath
        case .battery:
            return "M16.67 4H15V2H9V4H7.33A1.34 1.34 0 0 0 6 5.33V20.67A1.34 1.34 0 0 0 7.33 22H16.67A1.34 1.34 0 0 0 18 20.67V5.33A1.34 1.34 0 0 0 16.67 4M12.58 15.64L12 16.17L11.42 15.64C9.36 13.77 8 12.54 8 11A2.18 2.18 0 0 1 10.2 8.8A2.4 2.4 0 0 1 12 9.63A2.4 2.4 0 0 1 13.8 8.8A2.18 2.18 0 0 1 16 11C16 12.54 14.64 13.77 12.58 15.64Z"
        case .history:
            return "M16,11.78L20.24,4.45L21.97,5.45L16.74,14.5L10.23,10.75L5.46,19H22V21H2V3H4V17.54L9.5,8L16,11.78Z"
        case .diagnostics:
            return "M4 1C2.89 1 2 1.89 2 3V7C2 8.11 2.89 9 4 9H1V11H13V9H10C11.11 9 12 8.11 12 7V3C12 1.89 11.11 1 10 1H4M4 3H10V7H4V3M14 13C12.89 13 12 13.89 12 15V19C12 20.11 12.89 21 14 21H11V23H23V21H20C21.11 21 22 20.11 22 19V15C22 13.89 21.11 13 20 13H14M14 15H20V19H14V15M5.5 20.5L10.5 15.5L9 14L5.5 17.5L3.5 15.5L2 17L5.5 20.5Z"
        }
    }

    private static let paths = Dictionary(uniqueKeysWithValues: allCases.map {
        ($0, SolarMetricPath.parse($0.svgPath) ?? CGMutablePath())
    })
    var path: CGPath { Self.paths[self] ?? CGMutablePath() }
}

enum SolarNavigationLayout {
    static let brandWidth: CGFloat = 42
    static let accountWidth: CGFloat = 26
    static let iconSize: CGFloat = 25
    static let labelSize: CGFloat = 12
    static let height: CGFloat = 58
}

struct SolarNavigationIcon: View {
    let kind: SolarNavigationKind
    var body: some View {
        SolarNavigationShape(kind: kind).fill()
            .frame(width: SolarNavigationLayout.iconSize, height: SolarNavigationLayout.iconSize)
            .accessibilityHidden(true)
    }
}

struct SolarNavigationShape: Shape {
    let kind: SolarNavigationKind
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                         tx: rect.midX - 12 * scale, ty: rect.midY - 12 * scale)
        return Path(kind.path.copy(using: &transform) ?? CGMutablePath())
    }
}
