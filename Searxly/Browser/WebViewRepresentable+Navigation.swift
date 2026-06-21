//
//  WebViewRepresentable+Navigation.swift
//  Searxly
//
//  WKNavigationDelegate methods and certificate handling for WebViewRepresentable.Coordinator.
//

import WebKit

extension WebViewRepresentable.Coordinator {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        DispatchQueue.main.async { self.parent.isLoading = true }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.observedContainer?.stabilizeLayout(repeats: 2)
            self.parent.requestStabilization()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async { self.parent.isLoading = false }
        if DeveloperSettings.shared.isEnabled {
            print("[AdBlock] Page finished loading: \(webView.url?.absoluteString ?? "unknown")")
        }

        DispatchQueue.main.async {
            self.observedContainer?.stabilizeLayout(repeats: 3)
            self.parent.requestStabilization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            let js = """
            (function(){
              try {
                const h = Math.max(document.body ? document.body.scrollHeight : 0, document.documentElement.scrollHeight || 0);
                if (h < 80) {
                  window.dispatchEvent(new Event('resize'));
                  const de = document.documentElement;
                  const old = de.style.width;
                  const w = window.innerWidth || 800;
                  de.style.width = (w + 0.6) + 'px';
                  void de.offsetWidth;
                  de.style.width = old || '100%';
                  void de.offsetWidth;
                  window.dispatchEvent(new Event('resize'));
                }
              } catch(e){}
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
            self.observedContainer?.stabilizeLayout(repeats: 1)
        }

        if let u = webView.url {
            let settledTitle = webView.title ?? ""
            NotificationCenter.default.post(
                name: BrowserState.historyTitleSnapshotNotification,
                object: nil,
                userInfo: ["url": u, "title": settledTitle]
            )
        }

        if let url = webView.url, (url.host?.contains("youtube.com") == true || url.host?.contains("youtu.be") == true) {
            enterYouTubeSafeMode(on: webView)
            YouTubeAdBlocker.shared.reapplyProtection(on: webView)

            if DeveloperSettings.shared.youTubeCompatibilityMode {
                webView.configuration.userContentController.removeAllUserScripts()
            }

            if isYouTubeVideoPage(url) {
                let ytCleanup = """
                (function() {
                    'use strict';
                    try {
                        const toHide = [
                            'ytd-ad-slot-renderer', 'ytd-promoted-sparkles-web-renderer', '#player-ads',
                            '#masthead-ad', '[data-ad-slot]',
                            '.ytp-ad-overlay-container',
                            'ytd-enforcement-message-view-model', '.ytp-error', 'yt-mealbar-promo-renderer',
                            'ytd-player-error-message-renderer', '[class*="enforcement"]',
                            'ytd-ad-overlay-renderer'
                        ];
                        toHide.forEach(sel => {
                            document.querySelectorAll(sel).forEach(el => {
                                const core = el.closest('ytd-player, #player, .html5-video-player, .html5-video-container, #movie_player') ||
                                             el.querySelector('video') || (el.tagName === 'VIDEO');
                                if (core) {
                                    try {
                                        el.style.setProperty('display', 'block', 'important');
                                        el.style.setProperty('visibility', 'visible', 'important');
                                        el.style.setProperty('opacity', '1', 'important');
                                    } catch(_) {}
                                    return;
                                }
                                el.style.cssText = 'display:none !important; visibility:hidden !important; opacity:0 !important; pointer-events:none !important;';
                                if (el.parentNode) {
                                    try { el.parentNode.removeChild(el); } catch(_) {}
                                }
                            });
                        });

                        const skipButtons = document.querySelectorAll(
                            '.ytp-ad-skip-button, .ytp-skip-ad-button, ' +
                            'button[aria-label*="Skip"], .ytp-ad-skip-button-modern, ' +
                            '[class*="skip-ad"], [class*="ad-skip"]'
                        );
                        skipButtons.forEach(btn => {
                            if (btn && btn.offsetParent !== null) {
                                try { btn.click(); btn.dispatchEvent(new MouseEvent('click', {bubbles:true})); } catch(_) {}
                            }
                        });

                        const playerContainers = document.querySelectorAll(
                            'ytd-player, #player, .html5-video-player, .html5-video-container, #player-container, #movie_player'
                        );
                        playerContainers.forEach(p => {
                            p.style.setProperty('display', 'block', 'important');
                            p.style.setProperty('visibility', 'visible', 'important');
                            p.style.setProperty('opacity', '1', 'important');
                            p.style.setProperty('min-width', '640px', 'important');
                            p.style.setProperty('width', '100%', 'important');
                        });

                        const videos = document.querySelectorAll('video');
                        videos.forEach(v => {
                            v.style.setProperty('display', 'block', 'important');
                            v.style.setProperty('visibility', 'visible', 'important');
                            v.style.setProperty('opacity', '1', 'important');
                        });
                    } catch(e) {}
                })();
                """
                webView.evaluateJavaScript(ytCleanup, completionHandler: nil)

                let delays: [TimeInterval] = [0.4, 0.9, 1.4, 2.0, 3.0, 4.5, 6.5]
                for delay in delays {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak webView] in
                        webView?.evaluateJavaScript(ytCleanup, completionHandler: nil)
                    }
                }

                youtubeHighFreqSource?.cancel()
                var intervalCount = 0
                let src: DispatchSourceTimer = DispatchSource.makeTimerSource(queue: .main)
                src.schedule(deadline: .now() + .milliseconds(300), repeating: .milliseconds(300), leeway: .milliseconds(60))
                src.setEventHandler { [weak webView] in
                    intervalCount += 1
                    guard let wv = webView else { src.cancel(); return }
                    if intervalCount > 26 {
                        src.cancel()
                        return
                    }
                    wv.evaluateJavaScript("(document.querySelectorAll('video').length > 0 && Array.from(document.querySelectorAll('video')).some(v => (v.videoWidth||0) >= 640))", completionHandler: { result, _ in
                        if let good = result as? Bool, good {
                            wv.evaluateJavaScript(ytCleanup, completionHandler: nil)
                            src.cancel()
                            return
                        }
                    })
                    wv.evaluateJavaScript(ytCleanup, completionHandler: nil)
                }
                youtubeHighFreqSource = src
                src.resume()

                let observerJS = """
                (function() {
                    if (window.__searxlyYTForcePlay) return;
                    window.__searxlyYTForcePlay = true;

                    const doNuke = () => {
                        const bad = document.querySelectorAll(
                            'ytd-enforcement-message-view-model, .ytp-error, [class*="enforcement"], ' +
                            'ytd-ad-slot-renderer, .ytp-ad-overlay-container, #masthead-ad, #player-ads'
                        );
                        bad.forEach(el => {
                            const core = el.closest('ytd-player, #player, .html5-video-player, .html5-video-container, #movie_player') ||
                                         el.querySelector('video') || (el.tagName === 'VIDEO');
                            if (core) {
                                try {
                                    el.style.setProperty('display', 'block', 'important');
                                    el.style.setProperty('visibility', 'visible', 'important');
                                    el.style.setProperty('opacity', '1', 'important');
                                } catch(_) {}
                                return;
                            }
                            el.style.cssText = 'display:none!important;visibility:hidden!important;';
                            if (el.parentNode) try { el.parentNode.removeChild(el); } catch(_) {}
                        });
                        document.querySelectorAll('video').forEach(v => {
                            v.style.setProperty('display','block','important');
                            v.style.setProperty('visibility','visible','important');
                            v.style.setProperty('opacity','1','important');
                        });
                    };

                    const obs = new MutationObserver(doNuke);
                    obs.observe(document.documentElement || document.body, { childList: true, subtree: true });

                    doNuke(); setTimeout(doNuke, 400); setTimeout(doNuke, 900);
                    setTimeout(() => { try { obs.disconnect(); } catch(_) {} }, 12000);
                })();
                """
                webView.evaluateJavaScript(observerJS, completionHandler: nil)

                startYouTubeRecoveryTimer()

                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak webView] in
                    webView?.evaluateJavaScript("""
                    (function(){
                      try {
                        const vids = Array.from(document.querySelectorAll('video'));
                        const info = vids.map(v => ({ w: v.videoWidth||0, h: v.videoHeight||0, ready: v.readyState, src: (v.currentSrc||'').slice(0,120) }));
                        console.log('[YT Quality]', info);
                        return info;
                      } catch(e){ return null; }
                    })();
                    """, completionHandler: { res, _ in
                        if DeveloperSettings.shared.isEnabled || DeveloperSettings.shared.verboseTabLifecycleLogging {
                            print("[YT Quality] video natural sizes after settle:", res ?? "n/a")
                        }
                    })
                }
            } else {
                stopYouTubeRecoveryTimer()
                youtubeHighFreqSource?.cancel()
                youtubeHighFreqSource = nil
            }
        } else {
            stopYouTubeRecoveryTimer()
            youtubeHighFreqSource?.cancel()
            youtubeHighFreqSource = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async {
            self.parent.isLoading = false
            if DeveloperSettings.shared.isEnabled && DeveloperSettings.shared.verboseTabLifecycleLogging {
                print("[Dev] WebView error: \(error.localizedDescription)")
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        DispatchQueue.main.async {
            self.parent.isLoading = false
            if DeveloperSettings.shared.isEnabled && DeveloperSettings.shared.verboseTabLifecycleLogging {
                print("[Dev] WebView provisional navigation failed: \(error.localizedDescription) for \(webView.url?.absoluteString ?? "unknown")")
            }
            self.observedContainer?.stabilizeLayout(repeats: 1)
        }
    }

    func webView(_ webView: WKWebView,
                 didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Only bypass certificate validation for unambiguous loopback / mDNS addresses.
        // Removed the previous `host.contains("searx")` check: any attacker-controlled domain
        // containing "searx" (e.g. searx-evil.com) would have received unconditional trust.
        if let serverTrust = challenge.protectionSpace.serverTrust {
            let host = challenge.protectionSpace.host.lowercased()
            let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
            let isMDNS = host.hasSuffix(".local")
            if isLoopback || isMDNS {
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
            }
        }
        completionHandler(.performDefaultHandling, nil)
    }
}