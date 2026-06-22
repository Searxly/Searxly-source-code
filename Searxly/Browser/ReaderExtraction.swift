//
//  ReaderExtraction.swift
//  Searxly
//
//  Shared "readability-lite" extractor for Reader mode. Used by both reader entry points
//  (the toolbar button via NavigationCoordinator and WebViewRepresentable.toggleReaderMode).
//
//  Goals:
//  - Strip chrome + junk (nav/header/footer/aside, share/social/related/recommended/newsletter/promo
//    widgets, ads, comments) AND icon clutter (inline <svg>, buttons, forms) — the latter is why a
//    giant black share glyph used to dominate the reader on sites like Forbes.
//  - Pick the densest real article container by paragraph/text scoring, not just the first <article>.
//

import Foundation

enum ReaderExtraction {

    /// Returns a JS object: { title, html, len }. `html` is empty when nothing readable was found.
    static let script: String = """
    (function() {
      try {
        if (!document.body) return { title: document.title || '', html: '', len: 0 };
        var root = document.body.cloneNode(true);

        // 1) Remove non-content tags outright (svg/button/form kill the icon clutter).
        var junkTags = ['script','style','noscript','template','iframe','svg','canvas','video','audio',
                        'button','form','input','select','textarea','nav','header','footer','aside'];
        junkTags.forEach(function(t){ root.querySelectorAll(t).forEach(function(e){ e.remove(); }); });

        // 2) Remove common chrome/widget blocks by role / class hints.
        var junkSel = [
          '[aria-hidden="true"]','[role="navigation"]','[role="complementary"]','[role="banner"]','[role="contentinfo"]',
          '[class*="share"]','[class*="social"]','[class*="related"]','[class*="recommend"]','[class*="newsletter"]',
          '[class*="promo"]','[class*="subscribe"]','[class*="advert"]','[class*="sidebar"]','[class*="comment"]',
          '[class*="trending"]','[class*="more-from"]','[class*="paywall"]','[class*="cookie"]','[class*="ad-"]','[class*="-ad"]'
        ];
        junkSel.forEach(function(s){ try { root.querySelectorAll(s).forEach(function(e){ e.remove(); }); } catch(e){} });

        function textLen(el){ return ((el.innerText || el.textContent || '').trim()).length; }

        // 3) Score likely article containers; pick the densest.
        var best = null, bestScore = 0;
        var prefSel = ['article','main','[role="main"]','[itemprop="articleBody"]',
                       '.article-body','.article-content','.articleBody','.post-content','.entry-content','#content'];
        prefSel.forEach(function(sel){
          root.querySelectorAll(sel).forEach(function(e){
            var score = textLen(e) + e.querySelectorAll('p').length * 50;
            if (score > bestScore) { bestScore = score; best = e; }
          });
        });

        // 4) Fallback: scan blocks for paragraph density.
        if (!best || bestScore < 250) {
          root.querySelectorAll('div,section').forEach(function(e){
            var pc = e.querySelectorAll(':scope > p').length;
            if (pc >= 3) {
              var score = textLen(e) + pc * 50;
              if (score > bestScore) { bestScore = score; best = e; }
            }
          });
        }

        var container = best || root;

        // 5) Drop icon-only / empty links left inside the chosen container.
        container.querySelectorAll('a').forEach(function(a){ if (!((a.textContent||'').trim())) a.remove(); });

        var html = container.innerHTML || '';
        return { title: document.title || '', html: html, len: textLen(container) };
      } catch (e) {
        return { title: document.title || '', html: '', len: 0 };
      }
    })();
    """
}
