//
//  WalletDiscover.swift
//  Searxly
//
//  A small, curated directory of well-known, privacy-respecting dApps the user can open straight
//  into the browser. The list is bundled and static (no tracking, no remote fetch). Opening one
//  just navigates a normal tab — the wallet's existing protections apply (origin-bound approval,
//  phishing guard, optional per-dApp rotating address).
//

import Foundation

struct DiscoverDApp: Identifiable, Equatable {
    let id: String
    let name: String
    let tagline: String
    let url: String
    let category: Category
    /// SF Symbol shown in the monochrome tile.
    let symbol: String
    /// A short note on why it's privacy/safety-aligned (nil = none).
    let privacyNote: String?

    enum Category: String, CaseIterable, Identifiable {
        case swap = "Swap"
        case earn = "Earn"
        case bridge = "Bridge"
        case names = "Names"
        case security = "Security"
        var id: String { rawValue }
    }
}

enum WalletDiscover {
    /// Curated list. Kept intentionally small and reputable to avoid surfacing scams.
    static let dapps: [DiscoverDApp] = [
        DiscoverDApp(id: "uniswap", name: "Uniswap", tagline: "Swap tokens on a leading DEX",
                     url: "https://app.uniswap.org", category: .swap, symbol: "arrow.left.arrow.right",
                     privacyNote: nil),
        DiscoverDApp(id: "cowswap", name: "CoW Swap", tagline: "MEV-protected swaps",
                     url: "https://swap.cow.fi", category: .swap, symbol: "shield.lefthalf.filled",
                     privacyNote: "Routes orders to protect you from front-running (MEV)."),
        DiscoverDApp(id: "aerodrome", name: "Aerodrome", tagline: "Base-native DEX & liquidity",
                     url: "https://aerodrome.finance", category: .swap, symbol: "point.3.connected.trianglepath.dotted",
                     privacyNote: nil),
        DiscoverDApp(id: "aave", name: "Aave", tagline: "Lend & borrow",
                     url: "https://app.aave.com", category: .earn, symbol: "banknote",
                     privacyNote: nil),
        DiscoverDApp(id: "lido", name: "Lido", tagline: "Stake ETH, keep it liquid",
                     url: "https://stake.lido.fi", category: .earn, symbol: "square.stack.3d.up",
                     privacyNote: nil),
        DiscoverDApp(id: "basebridge", name: "Base Bridge", tagline: "Move funds to & from Base",
                     url: "https://bridge.base.org", category: .bridge, symbol: "arrow.left.and.right",
                     privacyNote: nil),
        DiscoverDApp(id: "basenames", name: "Basenames", tagline: "Claim a .base name",
                     url: "https://www.base.org/names", category: .names, symbol: "person.text.rectangle",
                     privacyNote: nil),
        DiscoverDApp(id: "ens", name: "ENS", tagline: "Name your wallet (.eth)",
                     url: "https://app.ens.domains", category: .names, symbol: "at",
                     privacyNote: nil),
        DiscoverDApp(id: "revoke", name: "Revoke.cash", tagline: "Review & revoke token approvals",
                     url: "https://revoke.cash", category: .security, symbol: "checkmark.shield",
                     privacyNote: "See exactly what can move your tokens, and cut off risky approvals."),
    ]
}
