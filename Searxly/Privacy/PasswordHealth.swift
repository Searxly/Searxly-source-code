//
//  PasswordHealth.swift
//  Searxly
//
//  Offline password-health analysis for the vault. NOTHING leaves the device — there is no API call,
//  no k-anonymity range request, nothing. We flag the three things that actually cause account
//  takeovers, all computed locally:
//
//   1. Reused   — the same password protects more than one account (the #1 real-world risk).
//   2. Common   — the password (or its un-numbered base) is in a bundled list of the most-breached
//                 passwords. Expand `commonPasswords` from a SecLists / rockyou top-N resource anytime.
//   3. Weak     — a lightweight zxcvbn-style strength estimate falls in the bottom buckets.
//
//  Pure Foundation, no app dependencies, so it stays unit-testable in isolation.
//

import Foundation

enum PasswordHealth {

    enum Strength: Int, Comparable, Codable {
        case veryWeak = 0, weak, fair, strong, veryStrong
        static func < (l: Strength, r: Strength) -> Bool { l.rawValue < r.rawValue }
        var label: String {
            switch self {
            case .veryWeak:   return "Very weak"
            case .weak:       return "Weak"
            case .fair:       return "Fair"
            case .strong:     return "Strong"
            case .veryStrong: return "Very strong"
            }
        }
    }

    struct Report: Equatable, Codable {
        var strength: Strength
        var reused: Bool      // the same password is used by another entry
        var common: Bool      // appears in the bundled known-breached list
        var weak: Bool        // strength is .weak or worse

        /// True when this password should be drawn to the user's attention.
        var atRisk: Bool { reused || common || weak }
    }

    /// Analyzes a set of `(id, password)` pairs and returns one report per id. Reuse is detected
    /// across the whole set, so callers pass every entry at once.
    static func analyze(_ items: [(id: UUID, password: String)]) -> [UUID: Report] {
        var counts: [String: Int] = [:]
        for item in items where !item.password.isEmpty { counts[item.password, default: 0] += 1 }

        var reports: [UUID: Report] = [:]
        for item in items {
            let s = strength(of: item.password)
            reports[item.id] = Report(
                strength: s,
                reused: (counts[item.password] ?? 0) > 1,
                common: isCommon(item.password),
                weak: s <= .weak
            )
        }
        return reports
    }

    // MARK: - Strength estimate (heuristic — no dependency)

    /// Approximate strength from character-pool entropy, with penalties for the low-effort patterns
    /// real attackers try first (dictionary words, runs like `aaaa`, sequences like `1234`).
    static func strength(of password: String) -> Strength {
        let n = password.count
        guard n > 0 else { return .veryWeak }

        var pool = 0
        if password.contains(where: { $0.isLowercase }) { pool += 26 }
        if password.contains(where: { $0.isUppercase }) { pool += 26 }
        if password.contains(where: { $0.isNumber }) { pool += 10 }
        if password.contains(where: { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }) { pool += 33 }

        var score = Double(n) * log2(Double(max(pool, 1)))   // rough entropy in bits
        if isCommon(password) { score -= 40 }
        if hasLongRun(password) { score -= 12 }
        if isSequential(password) { score -= 12 }
        if password.allSatisfy({ $0.isNumber }) { score -= 10 }
        score = max(0, score)

        switch score {
        case ..<28: return .veryWeak
        case ..<40: return .weak
        case ..<60: return .fair
        case ..<80: return .strong
        default:    return .veryStrong
        }
    }

    /// Whether the password (or its un-numbered base, e.g. `password2024` → `password`) is a known
    /// common/breached password.
    static func isCommon(_ password: String) -> Bool {
        guard !password.isEmpty else { return false }
        let lower = password.lowercased()
        if commonPasswords.contains(lower) { return true }
        let base = lower.replacingOccurrences(of: "[0-9!@#$._-]+$", with: "", options: .regularExpression)
        return base.count >= 4 && commonPasswords.contains(base)
    }

    // MARK: - Pattern helpers

    /// 4+ identical characters in a row (aaaa, 1111).
    private static func hasLongRun(_ s: String) -> Bool {
        let chars = Array(s)
        guard chars.count >= 4 else { return false }
        var run = 1
        for i in 1..<chars.count {
            run = (chars[i] == chars[i - 1]) ? run + 1 : 1
            if run >= 4 { return true }
        }
        return false
    }

    /// 4+ consecutive ascending or descending code points (abcd, 4321).
    private static func isSequential(_ s: String) -> Bool {
        let scalars = s.lowercased().unicodeScalars.map { Int($0.value) }
        guard scalars.count >= 4 else { return false }
        var asc = 1, desc = 1
        for i in 1..<scalars.count {
            asc  = (scalars[i] == scalars[i - 1] + 1) ? asc + 1 : 1
            desc = (scalars[i] == scalars[i - 1] - 1) ? desc + 1 : 1
            if asc >= 4 || desc >= 4 { return true }
        }
        return false
    }

    // MARK: - Bundled known-breached passwords (lowercased)
    //
    // A starter set of the most common passwords from public breach corpora. Swap in a larger
    // bundled file (e.g. SecLists rockyou top-10k) by loading it into this Set on first use.
    static let commonPasswords: Set<String> = [
        "123456", "123456789", "12345678", "1234567", "12345", "1234567890", "1234", "111111",
        "123123", "000000", "654321", "121212", "112233", "159753", "147258369", "987654321",
        "password", "password1", "passw0rd", "p@ssword", "p@ssw0rd", "pass", "letmein", "welcome",
        "admin", "administrator", "root", "guest", "user", "test", "login", "changeme", "default",
        "qwerty", "qwertyuiop", "qwerty123", "azerty", "asdfgh", "asdfghjkl", "zxcvbn", "qazwsx",
        "1q2w3e4r", "1qaz2wsx", "qwe123", "abc123", "a1b2c3", "iloveyou", "monkey", "dragon",
        "sunshine", "princess", "football", "baseball", "superman", "batman", "master", "shadow",
        "michael", "jennifer", "jordan", "harley", "ranger", "hunter", "buster", "thomas", "robert",
        "soccer", "hockey", "killer", "george", "charlie", "andrew", "michelle", "love", "secret",
        "summer", "winter", "ginger", "freedom", "whatever", "trustno1", "starwars", "pokemon",
        "computer", "internet", "samsung", "google", "apple", "amazon", "facebook", "yahoo",
        "hello", "hello123", "test123", "admin123", "root123", "welcome1", "welcome123", "abcdef",
        "abcd1234", "qwerty1", "password123", "11111111", "00000000", "asdf", "asdf1234", "zaq12wsx",
        "money", "freedom1", "ninja", "mustang", "access", "flower", "matrix", "cheese", "banana",
        "orange", "purple", "yellow", "diamond", "tigger", "chocolate", "nicole", "daniel", "ashley",
        "bailey", "passion", "maggie", "jessica", "amanda", "loveme", "fuckyou", "asshole", "mygod",
        "qwertyui", "1234qwer", "q1w2e3r4", "abcdefg", "987654", "696969", "5201314", "woaini1314"
    ]
}
