import SwiftUI

struct DataStatus: View {
    let snapshot: SolarSnapshot
    let message: String
    private var gridMessage: String {
        guard snapshot.online else { return "Chờ dữ liệu mới" }
        guard let voltage = snapshot.number("grid_voltage") else { return "Trực tiếp" }
        return voltage > 50 ? "Có điện lưới" : "Không có lưới"
    }
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock").font(.system(size: 12))
            if let date = snapshot.date("local_last_read") {
                Text(solarTime(date)).monospacedDigit()
                Text(solarDay(date)).foregroundStyle(.white.opacity(0.8))
            } else { Text(message) }
            Spacer(minLength: 3)
            Circle().fill(snapshot.online ? SolarTheme.leaf : SolarTheme.sun).frame(width: 5, height: 5)
            Text(gridMessage)
                .foregroundStyle(snapshot.online ? SolarTheme.muted : SolarTheme.sun)
        }.font(.system(size: 10)).foregroundStyle(SolarTheme.muted).lineLimit(1).minimumScaleFactor(0.8)
            .accessibilityElement(children: .combine)
    }
}

struct SolarPage<Content: View>: View {
    @Environment(SolarStore.self) private var store
    let title: String
    @ViewBuilder let content: (SolarSnapshot) -> Content
    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            let snapshot = store.snapshot(now: context.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title).font(.system(size: 20, weight: .semibold))
                    if store.previewMode { Text("Dữ liệu kiểm thử").font(.caption).foregroundStyle(.orange) }
                    content(snapshot)
                    Text("NAM SOLAR · CHỈ ĐỌC DỮ LIỆU").font(.system(size: 9)).tracking(1)
                        .foregroundStyle(SolarTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 16)
            }.refreshable { store.start(force: true) }
        }
    }
}

struct OverviewView: View {
    @Environment(SolarStore.self) private var store
    @Binding var selection: SolarTab
    @State private var sourceNote = false
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 2)) { context in
                let s = store.snapshot(now: context.date)
                ScrollView {
                    SolarOverviewLayout(viewportHeight: geometry.size.height) {
                        VStack(spacing: 7) {
                            if store.previewMode && !cleanLayoutPreview {
                                Text("Dữ liệu kiểm thử").font(.system(size: 10)).foregroundStyle(.orange)
                            }
                            DailySummary(snapshot: s, sourceNote: $sourceNote)
                        }
                        DataStatus(snapshot: s, message: store.connectionMessage).padding(.vertical, 2)
                        SolarFlowView(snapshot: s, selection: $selection)
                    }.padding(.horizontal, 8)
                }.refreshable { store.start(force: true) }
                    .alert("Nguồn tiêu thụ ước tính", isPresented: $sourceNote) { Button("Đóng", role: .cancel) {} } message: {
                        Text("Giả định pin chỉ sạc từ PV và điện phát lưới chỉ từ PV. Từ PV = sản lượng PV − sạc pin − phát lưới. Có gồm hao hụt biến tần. Nếu có sạc từ lưới hoặc xả pin lên lưới, phân bổ này có thể không chính xác.")
                    }
            }
        }
    }

    private var cleanLayoutPreview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ui-layout-clean")
        #else
        return false
        #endif
    }
}

