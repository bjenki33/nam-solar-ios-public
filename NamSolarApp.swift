import SwiftUI

@main
struct NamSolarApp: App {
    @State private var store = SolarStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.loggedIn { SolarTabs() }
                else { SignInView() }
            }
            .environment(store)
            .environment(\.locale, Locale(identifier: "vi_VN"))
            .preferredColorScheme(.dark)
            .tint(SolarTheme.sun)
            .task { if scenePhase == .active { store.start() } }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.start() }
                else { store.stop() }
            }
        }
    }
}

enum SolarTab: String, CaseIterable {
    case overview = "Tổng quan", battery = "Pin", history = "Lịch sử", diagnostics = "Hệ thống"
    var icon: SolarNavigationKind {
        switch self {
        case .overview: return .overview
        case .battery: return .battery
        case .history: return .history
        case .diagnostics: return .diagnostics
        }
    }
}

struct SolarTabs: View {
    @Environment(SolarStore.self) private var store
    @State private var selection: SolarTab = .overview
    @State private var confirmLogout = false
    var body: some View {
        ZStack {
            SolarBackground()
            Group {
                switch selection {
                case .overview: OverviewView(selection: $selection).ignoresSafeArea(.container, edges: .bottom)
                case .battery: BatteryView()
                case .history: HistoryView()
                case .diagnostics: DiagnosticsView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 1) {
                    Text("NAM").accessibilityIdentifier("brand-nam")
                    Text("SOLAR").accessibilityIdentifier("brand-solar")
                }.font(.system(size: 9, weight: .bold)).tracking(1)
                    .foregroundStyle(SolarTheme.sun).frame(width: SolarNavigationLayout.brandWidth)
                    .accessibilityElement(children: .contain)
                ForEach(SolarTab.allCases, id: \.self) { tab in
                    Button { selection = tab } label: {
                        VStack(spacing: 4) {
                            SolarNavigationIcon(kind: tab.icon)
                            Text(tab.rawValue).font(.system(size: SolarNavigationLayout.labelSize, weight: .medium))
                                .lineLimit(1).fixedSize()
                                .accessibilityIdentifier("tab-label-" + tab.icon.rawValue)
                        }.foregroundStyle(selection == tab ? SolarTheme.sun : SolarTheme.muted)
                            .frame(maxWidth: .infinity).frame(height: SolarNavigationLayout.height)
                            .overlay(alignment: .bottom) { if selection == tab { Rectangle().fill(SolarTheme.sun).frame(height: 2).padding(.horizontal, 8) } }
                    }.buttonStyle(.plain).accessibilityLabel(tab.rawValue).accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
                Button { confirmLogout = true } label: { Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: SolarNavigationLayout.accountWidth, height: SolarNavigationLayout.height).foregroundStyle(SolarTheme.muted) }
                    .accessibilityLabel("Tài khoản")
            }.background(SolarTheme.panel).overlay(alignment: .bottom) { Rectangle().fill(SolarTheme.border).frame(height: 0.5) }
        }.confirmationDialog("Đăng xuất Nam Solar?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Đăng xuất", role: .destructive) { Task { await store.logout() } }
        }
    }
}
