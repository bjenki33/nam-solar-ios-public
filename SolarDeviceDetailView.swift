import SwiftUI

struct SolarDeviceDetailView: View {
    let device: SolarDevice
    @Environment(SolarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 2)) { context in
                let s = store.snapshot(now: context.date)
                let history = store.deviceHistory.state(for: device)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Panel {
                            Text(device.sensorName).font(.system(size: 14)).foregroundStyle(SolarTheme.muted)
                            Text("Công suất hiện tại").font(.system(size: 12)).foregroundStyle(SolarTheme.muted)
                            Reading(value: s.number(device.key), unit: "W", large: true)
                                .foregroundStyle(color)
                                .accessibilityIdentifier("device-current-power")
                                .accessibilityLabel("Công suất hiện tại")
                                .accessibilityValue(quantity(s.number(device.key)) + " W")
                            HStack(spacing: 5) {
                                Circle().fill(s.online ? SolarTheme.leaf : SolarTheme.sun).frame(width: 6, height: 6)
                                Text(s.online ? "Trực tiếp" : "Chưa có dữ liệu mới")
                                if let read = s.date("local_last_read") {
                                    Spacer()
                                    Text(solarTime(read)).monospacedDigit()
                                }
                            }.font(.system(size: 11)).foregroundStyle(SolarTheme.muted)
                        }
                        Panel { extraReadings(s) }
                        if store.previewMode { Text("Dữ liệu kiểm thử").font(.caption).foregroundStyle(.orange) }
                        if history.loading {
                            ProgressView("Đang tải lịch sử thiết bị").frame(maxWidth: .infinity)
                                .accessibilityIdentifier("device-history-loading")
                        }
                        if let error = history.error {
                            Text(error).font(.caption).foregroundStyle(.orange)
                        }
                        if history.chart != nil || !history.loading {
                            HistoryPanel(title: device.chartTitle, unit: "W", preparedModel: history.chart)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("device-history-" + device.rawValue)
                        }
                        HStack {
                            if let loaded = history.loadedAt {
                                Text("Lịch sử cập nhật " + solarTime(loaded)).font(.system(size: 11)).foregroundStyle(SolarTheme.muted)
                            }
                            Spacer(minLength: 3)
                            Button("Tải lại lịch sử") { Task { await store.loadDeviceHistory(device, force: true) } }
                                .font(.system(size: 12)).buttonStyle(.bordered).disabled(history.loading)
                        }
                    }.padding(16)
                }
            }.background(SolarTheme.ink)
                .navigationTitle(device.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Đóng") { dismiss() }.accessibilityIdentifier("close-device-detail")
                    }
                }
                .toolbarBackground(SolarTheme.panel, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }.tint(SolarTheme.sun).preferredColorScheme(.dark)
            .task(id: device) { await store.loadDeviceHistory(device) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.loadDeviceHistory(device) } }
            }
    }

    private var color: Color {
        switch device {
        case .solar, .inverter: return SolarTheme.sun
        case .home: return SolarTheme.leaf
        case .grid: return SolarTheme.grid
        }
    }

    @ViewBuilder private func extraReadings(_ s: SolarSnapshot) -> some View {
        switch device {
        case .solar:
            Text("Dàn pin · 9,92 kWp").font(.system(size: 16, weight: .semibold))
            ForEach(1...2, id: \.self) { i in
                metricRow("PV\(i) · 8 tấm", s.number("pv\(i)_power"), "W")
                metricRow("Điện áp PV\(i)", s.number("pv\(i)_voltage"), "V", digits: 1)
            }
            Text("Dòng DC trên sơ đồ là ước tính từ công suất / điện áp.").font(.caption).foregroundStyle(SolarTheme.muted)
        case .inverter:
            Text("Luxpower SNA PRO 6.5K").font(.system(size: 16, weight: .semibold))
            metricRow("Tản nhiệt AC", s.number("radiator1_temperature", slow: true), "°C", digits: 1)
            metricRow("Tản nhiệt DC", s.number("radiator2_temperature", slow: true), "°C", digits: 1)
        case .home:
            Text("Nguồn cấp tải").font(.system(size: 16, weight: .semibold))
            metricRow("Tải phía lưới", s.number("grid_side_load"), "W")
            metricRow("Cổng EPS", s.number("eps_power"), "W")
        case .grid:
            Text(s.gridStatus).foregroundStyle(SolarTheme.grid)
            metricRow("Điện áp", s.number("grid_voltage"), "V", digits: 1)
            metricRow("Tần số", s.number("grid_frequency"), "Hz", digits: 2)
            Text("Công suất dương: mua từ lưới. Âm: phát lên lưới.").font(.caption).foregroundStyle(SolarTheme.muted)
        }
    }
}