struct DailySummary: View {
    private let readingSize: CGFloat = 18
    let snapshot: SolarSnapshot
    @Binding var sourceNote: Bool
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                tile("Sản lượng PV", .solar, "pv", SolarTheme.sun)
                tile("Sạc pin", .charge, "charge", SolarTheme.charge)
            }
            HStack(spacing: 6) {
                tile("Xả pin", .discharge, "discharge", SolarTheme.discharge)
                tile("Mua từ lưới", .grid, "grid_import", SolarTheme.grid)
            }
            VStack(spacing: 6) {
                consumptionColumns {
                    consumptionTitle.padding(.horizontal, 3)
                        .frame(minWidth: 0, maxWidth: .infinity)
                    total("Hôm nay", snapshot.consumption("today"), key: "today")
                    total("Tổng", snapshot.consumption("total", slow: true), key: "total")
                }
                Rectangle().fill(SolarTheme.border).frame(height: 0.7)
                let values = snapshot.estimatedSources
                consumptionColumns {
                    source("Từ PV", .solar, values?[0], SolarTheme.sun, key: "pv")
                    source("Từ pin", .discharge, values?[1], SolarTheme.discharge, key: "battery")
                    source("Từ lưới", .grid, values?[2], SolarTheme.grid, key: "grid")
                }
            }.padding(.horizontal, 8).padding(.vertical, 7)
                .accessibilityElement(children: .contain).accessibilityIdentifier("consumption-panel")
                .background(SolarTheme.panel, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(SolarTheme.border, lineWidth: 0.7))
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(SolarTheme.leaf).frame(width: 3).padding(.vertical, 1) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("daily-summary")
    }
    private func tile(_ title: String, _ icon: SolarMetricKind, _ key: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label { Text(title).accessibilityIdentifier("daily-" + key + "-title") } icon: { SolarMetricIcon(kind: icon) }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
            energyRow(snapshot.number(key + "_today"), label: "Hôm nay", digits: 2, size: readingSize, id: "daily-" + key + "-today-value")
            energyRow(snapshot.number(key + "_total", slow: true), label: "Tổng", digits: 2, size: 13, id: "daily-" + key + "-total-value")
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 7)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("daily-" + key)
            .background(SolarTheme.panel, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(SolarTheme.border, lineWidth: 0.7))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 1) }
    }
    private func energyRow(_ value: Double?, label: String, digits: Int, size: CGFloat, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(quantity(value, digits)).font(.system(size: size, weight: .semibold)).monospacedDigit()
                .accessibilityIdentifier(id)
            Text("kWh").font(.system(size: 10)).foregroundStyle(SolarTheme.muted)
            Spacer(minLength: 0)
            Text(label).font(.system(size: 10)).foregroundStyle(SolarTheme.muted)
        }.lineLimit(1).minimumScaleFactor(0.75)
    }
    private func consumptionColumns<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0, content: content)
            .overlay {
                // Both rows share the same column boundaries, regardless of text length.
                GeometryReader { geometry in
                    Path { path in
                        for column in 1...2 {
                            let x = geometry.size.width * CGFloat(column) / 3
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                        }
                    }.stroke(SolarTheme.border, lineWidth: 0.7)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }.padding(.vertical, 2)
    }
    private var consumptionTitle: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) { consumptionLabel; consumptionInfo }.fixedSize()
            VStack(spacing: 1) { consumptionLabel; consumptionInfo }.fixedSize()
        }
    }
    private var consumptionLabel: some View {
        Label { Text("Tiêu thụ").accessibilityIdentifier("consumption-heading") } icon: { SolarMetricIcon(kind: .home) }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(SolarTheme.leaf)
    }
    private var consumptionInfo: some View {
        Button { sourceNote = true } label: {
            Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(SolarTheme.muted).frame(width: 28, height: 28)
        }.accessibilityLabel("Cách ước tính nguồn tiêu thụ")
    }
    private func total(_ title: String, _ value: Double?, key: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 13)).foregroundStyle(SolarTheme.muted)
                .accessibilityIdentifier("consumption-" + key + "-title")
            estimatedReading(value, id: "consumption-" + key)
        }.padding(.horizontal, 3).frame(minWidth: 0, maxWidth: .infinity)
    }
    private func source(_ name: String, _ icon: SolarMetricKind, _ value: Double?, _ color: Color, key: String) -> some View {
        VStack(spacing: 3) {
            Label { Text(name).accessibilityIdentifier("consumption-" + key + "-title") } icon: { SolarMetricIcon(kind: icon) }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
            estimatedReading(value, id: "consumption-" + key)
        }.padding(.horizontal, 3).frame(minWidth: 0, maxWidth: .infinity)
    }
    private func estimatedReading(_ value: Double?, id: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                estimateNumber(value, id: id)
                estimateUnit(id: id)
            }.fixedSize()
            VStack(spacing: 1) {
                estimateNumber(value, id: id)
                estimateUnit(id: id)
            }
        }
    }
    private func estimateNumber(_ value: Double?, id: String) -> some View {
        Text("≈ " + quantity(value, 2)).font(.system(size: readingSize, weight: .semibold)).monospacedDigit()
            .lineLimit(1).fixedSize().accessibilityIdentifier(id + "-value")
    }
    private func estimateUnit(id: String) -> some View {
        Text("kWh").font(.system(size: 10)).foregroundStyle(SolarTheme.muted)
            .fixedSize().accessibilityIdentifier(id + "-unit")
    }
}

