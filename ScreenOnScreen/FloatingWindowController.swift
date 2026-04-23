import AppKit
import WebKit

// MARK: - Key-forwarding panel

/// NSPanel subclass that intercepts arrow key events and seeks the video.
/// Needed because .nonactivatingPanel never becomes key window, so
/// makeFirstResponder on a subview has no effect — we must catch keys here.
private final class VideoPanel: NSPanel {
    weak var webView: WKWebView?

    // Accept key events even though we're non-activating
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        let seconds: Int
        switch event.keyCode {
        case 123: seconds = -5   // ←  back 5 s
        case 124: seconds =  5   // →  forward 5 s
        case 125: seconds = -30  // ↓  back 30 s
        case 126: seconds =  30  // ↑  forward 30 s
        default:
            super.keyDown(with: event)
            return
        }
        let js = "var v=document.querySelector('video');if(v){v.currentTime=Math.max(0,v.currentTime+\(seconds));}"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }
}

// MARK: - Native close button

/// Round ✕ button that fades in on hover. Calls `onClose` when clicked.
private final class CloseButton: NSView {
    var onClose: (() -> Void)?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
    }
    required init?(coder: NSCoder) { fatalError() }

    // Always intercept hits so WKWebView/DragHandle below don't steal the click.
    // point is in superview coordinates — must compare against frame, not bounds.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) ? self : nil
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent)  { isHovered = false }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClose?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(ovalIn: r)
        (isHovered ? NSColor(red: 0.8, green: 0, blue: 0, alpha: 0.9)
                   : NSColor(white: 0, alpha: 0.6)).setFill()
        path.fill()
        NSColor(white: 1, alpha: 0.5).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        // Draw ✕
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let s = NSAttributedString(string: "✕", attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2,
                           y: (bounds.height - sz.height) / 2))
    }
}

/// Container view that tracks mouse-enter/exit over the whole panel
/// and fades the close button in/out accordingly.
private final class HoverContainerView: NSView {
    weak var closeButton: CloseButton?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            closeButton?.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            closeButton?.animator().alphaValue = 0
        }
    }
}

/// The native CloseButton sits above this so its hitTest takes priority.
private final class DragHandleView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    // point is in superview coordinates — must compare against frame, not bounds.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) ? self : nil
    }
}

// MARK: - Floating window controller

/// Opens a borderless floating panel above all other apps.
/// On YouTube: strips page chrome, shows only the video.
/// On all other platforms: loads the full page (Prime, Netflix, etc. need their player UI).
final class FloatingWindowController: NSObject, WKNavigationDelegate, NSWindowDelegate {

    private var panel: NSPanel?
    private var webView: WKWebView?
    /// Tracks whether the currently-loaded page is YouTube so we apply CSS only there.
    private var isYouTubePage = false

    // MARK: - Public

    /// Float the given URL in a borderless PiP-style panel.
    func openWithURL(_ url: URL) {
        isYouTubePage = url.host?.contains("youtube.com") == true
        if let existing = panel, existing.isVisible {
            webView?.load(URLRequest(url: url))
            existing.orderFront(nil)
            return
        }
        createPanel(url: url)
    }

