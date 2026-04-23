import SwiftUI
import WebKit

/// Full YouTube browser view. Uses the default (persistent) WKWebsiteDataStore
/// so login cookies survive app restarts. PiP is handled by YouTube's own
/// player button, which macOS WebKit exposes natively across all apps.
struct YouTubeBrowserView: NSViewRepresentable {
    @ObservedObject var controller: BrowserController

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Persistent store — cookies/login survive app restarts
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // Identify as Safari so YouTube serves the full desktop site
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/17.0 Safari/605.1.15"

        controller.attach(webView)
        webView.load(URLRequest(url: URL(string: "https://www.youtube.com")!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        // Open target="_blank" links inside the same view
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
