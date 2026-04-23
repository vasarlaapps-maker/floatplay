import WebKit
import Combine

/// Holds a weak reference to the underlying WKWebView and exposes
/// published navigation state so SwiftUI toolbar buttons can bind to it.
final class BrowserController: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var displayURL = "https://www.youtube.com"

    private weak var webView: WKWebView?
    private var observations: [NSKeyValueObservation] = []
    let floatingWindow = FloatingWindowController()

    /// Called once from YouTubeBrowserView.makeNSView to wire up KVO.
    func attach(_ webView: WKWebView) {
        self.webView = webView
        observations = [
            webView.observe(\.canGoBack, options: .new) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.canGoBack = wv.canGoBack }
            },
            webView.observe(\.canGoForward, options: .new) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.canGoForward = wv.canGoForward }
            },
            webView.observe(\.isLoading, options: .new) { [weak self] wv, _ in
                DispatchQueue.main.async { self?.isLoading = wv.isLoading }
            },
            webView.observe(\.url, options: .new) { [weak self] wv, _ in
                DispatchQueue.main.async {
                    self?.displayURL = wv.url?.absoluteString ?? ""
                }
            }
        ]
    }

    func goBack()    { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload()    { if isLoading { webView?.stopLoading() } else { _ = webView?.reload() } }
    func goHome()    { loadURL("https://www.youtube.com") }

    /// Finds the first <video> element on the page and toggles Picture-in-Picture
    /// using the standard Web API. Must be called from a user-gesture handler.
    func triggerPiP() {
        let js = """
        (function() {
            var video = document.querySelector('video');
            if (!video) { return 'no_video'; }
            if (document.pictureInPictureElement) {
                document.exitPictureInPicture();
                return 'exit';
            } else {
                video.requestPictureInPicture();
                return 'enter';
            }
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    func loadURL(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "https://" + s
        }
        guard let url = URL(string: s) else { return }
        webView?.load(URLRequest(url: url))
    }

    /// Opens only the video in a clean floating window above all other apps.
    /// Pauses the main browser video first so both don't play simultaneously.
    func floatCurrentVideo() {
        guard let url = webView?.url else { return }
        // Pause main browser video before opening the float
        webView?.evaluateJavaScript(
            "document.querySelectorAll('video').forEach(function(v){v.pause();})",
            completionHandler: nil
        )
        floatingWindow.openWithURL(url)
    }
}
