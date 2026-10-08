import SwiftUI
import Charts

private enum SolarChartStyle {
    static func color(_ entity: String) -> Color {
        if entity.hasSuffix("pv_power") || entity.hasSuffix("inverter_power") { return SolarTheme.sun }
        if entity.hasSuffix("grid_power") { return SolarTheme.grid }
        if entity.hasSuffix("home_power") { return .white.opacity(0.9) }
        return SolarTheme.leaf
    }

    static func name(_ entity: String) -> String {
        switch entity {
        case "sensor.lux_pv_power": return "PV"
        case "sensor.lux_inverter_power": return "Biến tần"
        case "sensor.lux_home_power": return "Nhà"
        case "sensor.lux_grid_power": return "Lưới"
        case "sensor.lux_battery_power": return "Pin"
        case "sensor.lux_battery_soc": return "SOC"
        default: return "Chênh cell"
        }
    }
}

struct HistoryPanel: View {
    private struct Expansion: Identifiable {
        let id = UUID()
        let selection: Date?
    }

    let title: String
    var points: [HistoryPoint] = []
    let unit: String
    var preparedModel: SolarChartModel? = nil
    @State private var expansion: Expansion?

    var body: some View {
        let model = preparedModel ?? SolarChartModel(points: SolarBatteryPower.history(points))
        Panel {
            HStack {
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 4)
                Button {
                    expansion = Expansion(selection: nil)
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                }.accessibilityLabel("Phóng to " + title).disabled(model.points.isEmpty)
            }
            if model.points.isEmpty {
                ContentUnavailableView("Chưa có lịch sử", systemImage: "chart.xyaxis.line",
                                       description: Text("Tải lại khi kết nối ổn định.")).frame(height: 180)
            } else {
                SolarHistoryChart(title: title, model: model, unit: unit) { date in
                    expansion = Expansion(selection: date)
                }
            }
        }.fullScreenCover(item: $expansion) { presentation in
            ExpandedHistoryChart(title: title, model: model, unit: unit, initialSelection: presentation.selection)
        }
    }
}

private struct ExpandedHistoryChart: View {
    let title: String
    let model: SolarChartModel
    let unit: String
    let initialSelection: Date?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    SolarHistoryChart(title: title, model: model, unit: unit, expanded: true,
                                      height: max(150, min(340, geometry.size.height * 0.38)),
                                      initialSelection: initialSelection)
                        .padding(16)
                }.background(SolarTheme.ink)
            }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Đóng") { dismiss() }.accessibilityLabel("Đóng biểu đồ")
                    }
                }
                .toolbarBackground(SolarTheme.panel, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }.tint(SolarTheme.sun).preferredColorScheme(.dark)
    }
}

private struct SolarHistoryChart: View {
    let title: String
    let model: SolarChartModel
    let unit: String
    let expanded: Bool
    let height: CGFloat
    let onExpand: ((Date?) -> Void)?
    @State private var selection: Date?
    @State private var window: ClosedRange<Date>?
    @State private var pinchWindow: ClosedRange<Date>?
    @State private var pinchFocus: Date?

    init(title: String, model: SolarChartModel, unit: String, expanded: Bool = false,
         height: CGFloat = 190, initialSelection: Date? = nil, onExpand: ((Date?) -> Void)? = nil) {
        self.title = title
        self.model = model
        self.unit = unit
        self.expanded = expanded
        self.height = height
        self.onExpand = onExpand
        _selection = State(initialValue: initialSelection)
    }

