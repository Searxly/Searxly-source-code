//
//  GrokipediaSlugCatalog.swift
//  Searxly
//
//  Verified Grokipedia page slugs (offline map). Slugs confirmed via grokipedia.com/page/{slug}.
//  Wikipedia-style titles — e.g. Tesla → Tesla_Inc, not "Tesla".
//

import Foundation

enum GrokipediaSlugCatalog {

    /// Maps normalized lookup keys to verified Grokipedia slugs.
    private static let slugByKey: [String: String] = [
        // Musk ecosystem
        "xai": "XAI_(company)", "x.ai": "XAI_(company)", "x ai": "XAI_(company)", "grok": "XAI_(company)",
        "tesla": "Tesla_Inc", "tesla motors": "Tesla_Inc", "tesla official": "Tesla_Inc",
        "spacex": "SpaceX", "space x": "SpaceX",
        "neuralink": "Neuralink", "neural link": "Neuralink",
        "starlink": "Starlink", "star link": "Starlink",
        "elon musk": "Elon_Musk", "elon": "Elon_Musk", "musk": "Elon_Musk",
        "x": "Twitter", "x.com": "Twitter", "twitter": "Twitter", "twitter x": "Twitter",
        "formerly twitter": "Twitter", "x official": "Twitter", "twitter official": "Twitter",

        // Major tech
        "youtube": "YouTube", "yt": "YouTube",
        "google": "Google", "gmail": "Google", "google maps": "Google", "google search": "Google",
        "apple": "Apple_Inc", "apple official": "Apple_Inc", "apple.com": "Apple_Inc",
        "microsoft": "Microsoft", "ms": "Microsoft",
        "amazon": "Amazon", "amazon shopping": "Amazon",
        "netflix": "Netflix",
        "github": "GitHub", "git hub": "GitHub",
        "openai": "OpenAI", "open ai": "OpenAI",
        "chatgpt": "ChatGPT", "chat gpt": "ChatGPT", "openai chat": "ChatGPT",
        "anthropic": "Anthropic", "claude": "Anthropic",
        "nvidia": "Nvidia",
        "meta": "Meta_Platforms", "meta platforms": "Meta_Platforms",
        "intel": "Intel", "amd": "AMD",
        "adobe": "Adobe_Inc",
        "zoom": "Zoom_Video_Communications", "zoom video": "Zoom_Video_Communications",
        "slack": "Slack_(software)",
        "salesforce": "Salesforce",
        "airbnb": "Airbnb",
        "uber": "Uber",
        "lyft": "Lyft",
        "paypal": "PayPal",
        "shopify": "Shopify",
        "arm": "Arm_(company)", "arm holdings": "Arm_(company)",
        "qualcomm": "Qualcomm",
        "ibm": "IBM",
        "oracle": "Oracle_Corporation",
        "sap": "SAP",
        "palantir": "Palantir_Technologies",

        // Social & platforms
        "reddit": "Reddit",
        "discord": "Discord",
        "spotify": "Spotify",
        "twitch": "Twitch",
        "facebook": "Facebook", "fb": "Facebook",
        "instagram": "Instagram", "ig": "Instagram",
        "linkedin": "LinkedIn", "linked in": "LinkedIn",
        "tiktok": "TikTok",
        "whatsapp": "WhatsApp", "wa": "WhatsApp",
        "snapchat": "Snapchat",
        "pinterest": "Pinterest",
        "tumblr": "Tumblr",
        "mastodon": "Mastodon_(social_network)",

        // Gaming & entertainment
        "roblox": "Roblox",
        "minecraft": "Minecraft",
        "epic games": "Epic_Games", "epic": "Epic_Games",
        "fortnite": "Fortnite",
        "nintendo": "Nintendo",
        "sony": "Sony", "sony interactive": "Sony_Interactive_Entertainment",
        "playstation": "PlayStation", "ps5": "PlayStation_5", "ps4": "PlayStation_4",
        "xbox": "Xbox", "xbox series x": "Xbox_Series_X",
        "pokemon": "Pokemon", "pokémon": "Pokemon",
        "league of legends": "League_of_Legends", "lol": "League_of_Legends",
        "valorant": "Valorant",
        "overwatch": "Overwatch_(video_game)",
        "call of duty": "Call_of_Duty",
        "gta": "Grand_Theft_Auto", "grand theft auto": "Grand_Theft_Auto",
        "rockstar games": "Rockstar_Games", "rockstar": "Rockstar_Games",
        "ubisoft": "Ubisoft",
        "ea": "Electronic_Arts", "electronic arts": "Electronic_Arts",
        "activision": "Activision",
        "blizzard": "Blizzard_Entertainment", "blizzard entertainment": "Blizzard_Entertainment",
        "riot games": "Riot_Games", "riot": "Riot_Games",
        "steam": "Steam", "steam store": "Steam",
        "roblox corporation": "Roblox",
        "mojang": "Mojang_Studios",
        "bethesda": "Bethesda_Softworks",

        // Entertainment & media
        "disney": "The_Walt_Disney_Company", "walt disney": "The_Walt_Disney_Company",
        "warner bros": "Warner_Bros", "warner brothers": "Warner_Bros",
        "universal": "Universal_Pictures",
        "hbo": "HBO",
        "hulu": "Hulu",
        "paramount": "Paramount_Pictures",
        "youtube music": "YouTube_Music",
        "apple music": "Apple_Music",
        "apple tv": "Apple_TV",

        // Dev & SaaS
        "cloudflare": "Cloudflare",
        "duckduckgo": "DuckDuckGo", "ddg": "DuckDuckGo", "duck duck go": "DuckDuckGo",
        "figma": "Figma",
        "stackoverflow": "Stack_Overflow", "stack overflow": "Stack_Overflow",
        "dropbox": "Dropbox",
        "notion": "Notion",
        "vercel": "Vercel",
        "huggingface": "Hugging_Face", "hugging face": "Hugging_Face", "hf": "Hugging_Face",
        "perplexity": "Perplexity", "perplexity ai": "Perplexity",
        "midjourney": "Midjourney",
        "cursor": "Cursor", "cursor ai": "Cursor",
        "linear": "Linear",
        "medium": "Medium_(website)",
        "stripe": "Stripe_(company)",
        "twilio": "Twilio",
        "docker": "Docker_(software)",
        "kubernetes": "Kubernetes",
        "linux": "Linux",
        "python": "Python_(programming_language)",
        "swift": "Swift_(programming_language)",
        "rust": "Rust_(programming_language)",
        "typescript": "TypeScript",
        "javascript": "JavaScript",
        "git": "Git",
        "postgresql": "PostgreSQL", "postgres": "PostgreSQL",
        "mongodb": "MongoDB",
        "redis": "Redis",
        "nginx": "Nginx",

        // Notable people (tech)
        "sam altman": "Sam_Altman",
        "mark zuckerberg": "Mark_Zuckerberg", "zuckerberg": "Mark_Zuckerberg",
        "jeff bezos": "Jeff_Bezos", "bezos": "Jeff_Bezos",
        "bill gates": "Bill_Gates", "gates": "Bill_Gates",
        "steve jobs": "Steve_Jobs", "jobs": "Steve_Jobs",
        "tim cook": "Tim_Cook",
        "sundar pichai": "Sundar_Pichai", "pichai": "Sundar_Pichai",
        "satya nadella": "Satya_Nadella", "nadella": "Satya_Nadella",
        "linus torvalds": "Linus_Torvalds", "torvalds": "Linus_Torvalds",
        "jensen huang": "Jensen_Huang", "jensen": "Jensen_Huang",
        "larry page": "Larry_Page",
        "sergey brin": "Sergey_Brin",

        // News & reference
        "wikipedia": "Wikipedia", "wiki": "Wikipedia",
        "grokipedia": "Grokipedia", "grok ipedia": "Grokipedia",
        "bbc": "BBC", "bbc news": "BBC",
        "reuters": "Reuters",
        "new york times": "The_New_York_Times", "nytimes": "The_New_York_Times",
        "the guardian": "The_Guardian",
        "cnn": "CNN",
    ]