struct BatteryView: View {
    @Environment(SolarStore.self) private var store
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        SolarPage(title: "Pin RPT · 16,08 kWh") { s in
            Text("RPES-W2-IP20 · REPT 314 Ah · BMS 200 A").font(.system(size: 12)).foregroundStyle(SolarTheme.muted)
            HStack(spacing: 5) {
                Circle().fill(s.bmsOnline ? SolarTheme.leaf : SolarTheme.sun).frame(width: 6, height: 6)
                Text(s.bmsOnline ? "BMS đang kết nối" : "BMS chưa có dữ liệu mới")
                Spacer()
                if let date = s.date("bms_last_read") { Text("Cập nhật " + solarTime(date)).foregroundStyle(SolarTheme.muted) }
            }.font(.system(size: 11))
            LazyVGrid(columns: columns, spacing: 8) {
                batteryTile("Dung lượng còn lại", "battery.100percent", s.number("battery_soc"), "%", SolarTheme.sun, progress: s.number("battery_soc"))
                batteryTile("Điện áp bộ pin", "waveform.path", s.number("battery_voltage"), "V", SolarTheme.grid, digits: 1)
                batteryTile("Công suất sạc", "battery.100percent", s.number("battery_charge"), "W", SolarTheme.leaf)
                batteryTile("Công suất xả", "battery.25percent", s.number("battery_discharge"), "W", SolarTheme.discharge)
            }
            section("Bộ pin", "battery.100percent") {
                metricRow("Số chu kỳ BMS", s.number("battery_cycles", slow: true), "")
                metricRow("Dung lượng BMS báo", s.number("bms_capacity", slow: true), "Ah")
                Text("Danh định: 51,2 V · 314 Ah").font(.system(size: 12)).foregroundStyle(SolarTheme.muted)
            }
            section("Điện áp cell", "waveform.path") {
                metricRow("Cell thấp nhất", s.number("cell_min_voltage", slow: true), "V", digits: 3)
                metricRow("Cell cao nhất", s.number("cell_max_voltage", slow: true), "V", digits: 3)
                metricRow("Chênh lệch cell", s.number("cell_delta", slow: true), "mV")
            }
            section("Nhiệt độ", "thermometer.medium") {
                metricRow("Pin thấp nhất", s.number("battery_temperature_min", slow: true), "°C", digits: 1)
                metricRow("Pin cao nhất", s.number("battery_temperature_max", slow: true), "°C", digits: 1)
                metricRow("Tản nhiệt biến tần AC", s.number("radiator1_temperature", slow: true), "°C", digits: 1)
                metricRow("Tản nhiệt biến tần DC", s.number("radiator2_temperature", slow: true), "°C", digits: 1)
            }
            HistoryPanel(title: "Dung lượng pin · 24 giờ", unit: "%", preparedModel: store.preparedHistory?.soc)
            HistoryPanel(title: "Chênh cell · 24 giờ", unit: "mV", preparedModel: store.preparedHistory?.cell)
            historyFooter(store)
        }.task { await store.loadHistory() }
    }
    private func batteryTile(_ title: String, _ icon: String, _ value: Double?, _ unit: String, _ color: Color, digits: Int = 0, progress: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.system(size: 12)).foregroundStyle(SolarTheme.muted)
            Reading(value: value, unit: unit, digits: digits, large: true)
            if let progress { ProgressView(value: min(1, max(0, progress / 100))).tint(SolarTheme.leaf) }
            else { Color.clear.frame(height: 4) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(SolarTheme.panel, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(SolarTheme.border, lineWidth: 0.7))
            .overlay(alignment: .top) { RoundedRectangle(cornerRadius: 2).fill(color).frame(height: 2).padding(.horizontal, 1) }
    }
    private func section<Content: View>(_ title: String, _ icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(SolarTheme.border).frame(height: 0.7)
            Label(title, systemImage: icon).font(.system(size: 15, weight: .semibold)).padding(.vertical, 4)
            content()
        }
    }
}

