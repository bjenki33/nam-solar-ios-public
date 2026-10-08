import SwiftUI

enum SolarTheme {
    static let ink = Color(red: 0.060, green: 0.078, blue: 0.080)
    static let panel = Color(red: 0.107, green: 0.140, blue: 0.149)
    static let border = Color(red: 0.205, green: 0.251, blue: 0.265)
    static let muted = Color(red: 0.65, green: 0.70, blue: 0.71)
    static let sun = Color(red: 0.91, green: 0.72, blue: 0.31)
    static let leaf = Color(red: 0.32, green: 0.73, blue: 0.65)
    static let grid = Color(red: 0.40, green: 0.66, blue: 0.87)
    static let charge = Color(red: 0.70, green: 0.56, blue: 0.91)
    static let discharge = Color(red: 0.93, green: 0.57, blue: 0.65)
}

struct SolarBackground: View {
    var body: some View { SolarTheme.ink.ignoresSafeArea() }
}

struct Panel<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(padding)
            .background(SolarTheme.panel, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(SolarTheme.border, lineWidth: 0.7))
    }
}

func quantity(_ value: Double?, _ digits: Int = 0) -> String {
    guard let value, value.isFinite else { return "--" }
    return value.formatted(.number.locale(Locale(identifier: "vi_VN")).precision(.fractionLength(digits)))
}

func solarTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "vi_VN")
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: date)
}

func solarDay(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "vi_VN")
    formatter.dateFormat = "dd/MM/yyyy"
    return formatter.string(from: date)
}

struct Reading: View {
    let value: Double?
    let unit: String
    var digits = 0
    var large = false
    var estimated = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text((estimated && value != nil ? "≈ " : "") + quantity(value, digits))
                .font(.system(size: large ? 32 : 20, weight: .semibold))
                .monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
            Text(unit).font(.system(size: large ? 14 : 10)).foregroundStyle(SolarTheme.muted)
        }.accessibilityElement(children: .combine)
    }
}

func metricRow(_ title: String, _ value: Double?, _ unit: String, digits: Int = 0, suffix: String = "") -> some View {
    textRow(title, quantity(value, digits) + (unit.isEmpty ? "" : " " + unit) + suffix)
}

func textRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(title).foregroundStyle(SolarTheme.muted)
        Spacer(minLength: 8)
        Text(value).monospacedDigit().multilineTextAlignment(.trailing)
    }.font(.system(size: 14)).padding(.vertical, 4).accessibilityElement(children: .combine)
}
