//
//  GrokipediaArticleClient.swift
//  Searxly
//
//  Fetches the opening paragraph of a Grokipedia article directly (no third-party API).
//

import Foundation

struct GrokipediaArticleSnippet: Sendable, Equatable {
    let title: String
    let firstParagraph: String
    let pageURL: String
    let imageURL: URL?
    let facts: [KnowledgeFact]
}

enum GrokipediaArticleClient {

    private static let cacheTTL: TimeInterval = 2 * 24 * 60 * 60
    private static let maxCacheEntries = 200
    private static var cache: [String: (snippet: GrokipediaArticleSnippet, fetchedAt: Date)] = [:]
    private static let cacheLock = NSLock()

    private static let userAgent = "Searxly/1.0 (Knowledge Panel; macOS)"

    static func fetchFirstParagraph(slug: String) async -> GrokipediaArticleSnippet? {
        let normalizedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSlug.isEmpty else { return nil }

        if let cached = cachedSnippet(for: normalizedSlug) {
            return cached
        }

        let pageURL = GrokipediaSlugCatalog.pageURL(for: normalizedSlug)
        guard let url = grokipediaRequestURL(for: pageURL) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                return nil
            }

            guard isValidArticlePage(html, expectedSlug: normalizedSlug) else {
                return nil
            }

            guard let paragraph = extractFirstParagraph(from: html), paragraph.count >= 48 else {
                return nil
            }