    private var visibleWindow: ClosedRange<Date> { window ?? model.domain }
    private var zoomFactor: Double { model.duration / visibleWindow.upperBound.timeIntervalSince(visibleWindow.lowerBound) }
    private var focus: Date {
        if let selection, visibleWindow.contains(selection) { return selection }
        return visibleWindow.lowerBound.addingTimeInterval(visibleWindow.upperBound.timeIntervalSince(visibleWindow.lowerBound) / 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if expanded { zoomControls }
            if expanded || window != nil {
                Text(solarDay(visibleWindow.lowerBound) + " " + solarTime(visibleWindow.lowerBound)
                     + " → " + solarDay(visibleWindow.upperBound) + " " + solarTime(visibleWindow.upperBound))
                    .font(.system(size: 10)).foregroundStyle(SolarTheme.muted).monospacedDigit()
                    .accessibilityIdentifier("chart-visible-range")
            }
            plot.frame(height: height)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { legend }
                VStack(alignment: .leading, spacing: 8) { legend }
            }
            Text(expanded ? "Chạm để xem · Giữ và kéo để rà giờ · Chụm hai ngón hoặc chạm hai lần để zoom"
                 : "Chạm để xem giờ và giá trị · Chạm hai lần để mở lớn")
                .font(.system(size: 10)).foregroundStyle(SolarTheme.muted)
            if let selection { inspector(at: selection) }
            if !expanded && window != nil {
                Button("Toàn khoảng") { reset() }.font(.caption).accessibilityLabel("Đặt lại biểu đồ")
            }
        }.onChange(of: model.domain) { _, _ in
            window = nil
            pinchWindow = nil
            pinchFocus = nil
            if let selection, !model.domain.contains(selection) { self.selection = nil }
        }
    }

    private var plot: some View {
        Chart {
            ForEach(model.drawingPoints(in: visibleWindow)) { point in
                LineMark(x: .value("Thời gian", point.date), y: .value(unit, point.value),
                         series: .value("Đoạn", point.entity + "-" + String(point.segment)))
                    .foregroundStyle(SolarChartStyle.color(point.entity)).interpolationMethod(.stepEnd)
                if model.series.first(where: { $0.entity == point.entity })?.points.count == 1 {
                    PointMark(x: .value("Thời gian", point.date), y: .value(unit, point.value))
                        .foregroundStyle(SolarChartStyle.color(point.entity))
                }
            }
            if let selection, visibleWindow.contains(selection) {
                RuleMark(x: .value("Thời điểm chọn", selection))
                    .foregroundStyle(.white.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(model.series) { series in
                    if let point = model.sample(at: selection, entity: series.entity) {
                        PointMark(x: .value("Thời gian", selection), y: .value(unit, point.value))
                            .foregroundStyle(SolarChartStyle.color(series.entity)).symbolSize(40)
                    }
                }
            }
        }.chartXScale(domain: visibleWindow)
            .chartYScale(domain: model.yDomain(unit: unit))
            .chartPlotStyle { plot in plot.clipped() }
            .chartXAxis { timeAxis }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let anchor = proxy.plotFrame {
                        let frame = geometry[anchor]
                        SolarChartTouchSurface(onSelect: { x in
                            select(x: x, proxy: proxy)
                        }, onDoubleTap: { x in
                            let date = proxy.value(atX: x, as: Date.self).map { model.inspectionDate(at: $0) }
                            if expanded { zoom(2, around: date ?? focus) }
                            else { onExpand?(date) }
                        }, onPinch: { scale, state in
                            switch state {
                            case .began, .changed:
                                if pinchWindow == nil { pinchWindow = visibleWindow; pinchFocus = focus }
                                window = model.zoomed(pinchWindow ?? visibleWindow, factor: Double(scale),
                                                      around: pinchFocus ?? focus)
                            case .ended, .cancelled, .failed:
                                pinchWindow = nil
                                pinchFocus = nil
                            default: break
                            }
                        })
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Biểu đồ " + title)
                            .accessibilityHint("Chạm hai lần để phóng to. Chạm hoặc giữ và kéo để xem dữ liệu.")
                            .accessibilityIdentifier((expanded ? "chart-expanded-plot-" : "chart-plot-") + unit)
                            .accessibilityAction(named: Text("Phóng to")) {
                                if expanded { zoom(2, around: focus) } else { onExpand?(selection) }
                            }
                            .accessibilityAction(named: Text("Xem mẫu cuối")) { selection = model.points.last?.date }
                    }
                }
            }
    }

    private var timeAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { value in
            AxisGridLine()
            AxisValueLabel {
                if let date = value.as(Date.self) { Text(SolarChartModel.axisTime(date)) }
            }
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            control("minus.magnifyingglass", label: "Thu nhỏ trục thời gian") { zoom(0.5, around: focus) }
            control("plus.magnifyingglass", label: "Phóng to trục thời gian") { zoom(2, around: focus) }
            Text("\(quantity(zoomFactor, 1))×").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .frame(maxWidth: .infinity).accessibilityIdentifier("chart-zoom-level")
                .accessibilityValue(String(format: "%.3f", zoomFactor))
            control("chevron.left", label: "Mốc trước") { move(-0.5) }
            control("chevron.right", label: "Mốc sau") { move(0.5) }
            control("arrow.counterclockwise", label: "Đặt lại biểu đồ") { reset() }
        }
    }

    private func control(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 40, height: 44) }
            .buttonStyle(.plain).foregroundStyle(SolarTheme.sun).accessibilityLabel(label)
    }

    private var legend: some View {
        ForEach(model.series) { series in
            HStack(spacing: 5) {
                Circle().fill(SolarChartStyle.color(series.entity)).frame(width: 6, height: 6)
                Text(SolarChartStyle.name(series.entity)).font(.caption2)
            }
        }
    }

    private func inspector(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Thời điểm " + solarDay(date) + " · " + solarTime(date))
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .accessibilityIdentifier(expanded ? "chart-selected-time" : "chart-compact-selected-time")
            ForEach(model.series) { series in
                let point = model.sample(at: date, entity: series.entity)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(SolarChartStyle.name(series.entity))
                        Spacer()
                        Text(point.map { $0.value.formatted(.number.locale(Locale(identifier: "vi_VN"))
                            .precision(.fractionLength(0...2))) + " " + unit } ?? "Không có mẫu")
                            .monospacedDigit().accessibilityIdentifier((expanded ? "chart-value-" : "chart-compact-value-") + series.entity)
                    }.font(.system(size: 14, weight: .semibold)).foregroundStyle(SolarChartStyle.color(series.entity))
                    if let point {
                        Text("Mẫu ghi lúc " + solarDay(point.date) + " " + solarTime(point.date))
                            .font(.system(size: 9)).foregroundStyle(SolarTheme.muted)
                    }
                }
            }
            Text("Giữ giá trị theo mẫu ghi, không nội suy qua đoạn mất dữ liệu.")
                .font(.system(size: 9)).foregroundStyle(SolarTheme.muted)
        }.padding(12).background(SolarTheme.ink, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(SolarTheme.border, lineWidth: 0.7))
    }

    private func select(x: CGFloat, proxy: ChartProxy) {
        if let date = proxy.value(atX: x, as: Date.self) { selection = model.inspectionDate(at: date) }
    }

    private func zoom(_ factor: Double, around date: Date) {
        window = model.zoomed(visibleWindow, factor: factor, around: date)
        if let selection, !visibleWindow.contains(selection) { self.selection = nil }
    }

    private func move(_ fraction: Double) {
        window = model.shifted(visibleWindow, by: fraction)
        if let selection, !visibleWindow.contains(selection) { self.selection = nil }
    }

    private func reset() {
        window = nil
        pinchWindow = nil
        pinchFocus = nil
        selection = nil
    }
}
