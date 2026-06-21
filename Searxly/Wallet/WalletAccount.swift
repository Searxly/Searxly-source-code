//
//  WalletAccount.swift
//  Searxly
//
//  One HD account in the wallet. All accounts come from the same seed, derived at
//  m/44'/60'/0'/0/`index`, so a single 12-word backup restores every account.
//

import Foundation

/// How an account's signing key is sourced.
enum AccountKind: String, Codable {
    case hd          // derived from the wallet's seed at `index` (the normal case)
    case imported    // user-imported raw private key (key stored encrypted, keyed by `index`)
    case watchOnly   // address only, no key — can receive & be viewed, but never signs
    case hardware    // signed on an external device (Ledger); the key never touches this Mac
}

struct WalletAccount: Codable, Identifiable, Equatable {
    let index: Int        // BIP-44 address index (or a synthetic index for imported / watch-only / hardware)
    let address: String
    var label: String
    var kind: AccountKind = .hd
    /// BIP-32 path a hardware account signs at (e.g. "m/44'/60'/0'/0/0"). nil for non-hardware.
    var derivationPath: String? = nil

    var id: Int { index }

    var shortAddress: String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}

extension WalletAccount {
    // Custom Decodable so accounts saved before newer fields (kind / derivationPath) still load.
    enum CodingKeys: String, CodingKey { case index, address, label, kind, derivationPath }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        address = try c.decode(String.self, forKey: .address)
        label = try c.decode(String.self, forKey: .label)
        kind = try c.decodeIfPresent(AccountKind.self, forKey: .kind) ?? .hd
        derivationPath = try c.decodeIfPresent(String.self, forKey: .derivationPath)
    }
}
