import SwiftUI

struct SolarEnergyHistoryView: View {
    @Environment(SolarStore.self) private var store
    @State private var rangeMode = false
    @State private var from = Date()
    @State private var through = Date()
    @State private var applied: SolarEnergyRange?
    @State private var validation: String?
    @State private var chartMetric = SolarEnergyMetric.consumption
    @State private var showRows = false
    @State private var loadTicket = UUID()
    @State private var dateRequest: SolarHistoryDateRequest?

    private var history: SolarEnergyStore { store.energyHistory }
    private var calendar: Calendar { SolarEnergyRange.calendar(history.timeZoneID) }
    private var draft: SolarEnergyRange? {
        try? SolarEnergyRange(from: from, through: rangeMode ? through : from, timeZoneID: history.timeZoneID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls
            if let validation { Text(validation).font(.callout).foregroundStyle(SolarTheme.discharge) }
            if history.loading {
                ProgressView("Đang tải thống kê năng lượng…").tint(SolarTheme.sun).frame(maxWidth: .infinity, minHeight: 90)
                    .accessibilityIdentifier("energy-loading")
            } else if let error = history.error {
                Panel {
                    Label("Chưa tải được lịch sử", systemImage: "wifi.exclamationmark").font(.headline)
                    Text(error).font(.callout).foregroundStyle(SolarTheme.muted)
                    Button("Thử lại") { apply(force: true) }.buttonStyle(.bordered)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("energy-error")
            } else if let report = history.report {
                results(report)
            }
        }.task { if applied == nil || (history.report == nil && !history.loading) { await load() } }
            .onDisappear { history.cancel() }
            .onChange(of: store.transportLive) { _, live in
                if live, history.report == nil, !history.loading { apply() }
            }
            .environment(\.timeZone, calendar.timeZone)
            .environment(\.locale, Locale(identifier: "vi_VN"))
            .sheet(item: $dateRequest) { request in
                SolarHistoryDatePicker(request: request) { day in
                    if request.field == .from { from = day } else { through = day }
                }
            }
    }

    private var controls: some View {
        Panel {
            HStack {
                Label("Điện năng theo ngày", systemImage: "calendar").font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 3)
                Text("kWh").font(.caption).foregroundStyle(SolarTheme.muted)
            }
            Picker("Khoảng thời gian", selection: $rangeMode) {
                Text("Một ngày").tag(false)
                Text("Khoảng ngày").tag(true)
            }.pickerStyle(.segmented).accessibilityIdentifier("energy-range-mode")
            dateButton(rangeMode ? "Từ ngày" : "Ngày xem", date: from, field: .from, id: "energy-from-date")
            if rangeMode {
                dateButton("Đến ngày", date: through, field: .through, id: "energy-through-date")
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                quickButton("Hôm nay", offset: 0)
                quickButton("Hôm qua", offset: -1)
                Button("7 ngày qua") {
                    rangeMode = true
                    through = calendar.startOfDay(for: Date())
                    from = calendar.date(byAdding: .day, value: -6, to: through) ?? through
                    apply()
                }.accessibilityIdentifier("energy-last-seven")
                Button("Tháng này") {
                    rangeMode = true
                    through = calendar.startOfDay(for: Date())
                    from = calendar.dateInterval(of: .month, for: through)?.start ?? through
                    apply()
                }.accessibilityIdentifier("energy-this-month")
            }.buttonStyle(.bordered).font(.system(size: 13)).tint(SolarTheme.sun)
            Button { apply(force: true) } label: {
                Label("Xem lịch sử", systemImage: "arrow.clockwise").frame(maxWidth: .infinity, minHeight: 28)
            }.buttonStyle(.borderedProminent).tint(SolarTheme.sun).foregroundStyle(SolarTheme.ink)
                .accessibilityIdentifier("energy-apply")
            Text("Tính cả ngày kết thúc · Giờ hệ thống: " + history.timeZoneID + " · Tối đa 366 ngày/lần")
                .font(.system(size: 11)).foregroundStyle(SolarTheme.muted)
            if applied != nil, draft != applied {
                Text("Ngày đã đổi. Bấm Xem lịch sử để áp dụng.").font(.caption).foregroundStyle(SolarTheme.sun)
                    .accessibilityIdentifier("energy-unapplied")
            }
        }
    }

