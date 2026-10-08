import SwiftUI

struct SolarFlowView: View {
    let snapshot: SolarSnapshot
    @Binding var selection: SolarTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var detail: SolarDevice?

    var body: some View {
        GeometryReader { geometry in
            let sx = geometry.size.width / 375
            let sy = geometry.size.height / 420
            let scale = min(1.25, min(sx, sy))
            ZStack(alignment: .topLeading) {
                SolarTheme.panel
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active || !snapshot.online)) { tick in
                    Canvas { context, size in
                        drawWires(&context, size: size, time: reduceMotion ? 0 : tick.date.timeIntervalSinceReferenceDate)
                    }.accessibilityHidden(true).allowsHitTesting(false)
                }
                Button { detail = .solar } label: {
                    HStack(spacing: 5) {
                        SolarPVArtwork(scale: scale)
                        Text("ĐIỆN MẶT TRỜI").font(.system(size: 11 * scale)).foregroundStyle(SolarTheme.sun)
                    }
                }.buttonStyle(.plain).position(x: 192 * sx, y: 26 * sy).accessibilityLabel("Chi tiết điện mặt trời")
                pvString(1, scale: scale).position(x: 105 * sx, y: 96 * sy)
                pvString(2, scale: scale).position(x: 270 * sx, y: 96 * sy)
                Button { detail = .solar } label: {
                    VStack(spacing: 2) {
                        powerBox(snapshot.number("pv_power"), color: SolarTheme.sun, scale: scale)
                        Text(quantity(snapshot.number("pv_power").map { $0 / 9920 * 100 }) + "% / 9,92 kWp")
                            .font(.system(size: 9 * scale)).foregroundStyle(SolarTheme.muted).background(SolarTheme.panel)
                    }
                }.buttonStyle(.plain).position(x: 187.5 * sx, y: 157 * sy).accessibilityLabel("Tổng công suất PV")
                grid(scale: scale).position(x: 62 * sx, y: 258 * sy)
                inverter(scale: scale).position(x: 187.5 * sx, y: 248 * sy)
                home(scale: scale).position(x: 312 * sx, y: 257 * sy)
                battery(scale: scale).position(x: 187.5 * sx, y: 374 * sy)
            }.clipShape(RoundedRectangle(cornerRadius: 7))
                .accessibilityElement(children: .contain).accessibilityIdentifier("energy-flow")
        }.sheet(item: $detail) { item in
            SolarDeviceDetailView(device: item).presentationDetents([.large]).presentationDragIndicator(.visible)
        }
    }

    private func artwork(_ name: String, width: CGFloat, height: CGFloat) -> some View {
        Image(name, bundle: .main).renderingMode(.original).resizable().scaledToFit()
            .frame(width: width, height: height).accessibilityHidden(true)
    }
    private func powerBox(_ value: Double?, color: Color, scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(quantity(value)).font(.system(size: 16 * scale, weight: .semibold)).monospacedDigit()
            Text("W").font(.system(size: 10 * scale))
        }.foregroundStyle(color).frame(width: 79 * scale, height: 28 * scale)
            .background(SolarTheme.panel, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 0.8))
            .accessibilityElement(children: .combine)
    }
    private func pvString(_ index: Int, scale: CGFloat) -> some View {
        VStack(spacing: 1) {
            powerBox(snapshot.number("pv\(index)_power"), color: SolarTheme.sun, scale: scale)
            Text("PV\(index) · 8 tấm").font(.system(size: 10 * scale, weight: .semibold)).foregroundStyle(SolarTheme.sun)
            Text(quantity(snapshot.number("pv\(index)_voltage"), 1) + " V").font(.system(size: 11 * scale)).foregroundStyle(SolarTheme.sun)
            Text("≈ " + quantity(snapshot.estimatedCurrent(power: "pv\(index)_power", voltage: "pv\(index)_voltage"), 1) + " A")
                .font(.system(size: 10 * scale)).foregroundStyle(SolarTheme.muted)
        }.frame(width: 115 * scale).background(SolarTheme.panel).accessibilityElement(children: .combine)
    }
    private func grid(scale: CGFloat) -> some View {
        Button { detail = .grid } label: {
            VStack(spacing: 3) {
                artwork("solar-grid", width: 77 * scale, height: 86 * scale)
                powerBox(snapshot.number("grid_power"), color: SolarTheme.grid, scale: scale)
                Text(snapshot.gridStatus).font(.system(size: 9 * scale)).foregroundStyle(SolarTheme.muted)
                Text(quantity(snapshot.number("grid_voltage"), 1) + " V").font(.system(size: 11 * scale))
                Text(quantity(snapshot.number("grid_frequency"), 2) + " Hz").font(.system(size: 10 * scale))
            }.frame(width: 116 * scale)
        }.buttonStyle(.plain).accessibilityLabel("Chi tiết điện lưới")
    }
    private func inverter(scale: CGFloat) -> some View {
        Button { detail = .inverter } label: {
            VStack(spacing: 2) {
                artwork("solar-inverter", width: 78 * scale, height: 97 * scale)
                Text(quantity(snapshot.number("inverter_power")) + " W").font(.system(size: 12 * scale, weight: .semibold)).background(SolarTheme.panel)
                Text("AC " + quantity(snapshot.number("radiator1_temperature", slow: true)) + " °C").font(.system(size: 9 * scale)).foregroundStyle(SolarTheme.muted).background(SolarTheme.panel)
                Text("DC " + quantity(snapshot.number("radiator2_temperature", slow: true)) + " °C").font(.system(size: 9 * scale)).foregroundStyle(SolarTheme.muted).background(SolarTheme.panel)
            }
        }.buttonStyle(.plain).accessibilityLabel("Chi tiết biến tần")
    }
    private func home(scale: CGFloat) -> some View {
        Button { detail = .home } label: {
            VStack(spacing: 3) {
                artwork("solar-home", width: 87 * scale, height: 77 * scale)
                powerBox(snapshot.number("home_power"), color: SolarTheme.leaf, scale: scale)
                Text("Nhà đang dùng").font(.system(size: 10 * scale)).foregroundStyle(SolarTheme.muted)
                Label("EPS " + quantity(snapshot.number("eps_power")) + " W", systemImage: "powerplug.fill")
                    .font(.system(size: 10 * scale)).foregroundStyle(SolarTheme.leaf)
            }.frame(width: 115 * scale)
        }.buttonStyle(.plain).accessibilityLabel("Chi tiết công suất nhà")
    }
    private func battery(scale: CGFloat) -> some View {
        Button { selection = .battery } label: {
            HStack(spacing: 13 * scale) {
                VStack(spacing: 4) {
                    Text(quantity(snapshot.number("battery_voltage"), 1) + " V").font(.system(size: 14 * scale, weight: .semibold))
                    Text(quantity(snapshot.batteryPower) + " W").font(.system(size: 14 * scale))
                    Text("≈ " + quantity(snapshot.estimatedCurrent(power: "battery_power", voltage: "battery_voltage"), 1) + " A")
                        .font(.system(size: 10 * scale)).foregroundStyle(SolarTheme.muted)
                }.foregroundStyle(SolarTheme.leaf).frame(width: 82 * scale, height: 69 * scale)
                    .background(SolarTheme.panel, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(SolarTheme.leaf, lineWidth: 0.8))
                artwork("solar-battery", width: 66 * scale, height: 86 * scale)
                VStack(alignment: .leading, spacing: 2) {
                    Text(quantity(snapshot.number("battery_soc")) + "%").font(.system(size: 25 * scale, weight: .semibold)).foregroundStyle(SolarTheme.leaf)
                    Text(snapshot.batteryStatus).font(.system(size: 9 * scale)).foregroundStyle(SolarTheme.muted)
                    Text("Pin lưu trữ").font(.system(size: 10 * scale)).foregroundStyle(SolarTheme.muted)
                    Text("16,08 kWh").font(.system(size: 12 * scale, weight: .semibold)).foregroundStyle(SolarTheme.sun)
                    ProgressView(value: min(1, max(0, (snapshot.number("battery_soc") ?? 0) / 100))).tint(SolarTheme.leaf).frame(width: 75 * scale)
                }.frame(width: 100 * scale, alignment: .leading).background(SolarTheme.panel)
            }.monospacedDigit()
        }.buttonStyle(.plain).accessibilityLabel("Chi tiết pin lưu trữ")
            .accessibilityValue(quantity(snapshot.batteryPower) + " W · " + snapshot.batteryStatus)
    }

    // Wires use the same design coordinates as the device nodes; never animate missing/idle readings.
    private func drawWires(_ context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let sx = size.width / 375
        let sy = size.height / 420
        let definitions: [FlowWire] = [
            FlowWire(vertices: [[105, 132], [105, 150], [187.5, 150]], watts: snapshot.number("pv1_power"), color: SolarTheme.sun),
            FlowWire(vertices: [[270, 132], [270, 150], [187.5, 150]], watts: snapshot.number("pv2_power"), color: SolarTheme.sun),
            FlowWire(vertices: [[187.5, 166], [187.5, 190]], watts: snapshot.number("pv_power"), color: SolarTheme.sun),
            FlowWire(vertices: [[64, 240], [109, 240], [109, 265], [161, 265]], watts: snapshot.number("grid_power"), color: SolarTheme.grid, reverse: (snapshot.number("grid_power") ?? 0) < 0),
            FlowWire(vertices: [[215, 265], [252, 265], [252, 250], [309, 250]], watts: snapshot.number("home_power"), color: SolarTheme.sun),
            FlowWire(vertices: [[187.5, 273], [187.5, 350]], watts: snapshot.batteryPower, color: SolarTheme.leaf, reverse: snapshot.batteryFlowReversed)
        ]
        for wire in definitions {
            let points = wire.vertices.map { CGPoint(x: $0[0] * sx, y: $0[1] * sy) }
            var path = Path()
            path.addLines(points)
            let unknown = wire.watts == nil
            context.stroke(path, with: .color(unknown ? SolarTheme.muted.opacity(0.35) : wire.color.opacity(0.5)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: unknown ? [3, 4] : []))
            guard let watts = wire.watts, abs(watts) > 5 else { continue }
            let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
            let total = lengths.reduce(0, +)
            guard total > 0 else { continue }
            let phase = CGFloat(time.truncatingRemainder(dividingBy: 2) / 2) * 24 * (wire.reverse ? -1 : 1)
            for i in 0...Int(total / 24) {
                var distance = (CGFloat(i) * 24 + phase + total).truncatingRemainder(dividingBy: total)
                for index in lengths.indices {
                    if distance <= lengths[index] {
                        let fraction = lengths[index] > 0 ? distance / lengths[index] : 0
                        let p = CGPoint(x: points[index].x + (points[index + 1].x - points[index].x) * fraction, y: points[index].y + (points[index + 1].y - points[index].y) * fraction)
                        context.fill(Path(ellipseIn: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)), with: .color(wire.color))
                        break
                    }
                    distance -= lengths[index]
                }
            }
        }
    }
}

private struct FlowWire {
    let vertices: [[CGFloat]]
    let watts: Double?
    let color: Color
    var reverse = false
}
