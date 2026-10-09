import SwiftUI
import Charts

struct SolarEnergyChartPanel: View {
    let report: SolarEnergyReport
    @Binding var metric: SolarEnergyMetric
    @State private var expanded = false
    var body: some View {
        Panel {
            HStack {
                Text(report.range.hourly ? "Điện năng từng giờ" : "Điện năng từng ngày").font(.system(size: 16, weight: .semibold))
                Spacer(minLength: 0)
                Button { expanded = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Phóng to điện năng")
            }
            Picker("Thông số biểu đồ", selection: $metric) {
                ForEach(SolarEnergyMetric.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu).tint(metric.color).accessibilityIdentifier("energy-chart-metric")
            if report.total(metric) == nil {
                Text("Thông số này chưa có thống kê hợp lệ trong khoảng đã chọn.")
                    .font(.caption).foregroundStyle(SolarTheme.muted)
            }
            SolarEnergyBarChart(report: report, metric: metric, onExpand: { expanded = true })
        }.fullScreenCover(isPresented: $expanded) {
            NavigationStack {
                GeometryReader { geometry in
                    ScrollView {
                        SolarEnergyBarChart(report: report, metric: metric, expanded: true,
                            expandedHeight: max(150, min(280, geometry.size.height * 0.38))).padding(16)
                    }
                }.background(SolarTheme.ink)
                    .navigationTitle(metric.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { expanded = false }.accessibilityIdentifier("energy-close-chart") } }
            }.tint(SolarTheme.sun).preferredColorScheme(.dark)
        }
    }
}

private struct SolarEnergyBarChart: View {
    let report: SolarEnergyReport
    let metric: SolarEnergyMetric
    var expanded = false
    var expandedHeight: CGFloat = 280
    var onExpand: (() -> Void)?
    @State private var selected: Date?
    @State private var window: ClosedRange<Date>?
    @State private var pinchWindow: ClosedRange<Date>?
    @State private var panWindow: ClosedRange<Date>?
    private var domain: ClosedRange<Date> { window ?? report.range.start...report.range.end }
    private var selectedBucket: SolarEnergyBucket? {
        guard let selected else { return nil }
        return report.buckets.first { selected >= $0.start && selected < $0.end }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if expanded {
                HStack {
                    Button("−") { zoom(0.5) }.accessibilityLabel("Thu nhỏ điện năng")
                    Button("+") { zoom(2) }.accessibilityLabel("Phóng lớn điện năng")
                    Spacer()
                    Button("Toàn khoảng") { window = nil }.accessibilityIdentifier("energy-reset-chart")
                }.buttonStyle(.bordered)
            }
            inspector
            Chart {
                ForEach(report.buckets) { bucket in
                    if bucket.start < domain.upperBound, bucket.end > domain.lowerBound, let value = bucket.value(metric) {
                        // Both intervals are explicit: energy columns rise from zero, not floating horizontal bars.
                        let inset = bucket.end.timeIntervalSince(bucket.start) * 0.03
                        let low = max(bucket.start.addingTimeInterval(inset), domain.lowerBound)
                        let high = min(bucket.end.addingTimeInterval(-inset), domain.upperBound)
                        if high > low {
                            RectangleMark(xStart: .value("Bắt đầu", low), xEnd: .value("Kết thúc", high),
                                          yStart: .value("kWh", 0.0), yEnd: .value("kWh", value))
                                .cornerRadius(2)
                                .foregroundStyle(metric.color.opacity(selectedBucket?.id == bucket.id ? 1 : 0.65))
                        }
                    }
                }
                if let selectedBucket, selectedBucket.start < domain.upperBound, selectedBucket.end > domain.lowerBound {
                    RuleMark(x: .value("Khoảng chọn", selectedBucket.start.addingTimeInterval(selectedBucket.end.timeIntervalSince(selectedBucket.start) / 2)))
                        .foregroundStyle(.white.opacity(0.8)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }.chartXScale(domain: domain).chartYScale(domain: 0...max(1, (report.buckets.compactMap { $0.value(metric) }.max() ?? 0) * 1.15))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { axis in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = axis.as(Date.self) {
                                Text(report.range.hourly ? report.range.label(date, time: true) : String(report.range.label(date).prefix(5)))
                            }
                        }
                    }
                }.chartPlotStyle { $0.clipped() }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let anchor = proxy.plotFrame {
                            let frame = geometry[anchor]
                            SolarChartTouchSurface(onSelect: { x in
                                selected = proxy.value(atX: x, as: Date.self).map { min(report.range.end.addingTimeInterval(-0.001), max(report.range.start, $0)) }
                            }, onDoubleTap: { _ in
                                if expanded { zoom(2) } else { onExpand?() }
                            }, onPinch: { scale, state in
                                if state == .began || state == .changed {
                                    if pinchWindow == nil { pinchWindow = domain }
                                    zoom(Double(scale), base: pinchWindow)
                                } else { pinchWindow = nil }
                            }, onPan: { fraction, state in
                                if state == .began || state == .changed || state == .ended {
                                    if panWindow == nil { panWindow = domain }
                                    let base = panWindow ?? domain
                                    let span = base.upperBound.timeIntervalSince(base.lowerBound)
                                    let low = min(report.range.end.addingTimeInterval(-span),
                                        max(report.range.start, base.lowerBound.addingTimeInterval(-Double(fraction) * span)))
                                    window = low...low.addingTimeInterval(span)
                                    if let selected, !domain.contains(selected) { self.selected = nil }
                                }
                                if state == .ended || state == .cancelled || state == .failed { panWindow = nil }
                            }, panEnabled: domain.upperBound.timeIntervalSince(domain.lowerBound)
                                < report.range.end.timeIntervalSince(report.range.start) - 0.01)
                                .frame(width: frame.width, height: frame.height).position(x: frame.midX, y: frame.midY)
                                .accessibilityElement(children: .ignore).accessibilityLabel("Biểu đồ điện năng")
                                .accessibilityIdentifier(expanded ? "energy-expanded-plot" : "energy-chart-plot")
                        }
                    }
                }.frame(height: expanded ? expandedHeight : 200)
            Text("kWh / " + (report.range.hourly ? "giờ" : "ngày")
                 + (expanded ? " · Vuốt ngang khi zoom · Giữ và kéo để rà số · Chạm hai lần để zoom"
                    : " · Chạm hoặc giữ và kéo để xem · Chạm hai lần để mở lớn"))
                .font(.system(size: 11)).foregroundStyle(SolarTheme.muted)
        }.onChange(of: report.range) { _, _ in selected = nil; window = nil; pinchWindow = nil; panWindow = nil }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedBucket.map { bucket in
                report.range.hourly ? report.range.label(bucket.start) + " · " + report.range.label(bucket.start, time: true) + " – " + report.range.label(bucket.end, time: true)
                    : report.range.label(bucket.start)
            } ?? "Chạm hoặc giữ trên biểu đồ để xem")
                .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                .accessibilityIdentifier(selectedBucket == nil ? "energy-inspector-prompt" : "energy-selected-time")
            ForEach(SolarEnergyMetric.allCases) { item in
                HStack {
                    Text(item.title).foregroundStyle(item.color)
                    Spacer(minLength: 4)
                    Text((item == .consumption ? "≈ " : "") + quantity(selectedBucket?.value(item), 2) + " kWh").monospacedDigit()
                        .accessibilityIdentifier("energy-selected-" + item.id)
                }.font(.system(size: 12)).lineLimit(1)
            }
        }.padding(12).background(SolarTheme.ink, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(SolarTheme.border, lineWidth: 0.7))
            .accessibilityIdentifier("energy-inspector")
    }

    private func zoom(_ factor: Double, base: ClosedRange<Date>? = nil) {
        guard factor.isFinite, factor > 0 else { return }
        let bounds = base ?? domain
        let total = report.range.end.timeIntervalSince(report.range.start)
        let minimum: TimeInterval = report.range.hourly ? 3600 * 3 : 86400 * 3
        let duration = min(total, max(min(total, minimum), bounds.upperBound.timeIntervalSince(bounds.lowerBound) / factor))
        let center = selected ?? bounds.lowerBound.addingTimeInterval(bounds.upperBound.timeIntervalSince(bounds.lowerBound) / 2)
        let low = min(report.range.end.addingTimeInterval(-duration), max(report.range.start, center.addingTimeInterval(-duration / 2)))
        window = low...low.addingTimeInterval(duration)
    }
}
