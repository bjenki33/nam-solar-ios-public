import SwiftUI
import WebKit

struct SignInView: View {
    @Environment(SolarStore.self) private var store
    @State private var showLogin = false
    @State private var nonce = UUID().uuidString
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ZStack {
            SolarBackground()
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                Spacer()
                Image(systemName: "sun.max.fill").font(.system(size: 64, weight: .light)).foregroundStyle(SolarTheme.sun)
                Text("NAM SOLAR").font(.caption.weight(.bold)).tracking(5).foregroundStyle(SolarTheme.sun)
                Text("Ngôi nhà của bạn.\nNăng lượng của bạn.")
                    .font(.system(size: 40, weight: .medium, design: .serif)).fixedSize(horizontal: false, vertical: true)
                Text("Theo dõi điện mặt trời, pin lưu trữ và điện lưới trong một ứng dụng riêng cho iPhone.")
                    .foregroundStyle(.secondary).font(.body).lineSpacing(5)
                Label("Chỉ theo dõi. Không điều khiển biến tần.", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(SolarTheme.leaf)
                Spacer()
                if let error { Text(error).font(.footnote).foregroundStyle(.orange) }
                Button {
                    nonce = UUID().uuidString
                    error = nil
                    showLogin = true
                } label: {
                    HStack { Text("Đăng nhập Nam Solar"); Spacer(); Image(systemName: "arrow.right") }
                        .font(.headline).padding(20).foregroundStyle(SolarTheme.ink)
                        .background(SolarTheme.sun, in: RoundedRectangle(cornerRadius: 22))
                }.disabled(busy)
                Text("solar.bocphot.me · Phiên được lưu trong Keychain")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }.padding(28).frame(minHeight: geometry.size.height)
                }
            }
            if busy { ProgressView("Đang hoàn tất đăng nhập").padding(28).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24)) }
        }
        .sheet(isPresented: $showLogin) {
            NavigationStack {
                AuthorizationWebView(state: nonce) { result in
                    showLogin = false
                    switch result {
                    case .success(let code):
                        busy = true
                        Task {
                            defer { busy = false }
                            do { try await store.login(code: code) }
                            catch { self.error = "Không thể hoàn tất đăng nhập. " + error.localizedDescription }
                        }
                    case .failure(let failure): error = failure.localizedDescription
                    }
                }
                .navigationTitle("Đăng nhập solar.bocphot.me")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Hủy") { showLogin = false } } }
            }
        }
    }
}

struct AuthorizationWebView: UIViewRepresentable {
    let state: String
    let completion: (Result<String, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(state: state, completion: completion) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.load(URLRequest(url: SolarConfig.authorizeURL(state: state)))
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) { }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        let state: String
        let completion: (Result<String, Error>) -> Void
        private var finished = false
        init(state: String, completion: @escaping (Result<String, Error>) -> Void) {
            self.state = state
            self.completion = completion
        }
        private func finish(_ result: Result<String, Error>) {
            guard !finished else { return }
            finished = true
            completion(result)
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if let redirect = URL(string: SolarConfig.redirect), url.host == redirect.host, url.path == redirect.path {
                decisionHandler(.cancel)
                if let code = SolarConfig.authorizationCode(from: url, expectedState: state) { finish(.success(code)) }
                else { finish(.failure(SolarError.invalidResponse)) }
                return
            }
            decisionHandler(url.scheme == "https" && url.host == SolarConfig.base.host && url.port == nil ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { finish(.failure(error)) }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { finish(.failure(error)) }
        }
    }
}
