//
//  WalletPhishingGuard.swift
//  Searxly
//
//  A lightweight, always-on, fully-local check that flags a dApp origin before the user connects
//  or signs. It combines a small bundled blocklist of known-scam hosts with a punycode/IDN
//  homograph heuristic (the classic "imitate a real domain" trick). It never phones home, so it
//  costs no privacy; the bundled list is a conservative starter that can be extended (or backed by
//  an opt-in external list) later.
//

import Foundation

enum WalletPhishingGuard {

    enum Risk: Equatable {
        case ok
        case flagged(String)   // human-readable reason
    }

    /// Known scam / impersonation hosts. Matches the exact host or any subdomain of it.
    /// Intentionally small to avoid false positives — extend as new scams are confirmed.
    private static let blockedHosts: Set<String> = [
        "claim-airdrop.com", "wallet-connect.cc", "walletconnect-app.com",
        "uniswap-airdrop.com", "metamask-wallet.io", "phantom-wallet.app",
        "base-airdrop.com", "searxly-airdrop.com", "searxly-claim.com",
        "free-eth-claim.com", "token-unlock.app",
    ]

    /// `origin` is "scheme://host[:port]" (the real WebKit security origin, never page-supplied).
    static func check(origin: String) -> Risk {
        guard let host = hostFromOrigin(origin)?.lowercased() else { return .ok }

        // 1. Known-scam blocklist (exact host or any subdomain of it).
        for bad in blockedHosts where host == bad || host.hasSuffix("." + bad) {
            return .flagged("This site is on a known-scam blocklist. Do not connect or sign.")
        }

        // 2. Punycode / IDN homograph — a domain that can visually imitate a real one.
        let labels = host.split(separator: ".")
        if labels.contains(where: { $0.hasPrefix("xn--") }) {
            return .flagged("This site uses a non-standard (punycode) domain that can imitate a real one. Check the address carefully.")
        }

        return .ok
    }

    private static func hostFromOrigin(_ origin: String) -> String? {
        var s = origin
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }   // strip port
        return s.isEmpty ? nil : s
    }
}
