import SwiftUI

// MDI paths used by the web dashboard. Attribution: SolarMetricIcon-NOTICE.txt.
enum SolarMetricKind: String, CaseIterable {
    case solar = "solar-power"
    case charge = "battery-arrow-up"
    case discharge = "battery-arrow-down"
    case grid = "transmission-tower-import"
    case home = "home-lightning-bolt"

    var svgPath: String {
        switch self {
        case .solar:
            return "M11.45,2V5.55L15,3.77L11.45,2M10.45,8L8,10.46L11.75,11.71L10.45,8M2,11.45L3.77,15L5.55,11.45H2M10,2H2V10C2.57,10.17 3.17,10.25 3.77,10.25C7.35,10.26 10.26,7.35 10.27,3.75C10.26,3.16 10.17,2.57 10,2M17,22V16H14L19,7V13H22L17,22Z"
        case .charge:
            return "M13.54 22H7.33C6.6 22 6 21.4 6 20.67V5.33C6 4.6 6.6 4 7.33 4H9V2H15V4H16.67C17.4 4 18 4.6 18 5.33V12C14.69 12 12 14.69 12 18C12 19.54 12.58 20.94 13.54 22M20.94 17.5L17.94 14.5L14.94 17.5H16.94V21.5H18.94V17.5H20.94"
        case .discharge:
            return "M13.54 22H7.33C6.6 22 6 21.4 6 20.67V5.33C6 4.6 6.6 4 7.33 4H9V2H15V4H16.67C17.4 4 18 4.6 18 5.33V12C14.69 12 12 14.69 12 18C12 19.54 12.58 20.94 13.54 22M14.94 18.5L17.94 21.5L20.94 18.5H18.94V14.5H16.94V18.5H14.94"
        case .grid:
            return "M11.39 5.45L9.61 4.55L10.87 2H19.34L20.61 4.55L18.83 5.44L18.11 4H12.11L11.39 5.45M21.73 8H17.2L16.41 5H13.81L13 8H8.5L7.21 10.55L9 11.44L9.73 10H20.5L21.21 11.45L23 10.56L21.73 8M20.88 22H18.81L18.57 21.1L15.11 15.9L11.64 21.1L11.41 22H9.34L12.23 11H14.3L13.94 12.35L15.11 14.1L16.27 12.35L15.92 11H18L20.88 22M14.5 15L13.61 13.65L12.43 18.13L14.5 15M17.79 18.12L16.61 13.64L15.71 15L17.79 18.12M9 16L5 12V15H1V17H5V20L9 16Z"
        case .home:
            return "M12 3L2 12H5V20H19V12H22L12 3M11.5 18V14H9L12.5 7V11H15L11.5 18Z"
        }
    }

    private static let paths = Dictionary(uniqueKeysWithValues: allCases.map {
        ($0, SolarMetricPath.parse($0.svgPath) ?? CGMutablePath())
    })
    var path: CGPath { Self.paths[self] ?? CGMutablePath() }
}

struct SolarMetricIcon: View {
    let kind: SolarMetricKind
    var body: some View {
        SolarMetricShape(kind: kind).fill().frame(width: 18, height: 18)
            .accessibilityHidden(true)
    }
}

struct SolarMetricShape: Shape {
    let kind: SolarMetricKind
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                         tx: rect.midX - 12 * scale, ty: rect.midY - 12 * scale)
        return Path(kind.path.copy(using: &transform) ?? CGMutablePath())
    }
}

enum SolarMetricPath {
    // Absolute commands used by the bundled MDI metric and navigation icons.
    static func parse(_ data: String) -> CGPath? {
        let tokens = data.replacingOccurrences(of: "([A-Za-z])", with: " $1 ", options: .regularExpression)
            .replacingOccurrences(of: ",", with: " ").split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let path = CGMutablePath()
        var index = 0
        var command = ""
        var current = CGPoint.zero
        func number() -> CGFloat? {
            guard index < tokens.count, let value = Double(tokens[index]), value.isFinite else { return nil }
            index += 1
            return CGFloat(value)
        }
        func point() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x, y: y)
        }
        while index < tokens.count {
            let token = tokens[index]
            if token.count == 1, let scalar = token.unicodeScalars.first, CharacterSet.letters.contains(scalar) {
                command = token
                index += 1
                if command == "Z" { path.closeSubpath(); current = path.currentPoint; command = ""; continue }
            }
            switch command {
            case "M", "L":
                guard let p = point() else { return nil }
                if command == "M" { path.move(to: p); command = "L" } else { path.addLine(to: p) }
                current = p
            case "H":
                guard let x = number() else { return nil }
                current.x = x; path.addLine(to: current)
            case "V":
                guard let y = number() else { return nil }
                current.y = y; path.addLine(to: current)
            case "C":
                guard let c1 = point(), let c2 = point(), let end = point() else { return nil }
                path.addCurve(to: end, control1: c1, control2: c2); current = end
            case "A":
                guard let rx = number(), let ry = number(), let degrees = number(),
                      let large = number(), let sweep = number(), let end = point(),
                      (large == 0 || large == 1), (sweep == 0 || sweep == 1) else { return nil }
                addArc(to: path, from: current, end: end, rx: rx, ry: ry, degrees: degrees,
                       large: large == 1, sweep: sweep == 1)
                current = end
            default: return nil
            }
        }
        return path.isEmpty ? nil : path.copy()
    }

    // SVG endpoint-to-center conversion: https://www.w3.org/TR/SVG/implnote.html#ArcConversionEndpointToCenter
    private static func addArc(to path: CGMutablePath, from start: CGPoint, end: CGPoint,
                               rx: CGFloat, ry: CGFloat, degrees: CGFloat, large: Bool, sweep: Bool) {
        guard start != end else { return }
        var rx = abs(rx), ry = abs(ry)
        guard rx > 0, ry > 0 else { path.addLine(to: end); return }
        let phi = degrees * .pi / 180
        let cosine = cos(phi), sine = sin(phi)
        let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
        let x = cosine * dx + sine * dy, y = -sine * dx + cosine * dy
        let correction = x * x / (rx * rx) + y * y / (ry * ry)
        if correction > 1 { let scale = sqrt(correction); rx *= scale; ry *= scale }
        let denominator = rx * rx * y * y + ry * ry * x * x
        let numerator = rx * rx * ry * ry - denominator
        let factor: CGFloat = (large == sweep ? -1 : 1) * sqrt(max(0, numerator / denominator))
        let cx = factor * rx * y / ry, cy = -factor * ry * x / rx
        let center = CGPoint(x: cosine * cx - sine * cy + (start.x + end.x) / 2,
                             y: sine * cx + cosine * cy + (start.y + end.y) / 2)
        let ux = (x - cx) / rx, uy = (y - cy) / ry
        let vx = (-x - cx) / rx, vy = (-y - cy) / ry
        let angle = atan2(uy, ux)
        var delta = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let transform = CGAffineTransform(a: rx * cosine, b: rx * sine, c: -ry * sine, d: ry * cosine,
                                         tx: center.x, ty: center.y)
        path.addRelativeArc(center: .zero, radius: 1, startAngle: angle, delta: delta, transform: transform)
    }
}
