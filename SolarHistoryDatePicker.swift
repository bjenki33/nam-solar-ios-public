import SwiftUI

struct SolarHistoryDateRequest: Identifiable {
    enum Field: Equatable { case from, through }
    let id = UUID()
    let field: Field
    let selection: Date
    let timeZoneID: String
    let now: Date
}

struct SolarHistoryDatePicker: View {
    @State private var draft: SolarCalendarDraft
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (Date) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    init(request: SolarHistoryDateRequest, onConfirm: @escaping (Date) -> Void) {
        _draft = State(initialValue: SolarCalendarDraft(selection: request.selection,
            timeZoneID: request.timeZoneID, now: request.now))
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Button { draft.moveMonth(-1) } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }.accessibilityLabel("Tháng trước").accessibilityIdentifier("energy-calendar-previous")
                        Spacer(minLength: 0)
                        Text(draft.monthTitle).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                            .accessibilityIdentifier("energy-calendar-month")
                        Spacer(minLength: 0)
                        Button { draft.moveMonth(1) } label: {
                            Image(systemName: "chevron.right").frame(width: 44, height: 44)
                        }.disabled(!draft.canMoveForward).accessibilityLabel("Tháng sau")
                            .accessibilityIdentifier("energy-calendar-next")
                    }.buttonStyle(.plain).tint(SolarTheme.sun)
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(Array(["T2", "T3", "T4", "T5", "T6", "T7", "CN"].enumerated()), id: \.offset) { _, day in
                            Text(day).font(.system(size: 12, weight: .medium)).foregroundStyle(SolarTheme.muted)
                                .frame(maxWidth: .infinity, minHeight: 24).accessibilityHidden(true)
                        }
                        ForEach(Array(draft.days.enumerated()), id: \.offset) { _, day in
                            if let day { dayButton(day) }
                            else { Color.clear.frame(height: 44).accessibilityHidden(true) }
                        }
                    }
                    HStack {
                        Text("Ngày chọn: " + draft.label(draft.selectedDay)).font(.system(size: 14)).monospacedDigit()
                            .accessibilityIdentifier("energy-calendar-selection")
                        Spacer(minLength: 4)
                        Button("Hôm nay") { draft.showToday() }.buttonStyle(.bordered)
                            .accessibilityIdentifier("energy-calendar-today")
                    }
                    Text("Chọn ngày rồi bấm Xong. Bấm Xem lịch sử ở màn hình trước để tải thống kê.")
                        .font(.system(size: 12)).foregroundStyle(SolarTheme.muted)
                }.padding(16)
            }.background(SolarTheme.ink)
                .navigationTitle("Chọn ngày").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Hủy") { dismiss() }.accessibilityIdentifier("energy-calendar-cancel")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Xong") { onConfirm(draft.selectedDay); dismiss() }
                            .accessibilityIdentifier("energy-calendar-confirm")
                    }
                }
        }.tint(SolarTheme.sun).preferredColorScheme(.dark).presentationDetents([.large])
    }

    private func dayButton(_ day: Date) -> some View {
        let selected = draft.calendar.isDate(day, inSameDayAs: draft.selectedDay)
        return Button { draft.select(day) } label: {
            Text(String(draft.calendar.component(.day, from: day)))
                .font(.system(size: 16, weight: selected ? .bold : .medium))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected ? SolarTheme.ink : day > draft.today ? SolarTheme.muted.opacity(0.45) : .white)
                .background(selected ? SolarTheme.sun : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(day > draft.today)
            .accessibilityLabel(draft.label(day)).accessibilityIdentifier("energy-calendar-day-" + draft.label(day))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
