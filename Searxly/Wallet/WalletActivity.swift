//
//  WalletActivity.swift
//  Searxly
//
//  Transaction activity feed. Always-on local record of outgoing transactions (private,
//  RPC-only) with live pending→confirmed/failed tracking. Optional full incoming+outgoing
//  history via the Basescan/Etherscan API is layered on top only when the user enables it.
//

import Foundation
import Observation

/// Everything needed to rebuild a broadcast transaction for replace-by-fee (speed-up / cancel).
struct PendingTxInfo: Codable, Equatable {
    let nonce: UInt64
    let to: String                 // recipient / contract ("0x…")
    let valueHex: String           // "0x…" wei (empty/0x0 for token transfers)
    let dataHex: String            // "0x…" calldata ("0x" for plain sends)
    let gasLimit: UInt64
    let maxFeePerGas: UInt64
    let maxPriorityFeePerGas: UInt64
    /// HD account index that SENT this tx — replace-by-fee MUST sign with the same account (the nonce
    /// belongs to it). -1 means "unknown" (an entry saved before this field existed).
    var accountIndex: Int = -1

    enum CodingKeys: String, CodingKey { case nonce, to, valueHex, dataHex, gasLimit, maxFeePerGas, maxPriorityFeePerGas, accountIndex }
    init(nonce: UInt64, to: String, valueHex: String, dataHex: String, gasLimit: UInt64,
         maxFeePerGas: UInt64, maxPriorityFeePerGas: UInt64, accountIndex: Int) {
        self.nonce = nonce; self.to = to; self.valueHex = valueHex; self.dataHex = dataHex
        self.gasLimit = gasLimit; self.maxFeePerGas = maxFeePerGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas; self.accountIndex = accountIndex
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        nonce = try c.decode(UInt64.self, forKey: .nonce)
        to = try c.decode(String.self, forKey: .to)
        valueHex = try c.decode(String.self, forKey: .valueHex)
        dataHex = try c.decode(String.self, forKey: .dataHex)
        gasLimit = try c.decode(UInt64.self, forKey: .gasLimit)
        maxFeePerGas = try c.decode(UInt64.self, forKey: .maxFeePerGas)
        maxPriorityFeePerGas = try c.decode(UInt64.self, forKey: .maxPriorityFeePerGas)
        accountIndex = try c.decodeIfPresent(Int.self, forKey: .accountIndex) ?? -1
    }
}

struct WalletActivityEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case send, receive, swap, approve, contract }
    enum Status: String, Codable { case pending, confirmed, failed, replaced }

    var id: String { hash.isEmpty ? "\(chainId):\(timestamp.timeIntervalSince1970):\(amount)" : hash }
    let hash: String
    var kind: Kind
    var tokenSymbol: String
    var amount: String            // display amount, e.g. "1.5"
    var counterparty: String      // to (send) or from (receive)
    var timestamp: Date
    var status: Status
    var fromExplorer: Bool = false // true if sourced from the explorer history fetch
    var chainId: Int = WalletChain.base.id   // which chain this tx is on (per-chain feed)
    var pending: PendingTxInfo? = nil        // fields to rebuild for speed-up / cancel (outgoing only)

    /// Whether this entry can be sped up or cancelled (a still-pending outgoing tx we have the fields for).
    var canReplace: Bool { status == .pending && pending != nil && !hash.isEmpty }
}

extension WalletActivityEntry {
    // Custom Decodable so entries saved before newer fields (chainId/fromExplorer/pending) still load.
    enum CodingKeys: String, CodingKey { case hash, kind, tokenSymbol, amount, counterparty, timestamp, status, fromExplorer, chainId, pending }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        hash = try c.decode(String.self, forKey: .hash)
        kind = try c.decode(Kind.self, forKey: .kind)
        tokenSymbol = try c.decode(String.self, forKey: .tokenSymbol)
        amount = try c.decode(String.self, forKey: .amount)
        counterparty = try c.decode(String.self, forKey: .counterparty)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        status = try c.decode(Status.self, forKey: .status)
        fromExplorer = try c.decodeIfPresent(Bool.self, forKey: .fromExplorer) ?? false
        chainId = try c.decodeIfPresent(Int.self, forKey: .chainId) ?? WalletChain.base.id
        pending = try c.decodeIfPresent(PendingTxInfo.self, forKey: .pending)
    }
}

@MainActor
@Observable
final class WalletActivityStore {
    static let shared = WalletActivityStore()

    private(set) var entries: [WalletActivityEntry] = []
    private let key = WalletConfig.Keys.localActivity

    private init() { load() }

    // MARK: - Local record (always on)

