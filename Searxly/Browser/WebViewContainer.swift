//
//  WebViewContainer.swift
//  Searxly
//
//  Dedicated NSView host for WKWebView.
//  Responsibilities:
//  - Guarantee the WKWebView always has correct bounds matching its SwiftUI parent
//    (addresses the core cause of "super wide" / broken initial layout on pages like speedtest).
//  - Dispatch 'resize' events + force reflow into the web content on size changes and key lifecycle moments.
//  - Provide an explicit stabilizeLayout() hook for the representable and navigation delegate.
//
//  This is the single place that owns frame syncing and layout-driven web content stabilization.
//  All WKWebViews (standard + private, fresh + woken from hibernation) benefit automatically
//  because they are always hosted through WebViewRepresentable → WebViewContainer.
//

import AppKit
import WebKit

final class WebViewContainer: NSView {

    let webView: WKWebView

    private var stabilizationWorkItem: DispatchWorkItem?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)

        // Use autoresizingMask so the webview automatically follows the container's size.
        // This is more reliable than Auto Layout constraints in SwiftUI NSViewRepresentable
        // scenarios where the parent view's frame is driven directly by the layout engine.
        // We still do explicit syncs in setFrameSize + layout for belt-and-suspenders.
        webView.autoresizingMask = [.width, .height]
        webView.frame = bounds
        addSubview(webView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout synchronization (the heart of the wide-page fix)

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // SwiftUI often sets the frame directly on the NSViewRepresentable's view.
        // Catch it here so the webview gets the size immediately and we can notify the page.
        webView.frame = bounds
        scheduleStabilization()
    }

    override func layout() {
        super.layout()

        // Force exact bounds on the webview. This ensures that even if the representable
        // received a size update after the page started its first layout/paint/JS measurements,
        // the web content sees the correct viewport width.
        if webView.frame.size != bounds.size {
            webView.frame = bounds
        }

        // Throttled stabilization: tell the page its container size may have changed.
        // Critical for responsive sites, canvas measurements, media queries, and SPAs
        // that snapshot window dimensions early.
        scheduleStabilization()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            // The view now has a real window and (very soon) real size.
            // Give SwiftUI one runloop tick to settle the final bounds, then stabilize.
            // We do a stronger multi-pass stabilization on first attach.
            DispatchQueue.main.async { [weak self] in
                self?.stabilizeLayout(repeats: 3)
            }
        }
    }

    // MARK: - Public stabilization API (called from representable + coordinator)

    /// Explicitly sync frame and push a resize + reflow into the web content.
    /// Safe to call at any time (e.g. after tab wake, explicit reload, or from didFinish).
    /// Pass repeats > 0 to schedule additional stabilization passes (helps JS-heavy sites
    /// like speedtest that do measurement + positioning in later frames or after data load).
    func stabilizeLayout(repeats: Int = 0) {
        webView.frame = bounds
        performImmediateStabilization()

        if repeats > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.webView.frame = self?.bounds ?? .zero
                self?.performImmediateStabilization()
                if repeats > 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                        self?.webView.frame = self?.bounds ?? .zero
                        self?.performImmediateStabilization()
                        if repeats > 2 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                                self?.webView.frame = self?.bounds ?? .zero
                                self?.performImmediateStabilization()
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private helpers

    private func scheduleStabilization() {
        stabilizationWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.performImmediateStabilization()
        }
        stabilizationWorkItem = work

        // ~1 frame throttle. Enough to coalesce rapid SwiftUI layout passes
        // (sidebar toggle, window resize) without perceptible lag.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: work)
    }

    private func performImmediateStabilization() {
        // Defensive JS: dispatch real resize events + aggressive but safe reflow tricks.
        // The combination of resize + temporary width perturbation + offset reads helps
        // force many canvas / flex / absolutely positioned / measurement-heavy pages
        // (speedtest gauges, hero buttons, dashboards) to re-measure and re-center.
        //
        // We also forcefully set html/body to 100% width + auto horizontal margins with
        // !important. This ensures that any inner "centered" container the site uses
        // (max-width + margin: 0 auto for the GO button / hero / server selector) can
        // actually center itself inside the full available content pane width instead
        // of appearing left-biased or stuck to the left edge of the web area.
        //
        // CRITICAL: YouTube's player does its own complex responsive measurement + shadow DOM
        // layout on first paint / during navigation within the watch page. The width forcing +
        // subpixel nudge here (even without the early user script) has been observed to collapse
        // the ytd-player / html5-video-container computed height to 0 while the underlying
        // media element still successfully decodes and plays the *audio* track. Result: sound
        // with no visible video. We therefore skip the style mutations + nudge for YT hosts.
                // (Safer quality help lives in the YT-specific protector style + sizing hints in
                // WebViewRepresentable.enterYouTubeSafeMode / ytCleanup.)
        let js = """
        (function() {
            try {
                const win = window;
                const docEl = document.documentElement;
                const body = document.body;
                const h = (location.hostname || '').toLowerCase();
                const isYT = h.includes('youtube.com') || h.includes('youtu.be');

                if (!isYT) {
                    // Force the root containing blocks to the full pane width with !important.
                    // This is the key for sites whose main test UI lives in a centered block.
                    // If the body or html ended up with a left-biased or constrained width from
                    // early measurement or our previous max-width rule, 'margin: auto' does nothing
                    // useful and the GO button / labels appear too far left with empty space on the right.
                    docEl.style.setProperty('width', '100%', 'important');
                    if (body) {
                        body.style.setProperty('width', '100%', 'important');
                        body.style.setProperty('margin-left', 'auto', 'important');
                        body.style.setProperty('margin-right', 'auto', 'important');
                    }

                    // Nudge trick: temporarily change a dimension by a fraction of a pixel then restore.
                    // This often kicks lazy/RAF-based centering and measurement code that missed the first resize.
                    const origWidth = docEl.style.width;
                    const measured = win.innerWidth || docEl.clientWidth || 0;
                    if (measured > 0) {
                        docEl.style.width = (measured + 0.5) + 'px';
                        // force
                        void docEl.offsetWidth;
                        if (body) void body.offsetWidth;
                        docEl.style.width = origWidth || '';
                        void docEl.offsetWidth;
                    }
                }

                // Primary: tell the page the viewport changed. (Safe and useful for YT too.)
                win.dispatchEvent(new Event('resize'));

                // Secondary: some pages react to visualViewport.
                if (win.visualViewport) {
                    try { win.dispatchEvent(new Event('resize')); } catch (_) {}
                }

                // Force style recalc / layout.
                void docEl.offsetWidth;
                if (body) void body.offsetWidth;

                // One more resize after the forcing + nudge.
                win.dispatchEvent(new Event('resize'));
            } catch (_) {
                // Never let layout JS break the page or the host.
            }
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