            let title = extractTitle(from: html, fallbackSlug: normalizedSlug)
            let imageURL = extractArticleImage(from: html)
            let snippet = GrokipediaArticleSnippet(
                title: title,
                firstParagraph: paragraph,
                pageURL: pageURL,
                imageURL: imageURL,
                facts: extractInfoboxFacts(from: html)
            )
            store(snippet, for: normalizedSlug)
            return snippet
        } catch {
            return nil
        }
    }

    // MARK: - Cache

    private static func cachedSnippet(for slug: String) -> GrokipediaArticleSnippet? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let entry = cache[slug] else { return nil }
        if Date().timeIntervalSince(entry.fetchedAt) > cacheTTL {
            cache.removeValue(forKey: slug)
            return nil
        }
        return entry.snippet
    }

    private static func store(_ snippet: GrokipediaArticleSnippet, for slug: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if cache.count >= maxCacheEntries, let oldestKey = cache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key {
            cache.removeValue(forKey: oldestKey)
        }
        cache[slug] = (snippet, Date())
    }

    // MARK: - HTML parsing

    private static func grokipediaRequestURL(for pageURL: String) -> URL? {
        if let direct = URL(string: pageURL) {
            return direct
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: "_()-")
        guard let encoded = pageURL.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: encoded)
    }

    private static func isValidArticlePage(_ html: String, expectedSlug: String) -> Bool {
        if let title = extractMetaProperty(name: "og:title", from: html),
           title.localizedCaseInsensitiveContains("article not found") {
            return false
        }

        if let canonical = extractLinkRelCanonical(from: html), canonical.contains("/page/") {
            let slugFragment = canonical.split(separator: "/").last.map(String.init) ?? ""
            let decoded = slugFragment
                .replacingOccurrences(of: "%28", with: "(")
                .replacingOccurrences(of: "%29", with: ")")
            if normalizeSlug(decoded) != normalizeSlug(expectedSlug) {
                return false
            }
        }

        return true
    }

    private static func normalizeSlug(_ slug: String) -> String {
        slug.lowercased().replacingOccurrences(of: "-", with: "_")
    }

    private static func extractLinkRelCanonical(from html: String) -> String? {
        let pattern = #"<link[^>]+rel="canonical"[^>]+href="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            let altPattern = #"<link[^>]+href="([^"]*)"[^>]+rel="canonical""#
            guard let altRegex = try? NSRegularExpression(pattern: altPattern, options: .caseInsensitive),
                  let altMatch = altRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let altRange = Range(altMatch.range(at: 1), in: html) else {
                return nil
            }
            return String(html[altRange])
        }
        return String(html[range])
    }

    private static func extractFirstParagraph(from html: String) -> String? {
        let articleHTML: String
        if let markerRange = html.range(of: "<!-- Article body") {
            articleHTML = String(html[markerRange.lowerBound...])
        } else {
            articleHTML = html
        }

        let patterns = [
            #"data-tts-block="true"[^>]*>(.*?)</span>"#,
            #"<span[^>]*data-tts-block="true"[^>]*>(.*?)</span>"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]),
                  let match = regex.firstMatch(in: articleHTML, range: NSRange(articleHTML.startIndex..., in: articleHTML)),
                  let range = Range(match.range(at: 1), in: articleHTML) else {
                continue
            }

            let raw = String(articleHTML[range])
            let text = stripHTML(raw)
            if isPlausibleOpeningParagraph(text) {
                return text
            }
        }

        for metaName in ["description", "og:description"] {
            let metaText: String?
            if metaName == "og:description" {
                metaText = extractMetaProperty(name: metaName, from: html)
            } else {
                metaText = extractMetaContent(named: metaName, from: html)
            }
            if let metaText {
                let text = stripHTML(metaText)
                if isPlausibleOpeningParagraph(text) {
                    return text
                }
            }
        }

        return nil
    }

    private static func isPlausibleOpeningParagraph(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 48 else { return false }

        let lower = trimmed.lowercased()
        let chromeMarkers = [
            "interactive-widget=resizes-content",
            "<meta",
            "googletagmanager",
            " — grokipedia",
            " - grokipedia",
            "(function()",
        ]
        if chromeMarkers.contains(where: { lower.contains($0) }) {
            return false
        }

        return true
    }

    private static func extractTitle(from html: String, fallbackSlug: String) -> String {
        if let ogTitle = extractMetaProperty(name: "og:title", from: html) {
            let cleaned = ogTitle
                .replacingOccurrences(of: " — Grokipedia", with: "")
                .replacingOccurrences(of: " - Grokipedia", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }

        if let titleMatch = html.range(of: #"<title>(.*?)</title>"#, options: .regularExpression) {
            let fragment = String(html[titleMatch])
            let inner = fragment
                .replacingOccurrences(of: "<title>", with: "")
                .replacingOccurrences(of: "</title>", with: "")
                .replacingOccurrences(of: " — Grokipedia", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.isEmpty { return inner }
        }

        return fallbackSlug.replacingOccurrences(of: "_", with: " ")
    }

    private static func extractArticleImage(from html: String) -> URL? {
        if let og = extractMetaProperty(name: "og:image", from: html),
           let url = URL(string: og) {
            return url
        }

        if let schemaImage = extractSchemaOrgImage(from: html),
           let url = URL(string: schemaImage) {
            return url
        }

        if let infobox = extractInfoboxImage(from: html),
           let url = URL(string: infobox) {
            return url
        }

        return nil
    }

    private static func extractSchemaOrgImage(from html: String) -> String? {
        let pattern = #""@type"\s*:\s*"Article"[^}]*"image"\s*:\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }

    private static let skippedInfoboxLabels: Set<String> = [
        "registration required",
        "native client",
        "character limit",
        "current status",
        "area served",
        "former name",
        "former names",
        "rebranded date",
        "rebrand date",
    ]

    private static let infoboxLabelAliases: [String: String] = [
        "owner": "Owned by",
        "founders": "Founded by",
        "parent company": "Parent",
        "key people": "Key people",
        "launch date": "Launched",
        "website": "Website",
        "headquarters": "Headquarters",
        "industry": "Industry",
        "type": "Type",
        "products": "Products",
        "services": "Services",
        "founded": "Founded",
        "country": "Country",
        "acquisition date": "Acquired",
        "acquisition price": "Acquisition price",
        "ceo": "CEO",
    ]

    private static func extractInfoboxFacts(from html: String) -> [KnowledgeFact] {
        let marker = "<!-- Article body"
        guard let markerRange = html.range(of: marker) else { return [] }
        let infoboxHTML = String(html[..<markerRange.lowerBound])

        let pattern = #"<dt[^>]*>(.*?)</dt>\s*<dd[^>]*>(.*?)</dd>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }

        let range = NSRange(infoboxHTML.startIndex..., in: infoboxHTML)
        let matches = regex.matches(in: infoboxHTML, range: range)
        var facts: [KnowledgeFact] = []
        var seenLabels = Set<String>()

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let labelRange = Range(match.range(at: 1), in: infoboxHTML),
                  let valueRange = Range(match.range(at: 2), in: infoboxHTML) else {
                continue
            }

            let rawLabel = stripHTML(String(infoboxHTML[labelRange]))
            let rawValue = normalizeInfoboxValue(stripHTML(String(infoboxHTML[valueRange])))
            guard rawLabel.count >= 2, rawValue.count >= 2 else { continue }

            let normalizedKey = rawLabel.lowercased()
            guard !skippedInfoboxLabels.contains(normalizedKey) else { continue }

            let displayLabel = infoboxLabelAliases[normalizedKey] ?? rawLabel
            let dedupeKey = displayLabel.lowercased()
            guard seenLabels.insert(dedupeKey).inserted else { continue }

            facts.append(KnowledgeFact(label: displayLabel, value: rawValue))
        }

        return facts
    }

    private static func normalizeInfoboxValue(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        if let regex = try? NSRegularExpression(pattern: #"([a-z])([A-Z])"#, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1 $2")
        }

        if text.count > 240 {
            text = String(text.prefix(240)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func extractInfoboxImage(from html: String) -> String? {
        let marker = "<!-- Article body"
        guard let markerRange = html.range(of: marker) else { return nil }
        let prefix = String(html[..<markerRange.lowerBound])

        let pattern = #"https://assets\.grokipedia\.com/wiki/images/[A-Za-z0-9]+\.(?:jpg|jpeg|png|webp)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)),
              let range = Range(match.range, in: prefix) else {
            return nil
        }
        return String(prefix[range])
    }

    private static func extractMetaProperty(name: String, from html: String) -> String? {
        let pattern = #"<meta[^>]+property="\#(name)"[^>]+content="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            let altPattern = #"<meta[^>]+content="([^"]*)"[^>]+property="\#(name)""#
            guard let altRegex = try? NSRegularExpression(pattern: altPattern, options: .caseInsensitive),
                  let altMatch = altRegex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let altRange = Range(altMatch.range(at: 1), in: html) else {
                return nil
            }
            return String(html[altRange])
        }
        return String(html[range])
    }

    private static func extractMetaContent(named name: String, from html: String) -> String? {
        let pattern = #"<meta[^>]+name="\#(name)"[^>]+content="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }

    private static func stripHTML(_ html: String) -> String {
        var text = html
        let entities: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
        ]
        for (entity, value) in entities {
            text = text.replacingOccurrences(of: entity, with: value)
        }

        guard let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let range = NSRange(text.startIndex..., in: text)
        text = tagRegex.stringByReplacingMatches(in: text, range: range, withTemplate: " ")

        while text.contains("  ") {
            text = text.replacingOccurrences(of: "  ", with: " ")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}