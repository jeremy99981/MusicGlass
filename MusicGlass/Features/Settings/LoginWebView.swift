import SwiftUI
import WebKit

struct LoginWebView: UIViewRepresentable {
    let onLoginSuccess: ([HTTPCookie], String?, String?) -> Void
    @Binding var isPresented: Bool

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

        let url = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&passive=true&continue=https://music.youtube.com/")!
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: LoginWebView
        private var didCompleteLogin = false
        private var retryCount = 0

        init(_ parent: LoginWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkCookies(in: webView)
        }

        private func checkCookies(in webView: WKWebView) {
            guard !didCompleteLogin else { return }
            guard webView.url?.host?.contains("music.youtube.com") == true else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let hasSapisid = cookies.contains { cookie in
                    cookie.name == "SAPISID" &&
                    !cookie.isExpired &&
                    cookie.domain.lowercased().contains("youtube.com")
                }
                guard hasSapisid else { return }

                DispatchQueue.main.async {
                    let script = """
                    (() => {
                      const cfg = (window.ytcfg && window.ytcfg.data_) || (window.yt && window.yt.config_) || {};
                      const getValue = (key) => {
                        if (window.ytcfg && typeof window.ytcfg.get === 'function') {
                          const value = window.ytcfg.get(key);
                          if (value) return value;
                        }
                        return cfg[key] || null;
                      };
                      return {
                        dataSyncId: getValue('DATASYNC_ID'),
                        visitorData: getValue('VISITOR_DATA')
                      };
                    })();
                    """
                    webView.evaluateJavaScript(script) { result, _ in
                        let dict = result as? [String: Any]
                        let dataSyncId = (dict?["dataSyncId"] as? String)
                            .map { $0.components(separatedBy: "||").first ?? $0 }
                            .flatMap { $0.isEmpty ? nil : $0 }
                        let visitorData = (dict?["visitorData"] as? String).flatMap { $0.isEmpty ? nil : $0 }

                        DispatchQueue.main.async {
                            guard !self.didCompleteLogin else { return }
                            guard dataSyncId != nil else {
                                self.retryCount += 1
                                if self.retryCount <= 12 {
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        self.checkCookies(in: webView)
                                    }
                                }
                                return
                            }
                            self.didCompleteLogin = true
                            self.parent.onLoginSuccess(cookies, dataSyncId, visitorData)
                            self.parent.isPresented = false
                        }
                    }
                }
            }
        }
    }
}

private extension HTTPCookie {
    var isExpired: Bool {
        guard let expiresDate else { return false }
        return expiresDate <= Date()
    }
}