struct HistoryView: View {
    @Environment(SolarStore.self) private var store
    var body: some View {
        SolarPage(title: "Lịch sử năng lượng") { s in
            SolarEnergyHistoryView()
            Text("Công suất gần đây").font(.system(size: 17, weight: .semibold)).padding(.top, 8)
            DataStatus(snapshot: s, message: store.connectionMessage)
            HistoryPanel(title: "Công suất · 2 giờ", unit: "W", preparedModel: store.preparedHistory?.power)
            Panel {
                Text("Điện năng hôm nay").font(.system(size: 17, weight: .semibold))
                metricRow("Sản lượng PV", s.number("pv_today"), "kWh", digits: 2)
                metricRow("Sạc vào pin", s.number("charge_today"), "kWh", digits: 2)
                metricRow("Xả từ pin", s.number("discharge_today"), "kWh", digits: 2)
                metricRow("Mua từ lưới", s.number("grid_import_today"), "kWh", digits: 2)
                metricRow("Phát lên lưới", s.number("grid_export_today"), "kWh", digits: 2)
            }
            Text("Pin: + sạc / − xả. Lưới: + mua / − phát. Khoảng cảm biến không khả dụng không được nối liền.")
                .font(.system(size: 11)).foregroundStyle(SolarTheme.muted)
            historyFooter(store)
        }.task { await store.loadHistory() }
    }
}

struct DiagnosticsView: View {
    @Environment(SolarStore.self) private var store
    var body: some View {
        SolarPage(title: "Hệ thống") { s in
            Panel(padding: 16) {
                Text("Kết nối trực tiếp").font(.system(size: 21, weight: .medium)).padding(.bottom, 4)
                diagnosticRow("App → Home Assistant", store.transportLive ? "Đã kết nối" : "Chưa kết nối", "network")
                diagnosticRow("Lux local connection", s.online ? "online" : "Chưa mới", "network")
                diagnosticRow("Lux local last read", age(s.date("local_last_read"), now: s.now), "network")
                diagnosticRow("Lux bms connection", s.bmsOnline ? "online" : "Chưa mới", "network")
                diagnosticRow("Lux bms last read", age(s.date("bms_last_read"), now: s.now), "network")
                diagnosticRow("Thời gian đọc (ms)", quantity(s.attribute("read_duration_ms")), "network")
                diagnosticRow("Lần đọc thành công", quantity(s.attribute("successful_reads")), "network")
                diagnosticRow("Lần đọc lỗi", quantity(s.attribute("failed_reads")), "network")
                Button("Kết nối lại") { store.start(force: true) }.buttonStyle(.bordered).font(.system(size: 13))
            }
            Panel(padding: 16) {
                Text("Thông số gốc").font(.system(size: 21, weight: .medium)).padding(.bottom, 4)
                diagnosticRow("Lux grid voltage", quantity(s.number("grid_voltage"), 1) + " V", "waveform.path")
                diagnosticRow("Lux grid frequency", quantity(s.number("grid_frequency"), 2) + " Hz", "waveform.path")
                diagnosticRow("Lux grid side load", quantity(s.number("grid_side_load")) + " W", "bolt.fill")
                diagnosticRow("Lux eps power", quantity(s.number("eps_power")) + " W", "bolt.fill")
                diagnosticRow("Mã trạng thái", s.online ? s.raw("state_code") ?? "--" : "--", "number")
                ForEach(["fault_raw", "warning_raw", "bms_fault_raw", "bms_warning_raw"], id: \.self) { key in
                    diagnosticRow(key, s.bmsOnline ? s.raw(key) ?? "--" : "--", "exclamationmark.circle")
                }
            }
            Text("Nam Solar \(SolarAppVersion.current) · SwiftUI · WebSocket\nChỉ đọc dữ liệu. Không gửi lệnh đến biến tần.")
                .font(.system(size: 11)).foregroundStyle(SolarTheme.muted)
                .accessibilityIdentifier("app-version-footer")
        }
    }
    private func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "--" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds) giây trước" }
        if seconds < 3600 { return "\(seconds / 60) phút trước" }
        return solarTime(date)
    }
    private func diagnosticRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(SolarTheme.grid).frame(width: 24)
            Text(title).font(.system(size: 13))
            Spacer(minLength: 3)
            Text(value).font(.system(size: 13)).monospacedDigit().multilineTextAlignment(.trailing)
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}

@MainActor func historyFooter(_ store: SolarStore) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        if store.historyLoading { ProgressView("Đang tải lịch sử") }
        if let message = store.historyError { Text(message).font(.caption).foregroundStyle(.orange) }
        Button("Tải lại lịch sử") { Task { await store.loadHistory(force: true) } }.buttonStyle(.bordered).disabled(store.historyLoading)
    }
}