    func record(_ entry: WalletActivityEntry) {
        var e = entry
        e.chainId = WalletManager.shared.activeChain.id   // local records always happen on the active chain
        if !e.hash.isEmpty { entries.removeAll { !$0.hash.isEmpty && $0.hash.lowercased() == e.hash.lowercased() } }
        entries.insert(e, at: 0)
        persistLocalOnly()
    }

    /// Entries for a specific chain (the Activity tab shows only the active chain's transactions).
    func entries(forChain chainId: Int) -> [WalletActivityEntry] {
        entries.filter { $0.chainId == chainId }
    }

    func updateStatus(hash: String, status: WalletActivityEntry.Status) {
        guard let idx = entries.firstIndex(where: { $0.hash.lowercased() == hash.lowercased() }) else { return }
        entries[idx].status = status
        persistLocalOnly()
    }

    /// Marks a tx as replaced by a speed-up/cancel and clears its pending fields (so it can't be
    /// replaced again from the old hash).
    func markReplaced(hash: String) {
        guard let idx = entries.firstIndex(where: { $0.hash.lowercased() == hash.lowercased() }) else { return }
        entries[idx].status = .replaced
        entries[idx].pending = nil
        persistLocalOnly()
    }

    func clear() {
        entries.removeAll()
        WalletKeychain.deleteActivity()
        UserDefaults.standard.removeObject(forKey: key)
    }

    // MARK: - Pending tracking (RPC, always on)

    /// Polls a freshly broadcast transaction until it's mined, updating its status and posting a
    /// macOS notification on the final outcome.
    func trackPending(hash: String, rpc: String) {
        Task {
            for _ in 0..<40 {                       // ~2 min at 3s
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                let status = await WalletNetwork.transactionReceipt(hash: hash, rpc: rpc)
                switch status {
                case .success: updateStatus(hash: hash, status: .confirmed); notify(hash: hash, ok: true);  return
                case .failed:  updateStatus(hash: hash, status: .failed);    notify(hash: hash, ok: false); return
                case .pending: continue
                }
            }
        }
    }

    private func notify(hash: String, ok: Bool) {
        let entry = entries.first { $0.hash.lowercased() == hash.lowercased() }
        let chainName = (entry.flatMap { WalletChain.by(id: $0.chainId) } ?? WalletManager.shared.activeChain).name
        let detail = entry.map { "\($0.kind == .receive ? "+" : "-")\($0.amount) \($0.tokenSymbol)" } ?? "Your transaction"
        NotificationManager.shared.show(
            title: ok ? "Transaction confirmed" : "Transaction failed",
            body: ok ? "\(detail) confirmed on \(chainName)." : "\(detail) failed — no funds moved.",
            source: "Searxly Wallet",
            iconSystemName: ok ? "checkmark.seal.fill" : "xmark.octagon.fill")
    }

    // MARK: - Full history (Basescan — only when the toggle is on)

    func refreshFullHistory(address: String) async {
        guard WalletFeatures.fullHistory else { return }
        let chain = WalletManager.shared.activeChain
        var remote = await WalletNetwork.fetchHistory(address: address, chainId: chain.id, nativeSymbol: chain.nativeSymbol)
        guard !remote.isEmpty else { return }
        for i in remote.indices { remote[i].chainId = chain.id }   // stamp the chain these came from
        // Merge: keep local entries (any chain), overlay explorer-sourced confirmed ones for THIS chain.
        var merged = entries.filter { !($0.fromExplorer && $0.chainId == chain.id) }
        let localHashes = Set(merged.map { $0.hash.lowercased() })
        for r in remote where !localHashes.contains(r.hash.lowercased()) {
            merged.append(r)
        }
        merged.sort { $0.timestamp > $1.timestamp }
        entries = merged
        persistLocalOnly()
    }

    // MARK: - Persistence (only the local, non-explorer entries are saved)

    private func persistLocalOnly() {
        let local = entries.filter { !$0.fromExplorer }
        if let data = try? JSONEncoder().encode(local) {
            WalletKeychain.saveActivity(data)   // encrypted, device-only, out of backups
        }
    }

    private func load() {
        // Prefer the Keychain copy; one-time migration from any old plaintext UserDefaults copy.
        var data = WalletKeychain.loadActivity()
        if data == nil, let legacy = UserDefaults.standard.data(forKey: key) {
            WalletKeychain.saveActivity(legacy)
            UserDefaults.standard.removeObject(forKey: key)
            data = legacy
        }
        guard let data, let decoded = try? JSONDecoder().decode([WalletActivityEntry].self, from: data) else { return }
        entries = decoded.sorted { $0.timestamp > $1.timestamp }
    }
}