    func close() { stopAndTearDown() }
    var isOpen: Bool { panel?.isVisible == true }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        stopAndTearDown()
    }

    // MARK: - WKNavigationDelegate

    /// Re-apply the hide-chrome CSS after every navigation, but only on YouTube.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Update isYouTubePage in case of in-panel navigation (e.g. SPA route change)
        isYouTubePage = webView.url?.host?.contains("youtube.com") == true
        if isYouTubePage {
            webView.evaluateJavaScript(hideChromScript, completionHandler: nil)
        }
    }

    // MARK: - Chrome-hiding script

    private let hideChromScript = """
    (function() {
      function applyFix() {
        if (document.getElementById('_sos_fix')) return;

        var s = document.createElement('style');
        s.id = '_sos_fix';
        s.textContent = `
          html, body {
            overflow: hidden !important;
            background: #000 !important;
            margin: 0 !important; padding: 0 !important;
          }
          body * { visibility: hidden !important; }

          /* === Video element always full-screen === */
          video {
            visibility: visible !important;
            position: fixed !important;
            top: 0 !important; left: 0 !important;
            width: 100vw !important; height: 100vh !important;
            z-index: 2147483644 !important;
            object-fit: contain !important;
            background: #000 !important;
          }

          /* Helper: show a bottom-bar controls container */
          .sos-controls {
            visibility: visible !important;
            opacity: 1 !important;
            position: fixed !important;
            bottom: 0 !important; left: 0 !important;
            width: 100vw !important;
            z-index: 2147483645 !important;
          }
          .sos-controls * {
            visibility: visible !important;
            opacity: 1 !important;
          }

          /* === YouTube === */
          .ytp-chrome-bottom { visibility: visible !important; position: fixed !important; bottom: 0 !important; left: 0 !important; width: 100vw !important; z-index: 2147483645 !important; }
          .ytp-chrome-bottom * { visibility: visible !important; }
          /* Settings / speed / quality popups sit outside .ytp-chrome-bottom in the DOM */
          .ytp-settings-menu, .ytp-popup, .ytp-panel,
          .ytp-panel-menu, .ytp-panel-header,
          .ytp-menuitem, .ytp-quality-menu,
          .ytp-speed-panel-mode {
            visibility: visible !important;
            opacity: 1 !important;
            z-index: 2147483646 !important;
          }
          .ytp-settings-menu *, .ytp-popup *, .ytp-panel * { visibility: visible !important; opacity: 1 !important; }

          /* === Netflix === */
          .watch-video--bottom-controls-container,
          .PlayerControlsNeo__layout--bottom {
            visibility: visible !important; opacity: 1 !important;
            position: fixed !important; bottom: 0 !important; left: 0 !important;
            width: 100vw !important; z-index: 2147483645 !important;
          }
          .watch-video--bottom-controls-container *,
          .PlayerControlsNeo__layout--bottom * { visibility: visible !important; opacity: 1 !important; }

          /* === Amazon Prime Video === */
          .atvwebplayersdk-overlays-container {
            visibility: visible !important; opacity: 1 !important;
            position: fixed !important; bottom: 0 !important; left: 0 !important;
            width: 100vw !important; z-index: 2147483645 !important;
          }
          .atvwebplayersdk-overlays-container * { visibility: visible !important; opacity: 1 !important; }

          /* === Disney+ === */
          .controls__bottom,
          .btm-media-scrubber-container {
            visibility: visible !important; opacity: 1 !important;
            position: fixed !important; bottom: 0 !important; left: 0 !important;
            width: 100vw !important; z-index: 2147483645 !important;
          }
          .controls__bottom *,
          .btm-media-scrubber-container * { visibility: visible !important; opacity: 1 !important; }

          /* === Apple TV+ === */
          .player-controls-bar,
          .skinnable-controls-bar {
            visibility: visible !important; opacity: 1 !important;
            position: fixed !important; bottom: 0 !important; left: 0 !important;
            width: 100vw !important; z-index: 2147483645 !important;
          }
          .player-controls-bar *,
          .skinnable-controls-bar * { visibility: visible !important; opacity: 1 !important; }

          /* === Hulu === */
          .controls-bar,
          .ControlsWrapper__controls-bar {
            visibility: visible !important; opacity: 1 !important;
            position: fixed !important; bottom: 0 !important; left: 0 !important;
            width: 100vw !important; z-index: 2147483645 !important;
          }
          .controls-bar *,
          .ControlsWrapper__controls-bar * { visibility: visible !important; opacity: 1 !important; }

          /* === Max (HBO Max) === */
          .player-controls-container,
          .player__controls {
            visibility: visible !important; opacity: 1 !important;
            position: fixed !important; bottom: 0 !important; left: 0 !important;
            width: 100vw !important; z-index: 2147483645 !important;
          }
          .player-controls-container *,
          .player__controls * { visibility: visible !important; opacity: 1 !important; }

          /* === Peacock / Paramount+ / generic fallback ===
             Show any element whose class contains 'control' or 'player-bar'
             at the bottom of the screen. */
          [class*='ControlBar'], [class*='controlBar'],
          [class*='PlayerControls'], [class*='playerControls'],
          [class*='player-controls'], [class*='playback-controls'],
          [class*='playbackControls'], [class*='video-controls'],
          [class*='videoControls'] {
            visibility: visible !important; opacity: 1 !important;
            position: fixed !important; bottom: 0 !important; left: 0 !important;
            width: 100vw !important; z-index: 2147483645 !important;
          }
          [class*='ControlBar'] *, [class*='controlBar'] *,
          [class*='PlayerControls'] *, [class*='playerControls'] *,
          [class*='player-controls'] *, [class*='playback-controls'] *,
          [class*='playbackControls'] *, [class*='video-controls'] *,
          [class*='videoControls'] * { visibility: visible !important; opacity: 1 !important; }
        `;
        (document.head || document.documentElement).appendChild(s);
      }

      applyFix();
      setTimeout(applyFix, 400);
      setTimeout(applyFix, 1200);
      setTimeout(applyFix, 3000);

      var obs = new MutationObserver(function() {
        if (!document.getElementById('_sos_fix')) applyFix();
      });
      obs.observe(document.documentElement, { childList: true, subtree: false });
    })();
    """

    // MARK: - Private

    private func stopAndTearDown() {
        webView?.evaluateJavaScript(
            "document.querySelectorAll('video,audio').forEach(function(m){m.pause();m.src='';});",
            completionHandler: nil
        )
        webView?.stopLoading()
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        webView?.navigationDelegate = nil
        webView = nil
        panel?.delegate = nil
        panel?.close()
        panel = nil
    }

    private func createPanel(url: URL) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let fullRect = screen.frame

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.mediaTypesRequiringUserActionForPlayback = []
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        if isYouTubePage {
            let userScript = WKUserScript(
                source: hideChromScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(userScript)
        }

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.autoresizingMask = [.width, .height]
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        // Transparent background so rounded corners show through
        wv.setValue(false, forKey: "drawsBackground")
        wv.load(URLRequest(url: url))

        // Default 480×270 (16:9), top-right corner, with 20px margin
        let defaultSize = NSSize(width: 480, height: 270)
        let margin: CGFloat = 20
        let visibleRect = screen.visibleFrame   // respects menu bar + dock
        let defaultRect = NSRect(
            x: visibleRect.maxX - defaultSize.width - margin,
            y: visibleRect.maxY - defaultSize.height - margin,
            width: defaultSize.width,
            height: defaultSize.height
        )

        // Borderless panel — no title bar, pure video like real PiP
        let p = VideoPanel(
            contentRect: defaultRect,
            styleMask: [.resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.webView = wv
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isFloatingPanel = true
        p.backgroundColor = .black
        p.isOpaque = true
        p.hasShadow = true
        p.delegate = self
        p.minSize = NSSize(width: 240, height: 135)

        // Use HoverContainerView so we can fade the close button in/out on window hover.
        let container = HoverContainerView(frame: NSRect(origin: .zero, size: defaultSize))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        wv.frame = container.bounds
        wv.autoresizingMask = [.width, .height]
        container.addSubview(wv)

        p.contentView = container

        // Transparent drag handle over the top 40px strip.
        let dragHandle = DragHandleView(
            frame: NSRect(x: 0,
                          y: defaultSize.height - 40,
                          width: defaultSize.width,
                          height: 40)
        )
        dragHandle.autoresizingMask = [.width, .minYMargin]
        dragHandle.wantsLayer = true
        dragHandle.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(dragHandle)

        // Native close button — top-right corner, added last so it wins hit-test.
        let closeBtn = CloseButton(frame: NSRect(
            x: defaultSize.width - 34,
            y: defaultSize.height - 34,
            width: 28,
            height: 28
        ))
        closeBtn.alphaValue = 0  // hidden until mouse enters the window
        closeBtn.autoresizingMask = [.minXMargin, .minYMargin]
        closeBtn.onClose = { [weak self] in self?.stopAndTearDown() }
        container.addSubview(closeBtn)
        container.closeButton = closeBtn

        p.setFrame(defaultRect, display: true)
        p.makeKeyAndOrderFront(nil)

        self.panel = p
        self.webView = wv
    }
}
