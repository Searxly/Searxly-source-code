//
//  WebViewRepresentable+YouTube.swift
//  Searxly
//
//  YouTube recovery timers, safe mode, and player protection for WebViewRepresentable.Coordinator.
//

import WebKit

extension WebViewRepresentable.Coordinator {
    func startYouTubeRecoveryTimer() {
        youtubeRecoveryTimer?.invalidate()

        youtubeRecoveryTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self = self, let wv = self.observedWebView else { return }
            guard let url = wv.url, url.host?.contains("youtube") == true || url.host?.contains("youtu.be") == true else {
                self.youtubeRecoveryTimer?.invalidate()
                self.youtubeRecoveryTimer = nil
                return
            }
            let recovery = """
            (function() {
                try {
                    const badSelectors = [
                        'ytd-enforcement-message-view-model', '.ytp-error', '[class*="enforcement"]',
                        'ytd-ad-slot-renderer', '.ytp-ad-overlay-container', '#masthead-ad', '#player-ads',
                        'ytd-player-error-message-renderer'
                    ];
                    badSelectors.forEach(sel => {
                        document.querySelectorAll(sel).forEach(el => {
                            const core = el.closest('ytd-player, #player, .html5-video-player, .html5-video-container, #movie_player') ||
                                         el.querySelector('video') || (el.tagName === 'VIDEO');
                            if (core) {
                                try {
                                    el.style.setProperty('display','block','important');
                                    el.style.setProperty('visibility','visible','important');
                                    el.style.setProperty('opacity','1','important');
                                } catch(_) {}
                                return;
                            }
                            el.style.cssText = 'display:none!important;visibility:hidden!important;';
                            if (el.parentNode) try { el.parentNode.removeChild(el); } catch(_) {}
                        });
                    });
                    document.querySelectorAll('ytd-player, #player, .html5-video-player, .html5-video-container, #movie_player').forEach(p => {
                        p.style.setProperty('display','block','important');
                        p.style.setProperty('visibility','visible','important');
                        p.style.setProperty('opacity','1','important');
                    });
                    document.querySelectorAll('video').forEach(v => {
                        v.style.setProperty('display','block','important');
                        v.style.setProperty('visibility','visible','important');
                        v.style.setProperty('opacity','1','important');
                    });
                } catch(e) {}
            })();
            """
            wv.evaluateJavaScript(recovery, completionHandler: nil)
        }
    }

    func stopYouTubeRecoveryTimer() {
        youtubeRecoveryTimer?.invalidate()
        youtubeRecoveryTimer = nil

        if let src = youtubeHighFreqSource {
            src.cancel()
            youtubeHighFreqSource = nil
        }

        if let wv = observedWebView {
            let pauseJS = """
            (function(){
              try {
                document.querySelectorAll('video, audio').forEach(function(el){
                  try { el.pause(); } catch(e){}
                });
              } catch(e){}
            })();
            """
            wv.evaluateJavaScript(pauseJS, completionHandler: nil)
            wv.configuration.userContentController.removeScriptMessageHandler(forName: "adblockDiagnostic")
        }
    }

    func enterYouTubeSafeMode(on webView: WKWebView) {
        if DeveloperSettings.shared.youTubeCompatibilityMode {
            webView.configuration.userContentController.removeAllUserScripts()
        }

        let protector = """
        (function(){
          try {
            const containers = document.querySelectorAll('ytd-player, #player, .html5-video-player, .html5-video-container, #player-container, #movie_player');
            containers.forEach(p => {
              p.style.setProperty('display', 'block', 'important');
              p.style.setProperty('visibility', 'visible', 'important');
              p.style.setProperty('opacity', '1', 'important');
              p.style.setProperty('min-width', '640px', 'important');
              p.style.setProperty('width', '100%', 'important');
              p.querySelectorAll('video').forEach(v => {
                v.style.setProperty('display', 'block', 'important');
                v.style.setProperty('visibility', 'visible', 'important');
                v.style.setProperty('opacity', '1', 'important');
              });
            });

            if (!document.getElementById('searxly-yt-protector')) {
              const st = document.createElement('style');
              st.id = 'searxly-yt-protector';
              st.textContent = 'ytd-player,#player,.html5-video-player,.html5-video-container,#movie_player{display:block!important;visibility:visible!important;opacity:1!important;min-width:640px!important;width:100%!important;} ytd-player video,#player video,.html5-video-player video,.html5-video-container video,#movie_player video{display:block!important;visibility:visible!important;opacity:1!important;}';
              (document.head || document.documentElement).appendChild(st);
            }

            if (!window.__searxlyYTGuardian) {
              window.__searxlyYTGuardian = true;
              const protectPlayer = () => {
                try {
                  const cores = document.querySelectorAll('ytd-player, #player, .html5-video-player, .html5-video-container, #player-container, #movie_player');
                  cores.forEach(el => {
                    el.style.setProperty('display', 'block', 'important');
                    el.style.setProperty('visibility', 'visible', 'important');
                    el.style.setProperty('opacity', '1', 'important');
                    if (el.tagName !== 'VIDEO') {
                      el.style.setProperty('min-width', '640px', 'important');
                      el.style.setProperty('width', '100%', 'important');
                    }
                    el.querySelectorAll('video').forEach(v => {
                      v.style.setProperty('display', 'block', 'important');
                      v.style.setProperty('visibility', 'visible', 'important');
                      v.style.setProperty('opacity', '1', 'important');
                    });
                  });
                } catch(e){}
              };

              try {
                const guardianObs = new MutationObserver((mutations) => {
                  let needs = false;
                  for (const m of mutations) {
                    if (m.addedNodes && m.addedNodes.length) needs = true;
                    if (m.type === 'attributes' && m.target) {
                      const t = m.target;
                      if (t.closest && t.closest('ytd-player, #player, .html5-video-player, .html5-video-container, #movie_player')) needs = true;
                    }
                  }
                  if (needs) protectPlayer();
                });
                guardianObs.observe(document.documentElement || document.body, {
                  childList: true,
                  subtree: true,
                  attributes: true,
                  attributeFilter: ['style', 'class', 'hidden']
                });
                window.__searxlyYTGuardianObs = guardianObs;
              } catch(e){}

              const guardInterval = setInterval(protectPlayer, 2000);
              window.__searxlyYTGuardInterval = guardInterval;
              protectPlayer();
            }
          } catch(e){}
        })();
        """
        webView.evaluateJavaScript(protector, completionHandler: nil)
    }
}