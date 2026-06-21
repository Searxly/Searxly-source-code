//
//  WalletToken.swift
//  Searxly
//

import Foundation
import SwiftUI

struct WalletToken: Identifiable, Equatable, Codable {
    let id: String          // stable identifier (symbol for built-ins, contract address for custom)
    let symbol: String
    let name: String
    let contractAddress: String?    // nil for native ETH
    let decimals: Int
    let isCustom: Bool              // user-added via "Add Token"
    var chainId: Int = WalletChain.base.id   // which EVM chain this token lives on

    var balance: Decimal = 0
    var priceUSD: Double = 0
    var change24h: Double = 0
    /// A watch-only / read-only token row (currently unused for tokens; reserved).
    var isNative: Bool { contractAddress == nil }

    var usdValue: Double {
        (balance as NSDecimalNumber).doubleValue * priceUSD
    }

    var formattedBalance: String {
        let d = (balance as NSDecimalNumber).doubleValue
        if d == 0 { return "0" }
        if d < 0.0001 { return String(format: "%.8f", d) }
        if d < 1      { return String(format: "%.4f", d) }
        return String(format: "%.4f", d)
    }

    var formattedUSD: String {
        let v = usdValue
        if v == 0    { return "$0.00" }
        if v < 0.01  { return String(format: "$%.4f", v) }
        return String(format: "$%.2f", v)
    }

    var canRemove: Bool { isCustom }

    // MARK: - Built-in tokens

    static var eth: WalletToken {
        WalletToken(id: "ETH", symbol: "ETH", name: "Ethereum",
                    contractAddress: nil, decimals: 18, isCustom: false)
    }

    /// The native gas token for a chain (ETH on Base/OP/Arbitrum/Ethereum, POL on Polygon).
    static func native(for chain: WalletChain) -> WalletToken {
        WalletToken(id: chain.nativeSymbol, symbol: chain.nativeSymbol, name: chain.nativeName,
                    contractAddress: nil, decimals: chain.nativeDecimals, isCustom: false,
                    chainId: chain.id)
    }

    static var searxly: WalletToken {
        WalletToken(id: "SEARXLY", symbol: WalletConfig.searxlyTokenSymbol,
                    name: WalletConfig.searxlyTokenName,
                    contractAddress: WalletConfig.searxlyTokenAddress,
                    decimals: WalletConfig.searxlyTokenDecimals, isCustom: false,
                    chainId: WalletChain.base.id)
    }

    // MARK: - Icon color (used by TokenIconView)

    var iconColor: Color {
        switch symbol.uppercased() {
        case "ETH", "WETH": return Color(red: 0.380, green: 0.443, blue: 0.890)   // Ethereum periwinkle
        case "SEARXLY":     return Color(white: 0.20)   // monochrome — Searxly is black & white
        case "USDC", "USDBC": return Color(red: 0.153, green: 0.459, blue: 0.792) // USDC brand blue #2775CA
        case "USDT":        return Color(red: 0.149, green: 0.682, blue: 0.557)   // Tether teal #26A17B
        case "DAI":         return Color(red: 0.961, green: 0.694, blue: 0.184)   // DAI gold #F5AC2F
        case "WBTC", "CBBTC", "BTC": return Color(red: 0.969, green: 0.576, blue: 0.118) // Bitcoin orange
        default:
            // Deterministic color from contract address / symbol hash
            let hash = (contractAddress ?? symbol).utf8.reduce(UInt32(0)) { ($0 &* 31) &+ UInt32($1) }
            return Color(hue: Double(hash % 360) / 360.0, saturation: 0.68, brightness: 0.82)
        }
    }

    /// True for tokens whose price is ~$1 (used as a price fallback when no feed is available).
    var isStablecoin: Bool {
        ["USDC", "USDBC", "USDT", "DAI", "USDS", "PYUSD"].contains(symbol.uppercased())
    }
}

extension WalletToken {
    // Custom Decodable so tokens saved before multi-chain (no `chainId` key) still load —
    // they default to Base. Keeps the synthesized memberwise initializer available.
    enum CodingKeys: String, CodingKey {
        case id, symbol, name, contractAddress, decimals, isCustom, chainId, balance, priceUSD, change24h
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        symbol = try c.decode(String.self, forKey: .symbol)
        name = try c.decode(String.self, forKey: .name)
        contractAddress = try c.decodeIfPresent(String.self, forKey: .contractAddress)
        decimals = try c.decode(Int.self, forKey: .decimals)
        isCustom = try c.decode(Bool.self, forKey: .isCustom)
        chainId = try c.decodeIfPresent(Int.self, forKey: .chainId) ?? WalletChain.base.id
        balance = try c.decodeIfPresent(Decimal.self, forKey: .balance) ?? 0
        priceUSD = try c.decodeIfPresent(Double.self, forKey: .priceUSD) ?? 0
        change24h = try c.decodeIfPresent(Double.self, forKey: .change24h) ?? 0
    }
}