    private func dateButton(_ title: String, date: Date, field: SolarHistoryDateRequest.Field, id: String) -> some View {
        Button {
            dateRequest = SolarHistoryDateRequest(field: field, selection: date,
                timeZoneID: history.timeZoneID, now: Date())
        } label: {
            HStack {
                Text(title).foregroundStyle(.white)
                Spacer(minLength: 8)
                Text(SolarCalendarDraft(selection: date, timeZoneID: history.timeZoneID).label(date))
                    .monospacedDigit().padding(.horizontal, 10).padding(.vertical, 8)
                    .background(SolarTheme.sun.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            }.font(.system(size: 15)).frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }

    private func quickButton(_ title: String, offset: Int) -> some View {
        Button(title) {
            rangeMode = false
            from = calendar.date(byAdding: .day, value: offset, to: Date()) ?? Date()
            through = from
            apply()
        }.accessibilityIdentifier(offset == 0 ? "energy-today" : "energy-yesterday")
    }

    private func results(_ report: SolarEnergyReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(report.range.title).font(.system(size: 18, weight: .semibold)).monospacedDigit()
                    .accessibilityIdentifier("energy-loaded-range")
                Spacer(minLength: 4)
                Text("\(report.range.dayCount) ngày").font(.caption).foregroundStyle(SolarTheme.muted)
            }
            if !report.hasData {
                ContentUnavailableView("Chưa có thống kê cho khoảng này", systemImage: "calendar.badge.exclamationmark",
                    description: Text("Home Assistant chỉ có lịch sử từ khi bắt đầu ghi dữ liệu. Chọn ngày khác hoặc tải lại sau."))
                    .accessibilityIdentifier("energy-empty")
            } else {
                summary(report)
                if report.incomplete || report.missingCount(.consumption) > 0 {
                    Label("Có khoảng thiếu dữ liệu. Tổng bên dưới chỉ cộng các mẫu hợp lệ, chưa phải toàn bộ khoảng đã chọn.",
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(SolarTheme.sun)
                        .accessibilityIdentifier("energy-incomplete")
                }
                if !report.unavailableMeters.isEmpty {
                    Text("Chưa có thống kê kWh: " + report.unavailableMeters.map(\.title).joined(separator: ", "))
                        .font(.caption).foregroundStyle(SolarTheme.muted)
                }
                SolarEnergyChartPanel(report: report, metric: $chartMetric)
                DisclosureGroup(isExpanded: $showRows) {
                    ForEach(report.buckets) { bucket in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(report.range.hourly ? report.range.label(bucket.start, time: true) + " – " + report.range.label(bucket.end, time: true)
                                     : report.range.label(bucket.start)).font(.system(size: 14, weight: .semibold))
                                Spacer()
                                if !report.range.hourly {
                                    Button("Xem ngày") {
                                        rangeMode = false; from = bucket.start; through = bucket.start; apply()
                                    }.font(.caption).accessibilityIdentifier("energy-day-" + report.range.label(bucket.start))
                                }
                            }
                            ForEach(SolarEnergyMetric.allCases) { metric in
                                metricRow(metric.title, bucket.value(metric), "kWh", digits: 2,
                                          suffix: metric == .consumption ? " (ước tính)" : "")
                            }
                            Rectangle().fill(SolarTheme.border).frame(height: 0.7)
                        }.padding(.vertical, 8)
                    }
                } label: {
                    Text(report.range.hourly ? "Bảng từng giờ" : "Bảng từng ngày").font(.system(size: 15, weight: .semibold))
                }.tint(SolarTheme.sun).accessibilityIdentifier("energy-detail-table")
            }
            Text("Nguồn: thống kê dài hạn Home Assistant, giống tab Năng lượng trên web. Có độ trễ tổng hợp; số này có thể khác bộ đếm Hôm nay đang cập nhật trực tiếp.")
                .font(.system(size: 11)).foregroundStyle(SolarTheme.muted)
            if let end = report.latestEnd {
                let boundary = min(end, report.loadedAt)
                Text("Khoảng thống kê đến: " + report.range.label(boundary) + " " + report.range.label(boundary, time: true))
                    .font(.system(size: 11)).foregroundStyle(SolarTheme.muted)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("energy-results")
    }

    private func summary(_ report: SolarEnergyReport) -> some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach([SolarEnergyMetric.pv, .charge, .discharge, .gridImport]) { metric in
                    VStack(alignment: .leading, spacing: 8) {
                        Label { Text(metric.title) } icon: { SolarMetricIcon(kind: metric.icon) }
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(metric.color)
                        Text(quantity(report.total(metric), 2) + " kWh").font(.system(size: 21, weight: .semibold))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                            .accessibilityIdentifier("energy-total-" + metric.id)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(SolarTheme.panel, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(metric.color.opacity(0.5), lineWidth: 0.7))
                }
            }
            Panel {
                Label("Tiêu thụ ước tính", systemImage: "house.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(SolarTheme.leaf)
                Text((report.total(.consumption) == nil ? "" : "≈ ") + quantity(report.total(.consumption), 2) + " kWh").font(.system(size: 28, weight: .semibold))
                    .monospacedDigit().accessibilityIdentifier("energy-total-consumption")
                metricRow("Phát lên lưới", report.total(.gridExport), "kWh", digits: 2)
                Text("PV + mua lưới + xả pin − sạc pin − phát lưới. Bao gồm hao hụt và điện tự dùng biến tần; không phải công tơ riêng của nhà, không dùng tính hóa đơn.")
                    .font(.system(size: 11)).foregroundStyle(SolarTheme.muted)
            }
        }
    }

    private func apply(force: Bool = false) { Task { await load(force: force) } }
    private func load(force: Bool = false) async {
        do {
            let selected = try SolarEnergyRange(from: from, through: rangeMode ? through : from, timeZoneID: history.timeZoneID)
            let id = UUID()
            loadTicket = id
            validation = nil; applied = selected; showRows = false
            await store.loadEnergyHistory(selected, force: force)
            guard loadTicket == id else { return }
            if let report = history.report {
                applied = report.range
            }
        } catch { validation = error.localizedDescription }
    }
}

extension SolarEnergyMetric {
    var color: Color {
        switch self {
        case .pv: return SolarTheme.sun
        case .charge: return SolarTheme.charge
        case .discharge: return SolarTheme.discharge
        case .gridImport, .gridExport: return SolarTheme.grid
        case .consumption: return SolarTheme.leaf
        }
    }
    var icon: SolarMetricKind {
        switch self {
        case .pv: return .solar
        case .charge: return .charge
        case .discharge: return .discharge
        case .gridImport, .gridExport: return .grid
        case .consumption: return .home
        }
    }
}
