//
//  WalletChain.swift
//  Searxly
//
//  Multi-chain support. Every supported network is an EVM chain, so the entire crypto stack
//  (BIP-44 m/44'/60', secp256k1, EIP-1559, Keccak, RLP) is identical across them — only the
//  chainId, RPC endpoints, block explorer, native gas token, and price-feed slugs differ.
//  The same HD address is used on every chain (standard EVM behavior).
//

import Foundation

struct WalletChain: Identifiable, Codable, Equatable, Hashable {
    let id: Int                    // EIP-155 chain id
    let name: String               // "Base"
    let shortName: String          // "Base"
    let nativeSymbol: String       // gas-token symbol: "ETH" / "POL"
    let nativeName: String         // "Ethereum" / "Polygon"
    let nativeDecimals: Int        // always 18 for these chains
    let rpcURLs: [String]          // first is primary; rest are public failover
    let explorerBaseURL: String    // no trailing slash
    let explorerName: String       // "Basescan"
    let coinGeckoNativeID: String  // CoinGecko id for the native coin's USD price
    let geckoTerminalSlug: String  // GeckoTerminal network slug for on-chain token OHLCV (charts)
    let dexScreenerSlug: String    // DexScreener chainId string (pool lookup for charts)
    let accentHex: String          // brand color for the chain chip

    var chainIdHex: String { "0x" + String(id, radix: 16) }
    var caip2: String { "eip155:\(id)" }

    func explorerTxURL(_ hash: String) -> String { "\(explorerBaseURL)/tx/\(hash)" }
    func explorerAddressURL(_ address: String) -> String { "\(explorerBaseURL)/address/\(address)" }
    func explorerTokenURL(_ contract: String) -> String { "\(explorerBaseURL)/token/\(contract)" }
}

extension WalletChain {

    // MARK: - Supported chains

    static let base = WalletChain(
        id: 8453, name: "Base", shortName: "Base",
        nativeSymbol: "ETH", nativeName: "Ethereum", nativeDecimals: 18,
        rpcURLs: ["https://mainnet.base.org",
                  "https://base-rpc.publicnode.com",
                  "https://base.drpc.org"],
        explorerBaseURL: "https://basescan.org", explorerName: "Basescan",
        coinGeckoNativeID: "ethereum", geckoTerminalSlug: "base", dexScreenerSlug: "base", accentHex: "0052FF")

    static let ethereum = WalletChain(
        id: 1, name: "Ethereum", shortName: "Ethereum",
        nativeSymbol: "ETH", nativeName: "Ethereum", nativeDecimals: 18,
        rpcURLs: ["https://eth.llamarpc.com",
                  "https://ethereum-rpc.publicnode.com",
                  "https://eth.drpc.org"],
        explorerBaseURL: "https://etherscan.io", explorerName: "Etherscan",
        coinGeckoNativeID: "ethereum", geckoTerminalSlug: "eth", dexScreenerSlug: "ethereum", accentHex: "627EEA")

    static let optimism = WalletChain(
        id: 10, name: "Optimism", shortName: "OP",
        nativeSymbol: "ETH", nativeName: "Ethereum", nativeDecimals: 18,
        rpcURLs: ["https://mainnet.optimism.io",
                  "https://optimism-rpc.publicnode.com",
                  "https://optimism.drpc.org"],
        explorerBaseURL: "https://optimistic.etherscan.io", explorerName: "Etherscan",
        coinGeckoNativeID: "ethereum", geckoTerminalSlug: "optimism", dexScreenerSlug: "optimism", accentHex: "FF0420")

    static let arbitrum = WalletChain(
        id: 42161, name: "Arbitrum One", shortName: "Arbitrum",
        nativeSymbol: "ETH", nativeName: "Ethereum", nativeDecimals: 18,
        rpcURLs: ["https://arb1.arbitrum.io/rpc",
                  "https://arbitrum-one-rpc.publicnode.com",
                  "https://arbitrum.drpc.org"],
        explorerBaseURL: "https://arbiscan.io", explorerName: "Arbiscan",
        coinGeckoNativeID: "ethereum", geckoTerminalSlug: "arbitrum", dexScreenerSlug: "arbitrum", accentHex: "2D374B")

    static let polygon = WalletChain(
        id: 137, name: "Polygon", shortName: "Polygon",
        nativeSymbol: "POL", nativeName: "Polygon", nativeDecimals: 18,
        rpcURLs: ["https://polygon-rpc.com",
                  "https://polygon-bor-rpc.publicnode.com",
                  "https://polygon.drpc.org"],
        explorerBaseURL: "https://polygonscan.com", explorerName: "PolygonScan",
        // POL (the gas token since the MATIC→POL migration). CoinGecko's "matic-network" id now
        // returns empty; "polygon-ecosystem-token" is the live POL price.
        coinGeckoNativeID: "polygon-ecosystem-token", geckoTerminalSlug: "polygon_pos", dexScreenerSlug: "polygon", accentHex: "8247E5")

    /// All supported chains, in display order. Base leads — it's Searxly's home chain.
    static let all: [WalletChain] = [.base, .ethereum, .optimism, .arbitrum, .polygon]

    static func by(id: Int) -> WalletChain? { all.first { $0.id == id } }

    static func by(hexId: String) -> WalletChain? {
        let clean = hexId.hasPrefix("0x") ? String(hexId.dropFirst(2)) : hexId
        guard let v = Int(clean, radix: 16) else { return nil }
        return by(id: v)
    }

    /// The default chain a new/migrated wallet starts on.
    static let defaultChain = WalletChain.base
}