    // MARK: - Public API

    /// Returns true when the subject has an explicit, curated slug entry (not an inferred one).
    /// Used by KnowledgeQueryDetector to prevent brand names from being misclassified as dictionary words.
    static func hasExplicitSlug(for subject: String) -> Bool {
        let key = subject.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return slugByKey[key] != nil
    }

    static func slug(for entity: OfficialEntityDatabase.OfficialEntity?) -> String? {
        guard let entity else { return nil }
        if let explicit = entity.grokipediaSlug, !explicit.isEmpty {
            return explicit
        }
        if let mapped = slugByKey[entity.canonicalKey] {
            return mapped
        }
        for alias in entity.aliases {
            let norm = alias.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let mapped = slugByKey[norm] {
                return mapped
            }
        }
        return nil
    }

    static func slug(forSubject subject: String) -> String? {
        let key = subject.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let mapped = slugByKey[key] { return mapped }
        if let entity = OfficialEntityDatabase.entity(for: key) {
            return slug(for: entity)
        }
        return inferredSlug(fromSubject: subject)
    }

    /// Wikipedia-style title slug used by Grokipedia for most biographies (e.g. "bernard arnault" → "Bernard_Arnault").
    static func inferredSlug(fromSubject subject: String) -> String? {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let words = trimmed
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard words.count >= 1, words.count <= 5 else { return nil }

        let skipTokens = Set(["the", "of", "and", "for", "inc", "corp", "ltd", "llc", "official", "company"])
        guard words.allSatisfy({ word in
            word.rangeOfCharacter(from: .letters) != nil && !skipTokens.contains(word.lowercased())
        }) else { return nil }

        return words.map { word in
            word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: "_")
    }

    static func pageURL(for slug: String) -> String {
        // Grokipedia canonical URLs use literal parentheses (e.g. XAI_(company)).
        // Do not pre-encode parens — addingPercentEncoding would double-encode % and 404.
        "https://grokipedia.com/page/\(slug)"
    }

    static func pageURL(forSubject subject: String) -> String? {
        guard let slug = slug(forSubject: subject) else { return nil }
        return pageURL(for: slug)
    }
}

private extension CharacterSet {
    static let grokipediaSlugAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.insert(charactersIn: "_-.")
        return set
    }()
}