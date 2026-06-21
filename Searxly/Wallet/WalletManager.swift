//
//  WalletManager.swift
//  Searxly
//
//  Full wallet implementation:
//  - BIP-39 mnemonic (real, via BIP39.swift)
//  - BIP-32/44 HD key derivation + secp256k1 + Keccak-256 → real Ethereum address
//  - Seed phrase encrypted with PIN-derived AES-GCM key, stored in Keychain
//  - PIN hash in UserDefaults (salt+SHA256)
//  - JSON-RPC balance fetching (eth_getBalance + ERC-20 balanceOf)
//  - Price feeds (CoinGecko for ETH, DexScreener for SEARXLY)
//

import Foundation
import CryptoKit
import Observation
import CommonCrypto
import AppKit

enum WalletUnlockState: Equatable {
    case notSetup
    case locked
    case unlocked
}

@Observable
@MainActor
final class WalletManager {
    static let shared = WalletManager()

    // MARK: - State

    var unlockState: WalletUnlockState = .notSetup

    /// HD accounts (all derived from the same seed). The active one is what the UI and in-app
    /// sends use; connected dApps each see their own assigned account (per-site isolation).
    var accounts: [WalletAccount] = []
    var activeAccountIndex: Int = 0

    /// The active account's address — computed so it always matches the current selection. Searches
    /// both the user accounts and the per-dApp rotation pool (a site's address can be made active).
    var activeAddress: String? { (accounts + rotationAccounts).first { $0.index == activeAccountIndex }?.address }
    var activeAccount: WalletAccount? { (accounts + rotationAccounts).first { $0.index == activeAccountIndex } }

    /// The address of a specific account index (used for per-site dApp isolation). Searches both the
    /// user-facing accounts and the hidden per-dApp rotation pool.
    func address(forAccount index: Int) -> String? {
        accounts.first { $0.index == index }?.address
            ?? rotationAccounts.first { $0.index == index }?.address
    }

    // MARK: - Per-dApp rotation pool (unlinkability)

    /// Hidden HD accounts (high index range) each dedicated to one dApp origin. Pre-derived while the
    /// wallet is unlocked so connecting a new site needs no extra prompt. Never shown as user accounts.
    private(set) var rotationAccounts: [WalletAccount] = WalletKeychain.loadRotationAccounts()

    /// Index range reserved for rotation accounts — far above any plausible user-account index so the
    /// two namespaces never collide.
    static let rotationIndexBase = 0x7000_0000
    private let rotationPoolBuffer = 5   // keep this many unused addresses ready to assign

    /// The next unused rotation account index for a brand-new origin, or nil if the pool is empty
    /// (caller falls back to the active account). "Unused" = not already assigned to some origin.
    func nextRotationAccountIndex() -> Int? {
        let assigned = Set(DAppPermissionStore.shared.accountByOrigin.values)
        return rotationAccounts.first { !assigned.contains($0.index) }?.index
    }

    /// Claims the next unused rotation address for `origin`, labels it with the site host so it's
    /// recognizable in the account list, and returns its index (nil if the pool is empty).
    func claimRotationAccount(for origin: String) -> Int? {
        guard let index = nextRotationAccountIndex(),
              let i = rotationAccounts.firstIndex(where: { $0.index == index }) else { return nil }
        rotationAccounts[i].label = hostLabel(from: origin)
        WalletKeychain.saveRotationAccounts(rotationAccounts)
        return index
    }

    /// Rotation accounts currently assigned to a connected site (shown in the account switcher so the
    /// user can spend funds a dApp received). Oldest-index first.
    var inUseRotationAccounts: [WalletAccount] {
        let assigned = Set(DAppPermissionStore.shared.accountByOrigin.values)
        return rotationAccounts.filter { assigned.contains($0.index) }.sorted { $0.index < $1.index }
    }

    private func hostLabel(from origin: String) -> String {
        var s = origin
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if let colon = s.firstIndex(of: ":") { s = String(s[..<colon]) }
        return s.isEmpty ? "dApp address" : s
    }

    // MARK: - Import private key + watch-only accounts

    /// Synthetic index ranges that never collide with HD (0,1,2…) or rotation (0x7000_0000) indices.
    static let importedIndexBase = 0x6000_0000
    static let watchOnlyIndexBase = 0x5000_0000

    /// True when the active account can't sign (a watch-only address) — Send/Sign should be disabled.
    var activeAccountIsWatchOnly: Bool { activeAccount?.kind == .watchOnly }

    enum ImportResult: Equatable { case ok, badKey, duplicate, authFailed }

    /// Imports a raw secp256k1 private key (64-hex, optional 0x) as a signable account. PIN-gated:
    /// the key is stored encrypted under the PIN, like the seed. Returns a precise result for the UI.
    @discardableResult
    func importPrivateKey(_ rawHex: String, label: String?, pin: String) -> ImportResult {
        guard attemptPIN(pin) else { return .authFailed }
        var hex = rawHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard hex.count == 64, hex.allSatisfy({ $0.isHexDigit }) else { return .badKey }
        var bytes = [UInt8](); var i = hex.startIndex
        while i < hex.endIndex { let n = hex.index(i, offsetBy: 2); bytes.append(UInt8(hex[i..<n], radix: 16)!); i = n }
        let keyData = Data(bytes)
        guard let address = EthereumAddress.address(fromPrivateKey: keyData) else { return .badKey }
        // Reject the all-zero key and any address we already track.
        guard bytes.contains(where: { $0 != 0 }) else { return .badKey }
        if (accounts + rotationAccounts).contains(where: { $0.address.lowercased() == address.lowercased() }) {
            return .duplicate
        }
        var keys = WalletKeychain.loadImportedKeys(pin: pin)
        // Use a monotonic index above EVERY index ever used for an imported key — including keys
        // orphaned by a removed account (still in the blob). A count-based index would reuse a live
        // index after a removal and overwrite another account's key. (See [[wallet-system]].)
        let usedMax = max(keys.keys.max() ?? (Self.importedIndexBase - 1),
                          accounts.filter { $0.kind == .imported }.map { $0.index }.max() ?? (Self.importedIndexBase - 1))
        let index = max(usedMax + 1, Self.importedIndexBase)
        let name = cleanLabel(label) ?? "Imported \(accounts.filter { $0.kind == .imported }.count + 1)"
        keys[index] = keyData
        guard WalletKeychain.saveImportedKeys(keys, pin: pin) else { return .authFailed }
        accounts.append(WalletAccount(index: index, address: address, label: name, kind: .imported))
        WalletKeychain.saveAccounts(accounts)
        switchAccount(to: index)
        return .ok
    }

    /// Adds a watch-only account (track any address; can't sign). No PIN needed.
    @discardableResult
    func addWatchOnly(address rawAddress: String, label: String?) -> Bool {
        let addr = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard addr.hasPrefix("0x"), addr.count == 42, addr.dropFirst(2).allSatisfy({ $0.isHexDigit }) else { return false }
        guard !(accounts + rotationAccounts).contains(where: { $0.address.lowercased() == addr.lowercased() }) else { return false }
        // Monotonic index above any existing watch-only index (count-based would collide after a removal).
        let index = max((accounts.filter { $0.kind == .watchOnly }.map { $0.index }.max() ?? (Self.watchOnlyIndexBase - 1)) + 1,
                        Self.watchOnlyIndexBase)
        let name = cleanLabel(label) ?? "Watch \(accounts.filter { $0.kind == .watchOnly }.count + 1)"
        accounts.append(WalletAccount(index: index, address: addr, label: name, kind: .watchOnly))
        WalletKeychain.saveAccounts(accounts)
        switchAccount(to: index)
        return true
    }

    private func cleanLabel(_ label: String?) -> String? {
        guard let t = label?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t
    }

    /// Tops up the rotation pool so at least `rotationPoolBuffer` unused addresses are ready. Needs
    /// the PIN to derive new addresses from the seed; called right after unlock (where we have it).
    /// Runs regardless of the toggle so that, the moment the user enables rotation, a pool is already
    /// waiting (the addresses themselves aren't secret — only signing needs the PIN).
    func replenishRotationPool(pin: String) {
        let assigned = Set(DAppPermissionStore.shared.accountByOrigin.values)
        let unused = rotationAccounts.filter { !assigned.contains($0.index) }.count
        guard unused < rotationPoolBuffer else { return }
        guard let words = WalletKeychain.loadSeed(pin: pin) else { return }
        let seed = BIP39.toSeed(words)
        var pool = rotationAccounts
        let toAdd = rotationPoolBuffer - unused
        for _ in 0..<toAdd {
            let index = Self.rotationIndexBase + pool.count
            guard let address = EthereumAddress.derive(fromSeed: seed, index: index) else { continue }
            pool.append(WalletAccount(index: index, address: address, label: "dApp address"))
        }
        rotationAccounts = pool
        WalletKeychain.saveRotationAccounts(pool)
    }

    var tokens: [WalletToken] = []
    var isFetchingPrices = false
    var isSending = false
    var lastError: String? = nil

    var ethPriceUSD: Double = 0
    var searxlyPriceUSD: Double = 0
    var searxlyChange24h: Double = 0

    // MARK: - Display currency (fiat)

    /// USD → selected-currency exchange rate (1.0 for USD).
    var fxRate: Double = 1.0

    var fiatCurrency: FiatCurrency = (FiatCurrency(rawValue: UserDefaults.standard.string(forKey: WalletConfig.Keys.fiatCurrency) ?? "") ?? .usd) {
        didSet {
            UserDefaults.standard.set(fiatCurrency.rawValue, forKey: WalletConfig.Keys.fiatCurrency)
            if fiatCurrency == .usd { fxRate = 1.0 }
            Task { await refreshFXRate() }
        }
    }

    func refreshFXRate() async {
        let c = fiatCurrency
        guard c != .usd else { fxRate = 1.0; return }
        if let r = await WalletNetwork.fxRate(usdTo: c.code) { fxRate = r }
    }

    /// Formats a USD amount in the user's selected display currency.
    func formatFiat(_ usd: Double) -> String {
        let sym = fiatCurrency.symbol
        let v = usd * fxRate
        if v == 0 { return "\(sym)0.00" }
        if abs(v) < 0.01 { return "\(sym)\(String(format: "%.4f", v))" }
        return "\(sym)\(String(format: "%.2f", v))"
    }

    /// Formats a per-coin USD market price in the display currency, with extra precision for tiny prices.
    func formatFiatPrice(_ usd: Double) -> String {
        let sym = fiatCurrency.symbol
        let v = usd * fxRate
        if v == 0 { return "—" }
        if v >= 1 { return "\(sym)\(String(format: "%.2f", v))" }
        if v >= 0.01 { return "\(sym)\(String(format: "%.4f", v))" }
        return "\(sym)\(String(format: "%.8f", v))"
    }

    /// Token IDs the user hid (spam/airdrop junk). ETH and SEARXLY can never be hidden.
    private(set) var hiddenTokenIDs: Set<String> = []
    var visibleTokens: [WalletToken] { tokens.filter { !hiddenTokenIDs.contains($0.id) } }

    func hideToken(id: String) {
        // Never hide SEARXLY or the active chain's native gas token.
        guard id != "SEARXLY", id != activeChain.nativeSymbol else { return }
        hiddenTokenIDs.insert(id); saveHiddenTokens()
    }
    func unhideAllTokens() { hiddenTokenIDs.removeAll(); saveHiddenTokens() }
    private func saveHiddenTokens() {
        UserDefaults.standard.set(Array(hiddenTokenIDs), forKey: WalletConfig.Keys.hiddenTokens)
    }

    var totalPortfolioUSD: Double { visibleTokens.reduce(0) { $0 + $1.usdValue } }

    /// USD-weighted 24h change of *held* assets. Returns 0 when the portfolio is empty,
    /// so a $0 balance never shows a misleading up/down percentage.
    var portfolioChange24h: Double {
        let total = totalPortfolioUSD
        guard total > 0 else { return 0 }
        let weighted = visibleTokens.reduce(0.0) { $0 + $1.usdValue * $1.change24h }
        return weighted / total
    }

    /// True only when the wallet actually holds value worth summarizing.
    var hasHoldings: Bool { totalPortfolioUSD > 0 }

    // MARK: - Active chain (multi-chain)

    /// The EVM chain the wallet is currently showing/using. The same HD address works on every
    /// chain; switching only changes the RPC, native token, explorer, and price feeds.
    var activeChain: WalletChain = (WalletChain.by(id: UserDefaults.standard.integer(forKey: WalletConfig.Keys.activeChain)) ?? .defaultChain)

    func switchChain(to chain: WalletChain) {
        guard chain.id != activeChain.id else { return }
        activeChain = chain
        UserDefaults.standard.set(chain.id, forKey: WalletConfig.Keys.activeChain)
        registerActivity()
        rebuildTokenList()
        // Tell connected dApps the chain changed (EIP-1193 chainChanged).
        WalletProviderBridge.shared.emitChainChanged(chain.chainIdHex)
        Task { await refreshBalancesAndPrices() }
    }

    /// Explorer URL helpers for the active chain (used by Activity / Send / Token detail).
    func explorerTxURL(_ hash: String) -> String { activeChain.explorerTxURL(hash) }
    func explorerTokenURL(_ contract: String) -> String { activeChain.explorerTokenURL(contract) }

    var customRPCURL: String {
        get { UserDefaults.standard.string(forKey: WalletConfig.Keys.customRPCURL) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: WalletConfig.Keys.customRPCURL) }
    }

    /// The RPC for the active chain. A user's custom RPC overrides ONLY on Base (where they set it);
    /// every other chain uses its bundled public endpoints (with same-chain failover).
    var activeRPCURL: String {
        let c = customRPCURL
        if activeChain.id == WalletChain.base.id, !c.isEmpty { return c }
        return activeChain.rpcURLs.first ?? ""
    }

    // MARK: - Init

    private init() {
        let configured = UserDefaults.standard.bool(forKey: WalletConfig.Keys.walletConfigured)
        if configured {
            loadAccountsOrMigrate()
            unlockState = .locked
        }
        pinFailedAttempts = UserDefaults.standard.integer(forKey: WalletConfig.Keys.pinFailedAttempts)
        let lockTS = UserDefaults.standard.double(forKey: WalletConfig.Keys.pinLockedUntil)
        if lockTS > 0 { pinLockedUntil = Date(timeIntervalSince1970: lockTS) }
        hiddenTokenIDs = Set(UserDefaults.standard.stringArray(forKey: WalletConfig.Keys.hiddenTokens) ?? [])
        rebuildTokenList()
        startAutoLockObservers()
    }

    // MARK: - HD accounts

    /// Loads the account list, migrating a pre-multi-account wallet (single stored address) into
    /// account 0 so existing wallets keep working.
    private func loadAccountsOrMigrate() {
        let loaded = WalletKeychain.loadAccounts()
        if !loaded.isEmpty {
            accounts = loaded
        } else {
            // Migrate: old single-address wallets (or the pre-Keychain plaintext address).
            var legacy = WalletKeychain.loadAddress()
            if legacy == nil, let plaintext = UserDefaults.standard.string(forKey: WalletConfig.Keys.lastKnownAddress) {
                WalletKeychain.saveAddress(plaintext)
                UserDefaults.standard.removeObject(forKey: WalletConfig.Keys.lastKnownAddress)
                legacy = plaintext
            }
            if let legacy {
                accounts = [WalletAccount(index: 0, address: legacy, label: "Account 1")]
                WalletKeychain.saveAccounts(accounts)
            }
        }
        activeAccountIndex = UserDefaults.standard.integer(forKey: WalletConfig.Keys.activeAccount)
        if !accounts.contains(where: { $0.index == activeAccountIndex }) {
            activeAccountIndex = accounts.first?.index ?? 0
        }
    }

    /// Adds a new HD account (next free index). Requires the PIN to derive its address from the seed.
    @discardableResult
    func addAccount(pin: String, label: String? = nil) -> Bool {
        guard attemptPIN(pin), let words = WalletKeychain.loadSeed(pin: pin) else { return false }
        let nextIndex = (accounts.map { $0.index }.max() ?? -1) + 1
        guard let address = EthereumAddress.derive(fromSeed: BIP39.toSeed(words), index: nextIndex) else { return false }
        let name = (label?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "Account \(nextIndex + 1)"
        accounts.append(WalletAccount(index: nextIndex, address: address, label: name))
        WalletKeychain.saveAccounts(accounts)
        switchAccount(to: nextIndex)
        return true
    }

    func switchAccount(to index: Int) {
        guard (accounts + rotationAccounts).contains(where: { $0.index == index }) else { return }
        activeAccountIndex = index
        UserDefaults.standard.set(index, forKey: WalletConfig.Keys.activeAccount)
        registerActivity()
        Task { await refreshBalancesAndPrices() }
    }

    func renameAccount(index: Int, label: String) {
        guard let i = accounts.firstIndex(where: { $0.index == index }) else { return }
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        accounts[i].label = trimmed.isEmpty ? "Account \(index + 1)" : trimmed
        WalletKeychain.saveAccounts(accounts)
    }

    /// Whether an account can be removed (hidden) from the list. The primary account (index 0) and
    /// the last remaining account can't be removed.
    func canRemoveAccount(index: Int) -> Bool { index != 0 && accounts.count > 1 }

    /// Removes (hides) an account from the list. The address isn't destroyed — it's deterministic
    /// and still controlled by your phrase — but it's taken off the list and any sites connected to
    /// it are disconnected.
    @discardableResult
    func removeAccount(index: Int) -> Bool {
        guard canRemoveAccount(index: index) else { return false }
        accounts.removeAll { $0.index == index }
        WalletKeychain.saveAccounts(accounts)
        DAppPermissionStore.shared.removeMappings(toAccount: index)
        WalletPortfolioHistoryStore.shared.clear(account: index)
        if activeAccountIndex == index { switchAccount(to: accounts.first?.index ?? 0) }
        return true
    }

    // MARK: - Auto-lock (opt-in)

    /// When an unlocked wallet automatically re-locks. Default `.never`.
    var autoLock: WalletAutoLock {
        get { WalletAutoLock(rawValue: UserDefaults.standard.string(forKey: WalletConfig.Keys.autoLock) ?? "") ?? .never }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: WalletConfig.Keys.autoLock)
            lastActivity = Date()
            configureIdleTimer()
        }
    }

    private var lastActivity = Date()
    private var idleTimer: Timer?
    private var resignObserver: NSObjectProtocol?

    /// Call on any wallet interaction so the idle timer doesn't lock an actively-used wallet.
    func registerActivity() { lastActivity = Date() }

    private func startAutoLockObservers() {
        configureIdleTimer()
        // Lock-on-switch: fires when Searxly stops being the frontmost app (opt-in).
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.autoLock.locksOnResign, self.unlockState == .unlocked else { return }
                self.lock()
            }
        }
    }

    private func configureIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard autoLock.timeout != nil else { return }   // only run a timer for time-based options
        idleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkIdleAutoLock() }
        }
    }

    private func checkIdleAutoLock() {
        guard unlockState == .unlocked, let timeout = autoLock.timeout else { return }
        if Date().timeIntervalSince(lastActivity) >= timeout { lock() }
    }

    // MARK: - PIN attempt limiting

    var pinFailedAttempts: Int = 0
    var pinLockedUntil: Date? = nil

    /// Number of wrong PINs allowed before a cooldown kicks in.
    private let pinAttemptThreshold = 5

    var isPINLocked: Bool {
        if let until = pinLockedUntil, until > Date() { return true }
        return false
    }

    /// Seconds remaining on the current lockout (0 if not locked).
    var pinLockRemaining: TimeInterval {
        guard let until = pinLockedUntil else { return 0 }
        return max(0, until.timeIntervalSinceNow)
    }

    var pinAttemptsRemaining: Int { max(0, pinAttemptThreshold - pinFailedAttempts) }

    private func registerFailedPIN() {
        pinFailedAttempts += 1
        UserDefaults.standard.set(pinFailedAttempts, forKey: WalletConfig.Keys.pinFailedAttempts)
        if pinFailedAttempts >= pinAttemptThreshold {
            // Escalating cooldown: 30s, 60s, 120s … capped at 15 minutes.
            let extra = pinFailedAttempts - pinAttemptThreshold
            let seconds = min(pow(2.0, Double(extra)) * 30.0, 900.0)
            let until = Date().addingTimeInterval(seconds)
            pinLockedUntil = until
            UserDefaults.standard.set(until.timeIntervalSince1970, forKey: WalletConfig.Keys.pinLockedUntil)
        }
    }

    func resetPINAttempts() {
        pinFailedAttempts = 0
        pinLockedUntil = nil
        UserDefaults.standard.removeObject(forKey: WalletConfig.Keys.pinFailedAttempts)
        UserDefaults.standard.removeObject(forKey: WalletConfig.Keys.pinLockedUntil)
    }

    // MARK: - Token list

    func rebuildTokenList() {
        // On Base, $SEARXLY is the hero asset and leads; then the chain's native gas token; then
        // this chain's custom tokens. On other chains there's no SEARXLY, so native leads.
        var list: [WalletToken] = []
        if activeChain.id == WalletChain.base.id { list.append(.searxly) }
        list.append(.native(for: activeChain))
        list.append(contentsOf: loadCustomTokens().filter { $0.chainId == activeChain.id })
        tokens = list
    }

    // MARK: - Custom tokens

    func addCustomToken(contractAddress: String, symbol: String, name: String, decimals: Int) {
        let trimmed = contractAddress.trimmingCharacters(in: .whitespaces).lowercased()
        guard !tokens.contains(where: { $0.contractAddress?.lowercased() == trimmed }) else { return }
        let token = WalletToken(id: trimmed, symbol: symbol.uppercased(),
                                name: name, contractAddress: trimmed,
                                decimals: decimals, isCustom: true, chainId: activeChain.id)
        var customs = loadCustomTokens()
        customs.append(token)
        saveCustomTokens(customs)
        rebuildTokenList()
    }

    func removeCustomToken(id: String) {
        var customs = loadCustomTokens()
        customs.removeAll { $0.id == id }
        saveCustomTokens(customs)
        rebuildTokenList()
    }

    private func loadCustomTokens() -> [WalletToken] {
        guard let data = UserDefaults.standard.data(forKey: WalletConfig.Keys.customTokens),
              let decoded = try? JSONDecoder().decode([WalletToken].self, from: data)
        else { return [] }
        return decoded
    }

    private func saveCustomTokens(_ list: [WalletToken]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: WalletConfig.Keys.customTokens)
    }

    // MARK: - Mnemonic

    func generateMnemonic() -> [String] {
        let words = BIP39.generateMnemonic(wordCount: 12)
        return words.isEmpty ? placeholderMnemonic() : words
    }

    // MARK: - Wallet setup

    /// Creates a new wallet: saves seed in Keychain, derives address, stores PIN.
    func prepareNewWallet(mnemonic: [String], pin: String) -> String {
        // 1. Derive real address from seed
        let seed = BIP39.toSeed(mnemonic)
        let address = EthereumAddress.derive(fromSeed: seed)
                      ?? "0x0000000000000000000000000000000000000000"

        // 2. Save encrypted seed in Keychain (PIN-encrypted)
        WalletKeychain.saveSeed(mnemonic, pin: pin)

        // 3. PIN hash in UserDefaults
        setupPIN(pin)
        resetPINAttempts()

        // 4. Recovery code + a recovery-code-encrypted copy of the seed (so a PIN reset can re-key it)
        let recoveryCode = generateAndStoreRecoveryCode()
        WalletKeychain.saveRecoverySeed(mnemonic, recoveryCode: recoveryCode)

        // 5. Persist as account 0 (Keychain — keeps the device↔address link out of plaintext/backups)
        accounts = [WalletAccount(index: 0, address: address, label: "Account 1")]
        activeAccountIndex = 0
        UserDefaults.standard.set(0, forKey: WalletConfig.Keys.activeAccount)
        WalletKeychain.saveAccounts(accounts)
        WalletKeychain.saveAddress(address)   // legacy single-address slot (kept in sync for safety)
        UserDefaults.standard.set(true, forKey: WalletConfig.Keys.walletConfigured)
        replenishRotationPool(pin: pin)       // pre-derive a per-dApp address pool

        return recoveryCode
    }

    func activateUnlock() {
        unlockState = .unlocked
        registerActivity()
        Task { await refreshBalancesAndPrices() }
    }

    func importWallet(mnemonic: [String], pin: String) -> String {
        let code = prepareNewWallet(mnemonic: mnemonic, pin: pin)
        activateUnlock()
        return code
    }

    func deleteWallet() {
        let keys = [WalletConfig.Keys.walletConfigured, WalletConfig.Keys.pinSalt,
                    WalletConfig.Keys.pinHash, WalletConfig.Keys.recoveryHash,
                    WalletConfig.Keys.lastKnownAddress, WalletConfig.Keys.customTokens,
                    WalletConfig.Keys.biometricEnabled, WalletConfig.Keys.localActivity,
                    WalletConfig.Keys.pinFailedAttempts, WalletConfig.Keys.pinLockedUntil,
                    WalletConfig.Keys.hiddenTokens, WalletConfig.Keys.priceAlerts,
                    WalletConfig.Keys.activeChain]
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        hiddenTokenIDs = []
        WalletKeychain.deleteSeed()          // wipes seed, recovery copy, salt, biometric PIN
        WalletActivityStore.shared.clear()
        WalletPortfolioHistoryStore.shared.clearAll()
        DAppPermissionStore.shared.disconnectAll()   // a fresh wallet must not inherit old site connections
        WalletProviderBridge.shared.walletDidLock()  // tell any open pages the wallet is gone
        resetPINAttempts()
        accounts = []
        rotationAccounts = []
        // Clear in-memory state so a NEW wallet can't inherit the old one's alerts or trigger false
        // "received" notifications by comparing fresh balances against the deleted wallet's.
        priceAlerts = []
        lastSeenBalances = [:]
        activeChain = .defaultChain
        activeAccountIndex = 0
        UserDefaults.standard.removeObject(forKey: WalletConfig.Keys.activeAccount)
        unlockState = .notSetup
        rebuildTokenList()
    }

    // MARK: - PIN / lock

    func setupPIN(_ pin: String) {
        let salt = UUID().uuidString
        UserDefaults.standard.set(salt, forKey: WalletConfig.Keys.pinSalt)
        UserDefaults.standard.set(pinKDF(pin, salt: salt), forKey: WalletConfig.Keys.pinHash)
    }

    func verifyPIN(_ pin: String) -> Bool {
        guard let salt = UserDefaults.standard.string(forKey: WalletConfig.Keys.pinSalt),
              let stored = UserDefaults.standard.string(forKey: WalletConfig.Keys.pinHash)
        else { return false }
        if stored.hasPrefix("p2$") { return pinKDF(pin, salt: salt) == stored }
        // Legacy fast-SHA256 PIN hash: a 6-digit PIN is brute-forceable from the stored hash in
        // milliseconds, which would let an attacker with the prefs file shortcut the seed's PBKDF2.
        // Verify the old way once, then transparently upgrade to the slow KDF below.
        if sha256("\(salt)\(pin)") == stored { setupPIN(pin); return true }
        return false
    }

    /// PIN verifier hash: PBKDF2-SHA256 (same cost as the seed KDF) so brute-forcing a 6-digit PIN
    /// from the stored hash is as expensive as attacking the seed itself — no weak link.
    private func pinKDF(_ pin: String, salt: String) -> String {
        let saltData = Data(salt.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        saltData.withUnsafeBytes { sp in
            _ = CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pin, pin.utf8.count,
                                     sp.bindMemory(to: UInt8.self).baseAddress, saltData.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 200_000, &out, 32)
        }
        return "p2$" + out.map { String(format: "%02x", $0) }.joined()
    }

    func verifyRecoveryCode(_ code: String) -> Bool {
        guard let stored = UserDefaults.standard.string(forKey: WalletConfig.Keys.recoveryHash) else { return false }
        return sha256(code.uppercased()) == stored
    }

    func lock() {
        guard unlockState == .unlocked else { return }
        unlockState = .locked
        // Tell connected pages the wallet is no longer available until re-auth.
        WalletProviderBridge.shared.walletDidLock()
    }

    /// Rate-limited PIN check used by EVERY UI PIN entry (unlock, Send confirm, dApp approval,
    /// delete). Enforces the lockout consistently so a sign/approval prompt can't be used to
    /// brute-force the PIN around the unlock-screen limit. Returns false while locked.
    @discardableResult
    func attemptPIN(_ pin: String) -> Bool {
        guard !isPINLocked else { return false }
        if verifyPIN(pin) { resetPINAttempts(); return true }
        registerFailedPIN()
        return false
    }

    func unlock(pin: String) -> Bool {
        guard attemptPIN(pin) else { return false }
        unlockState = .unlocked
        registerActivity()
        replenishRotationPool(pin: pin)   // keep a few per-dApp addresses ready
        Task { await refreshBalancesAndPrices() }
        return true
    }

    // MARK: - Biometric unlock

    var biometricUnlockEnabled: Bool {
        UserDefaults.standard.bool(forKey: WalletConfig.Keys.biometricEnabled)
    }

    var biometricAvailable: Bool { WalletBiometric.isAvailable }

    /// Enables Face/Touch ID unlock by stashing the (PIN-verified) PIN behind the Secure-Enclave
    /// biometric gate in the Keychain.
    @discardableResult
    func enableBiometricUnlock(pin: String) -> Bool {
        guard attemptPIN(pin), WalletBiometric.isAvailable else { return false }
        guard WalletKeychain.saveBiometricPIN(pin) else { return false }   // biometry-gated item
        UserDefaults.standard.set(true, forKey: WalletConfig.Keys.biometricEnabled)
        UserDefaults.standard.set(true, forKey: "Wallet.biometricSecured")  // freshly secured
        return true
    }

    func disableBiometricUnlock() {
        WalletKeychain.deleteBiometricPIN()
        UserDefaults.standard.set(false, forKey: WalletConfig.Keys.biometricEnabled)
        UserDefaults.standard.removeObject(forKey: "Wallet.biometricSecured")
    }

    /// Unlocks via biometrics. Returns false if disabled, unavailable, or the check fails.
    func unlockWithBiometrics() async -> Bool {
        guard biometricUnlockEnabled,
              let ctx = await WalletBiometric.authenticatedContext(reason: "Unlock your Searxly wallet"),
              let pin = WalletKeychain.loadBiometricPIN(context: ctx)   // biometry-gated Keychain read
        else { return false }
        secureBiometricPINIfNeeded(pin)
        return unlock(pin: pin)
    }

    /// One-time upgrade: wallets that enabled biometrics before the Secure-Enclave gate existed have
    /// the PIN in a plain (no-access-control) item. On the next successful biometric unlock, re-store
    /// it behind `.biometryCurrentSet`.
    private func secureBiometricPINIfNeeded(_ pin: String) {
        let key = "Wallet.biometricSecured"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        WalletKeychain.saveBiometricPIN(pin)
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Biometric confirmation for a single signature/transaction. When biometric unlock is
    /// enabled this is required; otherwise callers fall back to PIN entry.
    func confirmWithBiometrics(reason: String) async -> Bool {
        guard biometricUnlockEnabled else { return false }
        return await WalletBiometric.authenticate(reason: reason)
    }

    /// Biometric-gates a signing operation and returns the PIN needed to decrypt the seed.
    /// Returns nil if biometric unlock isn't enabled or the check fails — callers then use PIN entry.
    func authorizeSigningWithBiometrics(reason: String) async -> String? {
        guard biometricUnlockEnabled,
              let ctx = await WalletBiometric.authenticatedContext(reason: reason)
        else { return nil }
        return WalletKeychain.loadBiometricPIN(context: ctx)   // biometry-gated Keychain read
    }

    func unlockWithRecoveryCode(_ code: String, newPIN: String) -> Bool {
        // The recovery code decrypts the recovery copy of the seed; re-encrypt it under the new PIN.
        guard let words = WalletKeychain.loadRecoverySeed(recoveryCode: code) else { return false }
        WalletKeychain.saveSeed(words, pin: newPIN)
        setupPIN(newPIN)
        resetPINAttempts()
        // The stashed biometric PIN is now stale; disable until the user re-enables it.
        disableBiometricUnlock()
        unlockState = .unlocked
        registerActivity()
        replenishRotationPool(pin: newPIN)
        Task { await refreshBalancesAndPrices() }
        return true
    }

    func generateAndStoreRecoveryCode() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &bytes)
        let code = bytes.map { String(format: "%02X", $0) }.joined()
        UserDefaults.standard.set(sha256(code), forKey: WalletConfig.Keys.recoveryHash)
        return code
    }

    // MARK: - Balances + prices

    func refreshBalancesAndPrices() async {
        guard unlockState == .unlocked, let address = activeAddress,
              address != "0x0000000000000000000000000000000000000000" else { return }

        isFetchingPrices = true
        defer { isFetchingPrices = false }

        await refreshFXRate()   // keep the display-currency rate fresh (no-op for USD)

        let chain = activeChain
        let rpc = activeRPCURL
        let onBase = chain.id == WalletChain.base.id

        // Optional: auto-discover tokens this address holds (Etherscan v2) before fetching balances.
        if WalletFeatures.tokenDiscovery {
            let discovered = await WalletNetwork.discoverTokens(address: address, chainId: chain.id)
            for t in discovered where !tokens.contains(where: { $0.contractAddress?.lowercased() == t.contract.lowercased() }) {
                addCustomToken(contractAddress: t.contract, symbol: t.symbol, name: t.name, decimals: t.decimals)
            }
        }

        // Fetch native balance + (Base-only) SEARXLY + prices concurrently.
        async let nativeBal = WalletNetwork.ethBalance(address: address, rpc: rpc)
        async let searxlyBal = onBase ? WalletNetwork.erc20Balance(
            tokenAddress: WalletConfig.searxlyTokenAddress,
            walletAddress: address,
            decimals: WalletConfig.searxlyTokenDecimals,
            rpc: rpc) : nil
        async let prices = WalletNetwork.fetchPrices(
            nativeCoinGeckoID: chain.coinGeckoNativeID,
            searxlyAddress: onBase ? WalletConfig.searxlyTokenAddress : nil)

        let (nb, sb, pr) = await (nativeBal, searxlyBal, prices)

        ethPriceUSD = pr.ethUSD
        searxlyPriceUSD = pr.searxlyUSD
        searxlyChange24h = pr.searxlyChange24h

        updateToken(id: chain.nativeSymbol, balance: nb ?? 0, price: pr.ethUSD, change: 0)
        if onBase { updateToken(id: "SEARXLY", balance: sb ?? 0, price: pr.searxlyUSD, change: pr.searxlyChange24h) }

        // Custom ERC-20 balances
        let customs = tokens.filter { $0.isCustom }
        await withTaskGroup(of: (String, Decimal, Double).self) { group in
            for token in customs {
                guard let ca = token.contractAddress else { continue }
                // Read the (MainActor-isolated) token fields here, then capture plain values into the
                // concurrent child task — avoids touching actor-isolated state off the main actor.
                let tid = token.id, decimals = token.decimals, isStable = token.isStablecoin
                group.addTask {
                    let bal = await WalletNetwork.erc20Balance(
                        tokenAddress: ca, walletAddress: address, decimals: decimals, rpc: rpc)
                    // Known stablecoins are pegged to $1; unknown tokens have no price feed.
                    return (tid, bal ?? 0, isStable ? 1.0 : 0)
                }
            }
            for await (id, bal, price) in group {
                updateToken(id: id, balance: bal, price: price, change: 0)
            }
        }

        // Snapshot the (displayed) total for the portfolio-over-time graph. On-device only.
        WalletPortfolioHistoryStore.shared.record(accountIndex: activeAccountIndex, usd: totalPortfolioUSD)

        // Local-only alerts: notify on inbound transfers and on crossed price targets.
        detectIncomingFunds()
        checkPriceAlerts()
    }

    /// The active account's portfolio-value history (on-device snapshots), oldest-first.
    var portfolioSeries: [PortfolioSnapshot] {
        WalletPortfolioHistoryStore.shared.series(forAccount: activeAccountIndex)
    }

    // MARK: - Price alerts + incoming-funds notifications

    private(set) var priceAlerts: [WalletPriceAlert] = WalletPriceAlertStore.load()

    func addPriceAlert(token: WalletToken, targetUSD: Double, above: Bool) {
        let alert = WalletPriceAlert(tokenID: token.id, tokenSymbol: token.symbol, targetUSD: targetUSD, above: above)
        priceAlerts.append(alert)
        WalletPriceAlertStore.save(priceAlerts)
    }

    func removePriceAlert(id: UUID) {
        priceAlerts.removeAll { $0.id == id }
        WalletPriceAlertStore.save(priceAlerts)
    }

    func priceAlerts(forTokenID id: String) -> [WalletPriceAlert] {
        priceAlerts.filter { $0.tokenID == id }
    }

    /// Fires any price alert whose threshold the current price has crossed, then consumes it.
    private func checkPriceAlerts() {
        guard !priceAlerts.isEmpty else { return }
        var triggeredIDs: [UUID] = []
        for alert in priceAlerts {
            guard let token = tokens.first(where: { $0.id == alert.tokenID }), token.priceUSD > 0,
                  alert.crossed(currentUSD: token.priceUSD) else { continue }
            triggeredIDs.append(alert.id)
            NotificationManager.shared.show(
                title: "\(alert.tokenSymbol) price alert",
                body: "\(alert.tokenSymbol) is now \(formatFiatPrice(token.priceUSD)) — \(alert.directionWord) your \(formatFiatPrice(alert.targetUSD)) target.",
                source: "Searxly Wallet", iconSystemName: "bell.badge.fill")
        }
        guard !triggeredIDs.isEmpty else { return }
        priceAlerts.removeAll { triggeredIDs.contains($0.id) }
        WalletPriceAlertStore.save(priceAlerts)
    }

    /// Per (chain,account,token) last-seen balance, to detect inbound transfers between refreshes.
    private var lastSeenBalances: [String: Decimal] = [:]

    private func detectIncomingFunds() {
        guard WalletFeatures.incomingAlerts, !isSending else {
            // Still snapshot so a send doesn't later look like a receive.
            snapshotBalances(); return
        }
        for token in tokens {
            let key = "\(activeChain.id):\(activeAccountIndex):\(token.id)"
            let previous = lastSeenBalances[key]
            lastSeenBalances[key] = token.balance
            guard let previous else { continue }                  // first sighting → baseline only
            let delta = token.balance - previous
            guard delta > 0 else { continue }
            let amount = (delta as NSDecimalNumber).doubleValue
            let pretty = amount < 0.0001 ? String(format: "%.8f", amount) : String(format: "%.4f", amount)
            NotificationManager.shared.show(
                title: "Received \(token.symbol)",
                body: "+\(pretty) \(token.symbol) arrived on \(activeChain.name).",
                source: "Searxly Wallet", iconSystemName: "arrow.down.circle.fill")
            WalletActivityStore.shared.record(WalletActivityEntry(
                hash: "", kind: .receive, tokenSymbol: token.symbol,
                amount: pretty, counterparty: activeAddress ?? "", timestamp: Date(), status: .confirmed))
        }
    }

    private func snapshotBalances() {
        for token in tokens {
            lastSeenBalances["\(activeChain.id):\(activeAccountIndex):\(token.id)"] = token.balance
        }
    }

    private func updateToken(id: String, balance: Decimal, price: Double, change: Double) {
        guard let idx = tokens.firstIndex(where: { $0.id == id }) else { return }
        tokens[idx].balance = balance
        tokens[idx].priceUSD = price
        tokens[idx].change24h = change
    }

    // MARK: - Send (EIP-1559 build → sign → broadcast)

    var lastTxHash: String? = nil

    /// Builds, signs, and broadcasts a real transaction on Base L2.
    /// `pin` is required to decrypt the seed phrase and derive the signing key.
    func send(to recipient: String, amount: Decimal, token: WalletToken, pin: String,
              speed: GasSpeed = .normal) async -> Bool {
        lastError = nil
        lastTxHash = nil

        // 0. Watch-only / hardware accounts have no local key.
        if activeAccount?.kind == .watchOnly {
            lastError = "This is a watch-only address — it can't send."
            return false
        }
        if activeAccount?.kind == .hardware {
            lastError = "Hardware-wallet signing needs your Ledger connected. Device support is coming in a hardware-enabled build."
            return false
        }

        // 1. Resolve the signing key for the active account (HD-derived OR imported).
        guard let privateKey = privateKey(forPIN: pin, accountIndex: activeAccountIndex),
              let fromAddress = activeAddress else {
            lastError = "Could not unlock your wallet key."
            return false
        }

        let rpc = activeRPCURL

        // 2. Determine recipient, value, and call data
        let isERC20 = token.contractAddress != nil
        let txTo: String
        let valueBytes: [UInt8]
        let data: Data

        if isERC20, let contract = token.contractAddress {
            let amountBytes = WeiConverter.baseUnitBytes(amount: amount, decimals: token.decimals)
            txTo = contract
            valueBytes = []   // ETH value is 0 for token transfers
            data = EthereumTransaction.erc20TransferData(to: recipient, amountBytes: amountBytes)
        } else {
            txTo = recipient
            valueBytes = WeiConverter.baseUnitBytes(amount: amount, decimals: token.decimals)
            data = Data()
        }

        // 3. Fetch chain params concurrently
        async let nonceA = WalletNetwork.transactionCount(address: fromAddress, rpc: rpc)
        async let tipA   = WalletNetwork.maxPriorityFee(rpc: rpc)
        async let baseA  = WalletNetwork.baseFee(rpc: rpc)

        guard let nonce = await nonceA else {
            lastError = "Could not fetch account nonce. Check your network."
            return false
        }
        let tip = await tipA ?? GasOptions.fallbackTip
        let base = await baseA ?? GasOptions.fallbackBaseFee
        let gasFee = GasOptions.fee(for: speed, baseFee: base, priorityTip: tip)

        // 4. Gas limit (estimate, with sane fallbacks)
        let valueHex = "0x" + (valueBytes.isEmpty ? "0" : valueBytes.map { String(format: "%02x", $0) }.joined())
        let dataHex = data.isEmpty ? "0x" : "0x" + data.map { String(format: "%02x", $0) }.joined()
        let estimated = await WalletNetwork.estimateGas(from: fromAddress, to: txTo, valueHex: valueHex, dataHex: dataHex, rpc: rpc)
        let gasLimit = estimated.map { $0 + $0 / 5 } ?? (isERC20 ? 100_000 : 21_000)  // +20% headroom

        // 5. Build, sign, broadcast
        let tx = EthereumTransaction(
            chainId: UInt64(activeChain.id),
            nonce: nonce,
            maxPriorityFeePerGas: gasFee.maxPriorityFeePerGas,
            maxFeePerGas: gasFee.maxFeePerGas,
            gasLimit: gasLimit,
            to: txTo,
            valueWei: valueBytes,
            data: data
        )

        guard let rawTx = tx.signedRawTransaction(privateKey: privateKey) else {
            lastError = "Transaction signing failed."
            return false
        }

        let result = await WalletNetwork.sendRawTransaction(rawTx, rpc: rpc)
        if let hash = result.txHash {
            lastTxHash = hash
            WalletActivityStore.shared.record(WalletActivityEntry(
                hash: hash, kind: .send, tokenSymbol: token.symbol,
                amount: "\(amount)", counterparty: recipient, timestamp: Date(), status: .pending,
                pending: PendingTxInfo(nonce: nonce, to: txTo, valueHex: valueHex, dataHex: dataHex,
                                       gasLimit: gasLimit, maxFeePerGas: gasFee.maxFeePerGas,
                                       maxPriorityFeePerGas: gasFee.maxPriorityFeePerGas,
                                       accountIndex: activeAccountIndex)))
            WalletActivityStore.shared.trackPending(hash: hash, rpc: rpc)
            // Refresh balances shortly after broadcast
            Task { await refreshBalancesAndPrices() }
            return true
        } else {
            lastError = result.error ?? "Transaction failed to broadcast."
            return false
        }
    }

    // MARK: - dApp signing primitives (used by WalletProviderBridge)

    /// Derives the signing private key from the PIN-decrypted seed for a given account index
    /// (defaults to the active account). In-app only.
    func privateKey(forPIN pin: String, accountIndex: Int? = nil) -> Data? {
        let idx = accountIndex ?? activeAccountIndex
        if let acct = accounts.first(where: { $0.index == idx }) {
            switch acct.kind {
            case .watchOnly, .hardware:
                return nil                                       // no local key (hardware signs on-device)
            case .imported:
                return WalletKeychain.loadImportedKeys(pin: pin)[idx]   // PIN decrypts the stored key
            case .hd:
                break
            }
        }
        // HD account (user, or rotation-pool index) → derive from the seed.
        guard let words = WalletKeychain.loadSeed(pin: pin) else { return nil }
        return EthereumAddress.derivePrivateKey(fromSeed: BIP39.toSeed(words), index: idx)
    }

    func dappPersonalSign(message: String, pin: String, accountIndex: Int? = nil) -> String? {
        guard let key = privateKey(forPIN: pin, accountIndex: accountIndex) else { return nil }
        return EthereumMessageSigner.personalSign(message: message, privateKey: key)
    }

    func dappSignTypedData(json: String, pin: String, accountIndex: Int? = nil) -> String? {
        guard let key = privateKey(forPIN: pin, accountIndex: accountIndex) else { return nil }
        return EthereumMessageSigner.signTypedDataV4(json: json, privateKey: key)
    }

    /// Builds/signs/broadcasts a transaction whose fields come straight from a dApp request.
    /// `accountIndex` is the connected origin's account (per-site isolation); defaults to active.
    func dappSendTransaction(toHex: String, valueHex: String?, dataHex: String?,
                             gasHex: String?, pin: String, speed: GasSpeed = .normal,
                             accountIndex: Int? = nil)
        async -> (hash: String?, error: String?) {
        let idx = accountIndex ?? activeAccountIndex
        // A site bound to a non-signing account can't transact — say why, rather than "locked".
        if let kind = (accounts + rotationAccounts).first(where: { $0.index == idx })?.kind,
           kind == .watchOnly || kind == .hardware {
            return (nil, kind == .hardware ? "This account signs on a hardware device." : "This is a watch-only account — it can't sign.")
        }
        guard let key = privateKey(forPIN: pin, accountIndex: idx), let from = address(forAccount: idx) else {
            return (nil, "Wallet is locked.")
        }
        let rpc = activeRPCURL

        async let nonceA = WalletNetwork.transactionCount(address: from, rpc: rpc)
        async let tipA   = WalletNetwork.maxPriorityFee(rpc: rpc)
        async let baseA  = WalletNetwork.baseFee(rpc: rpc)

        guard let nonce = await nonceA else { return (nil, "Could not fetch account nonce.") }
        let gasFee = GasOptions.fee(for: speed,
                                    baseFee: await baseA ?? GasOptions.fallbackBaseFee,
                                    priorityTip: await tipA ?? GasOptions.fallbackTip)

        let valueBytes = Array(RLP.dataFromHex(valueHex ?? "0x0"))
        let data = RLP.dataFromHex(dataHex ?? "0x")

        let gasLimit: UInt64
        if let g = gasHex, let parsed = WalletNetwork.hexToUInt64(g), parsed > 0 {
            gasLimit = parsed
        } else {
            let est = await WalletNetwork.estimateGas(from: from, to: toHex,
                                                      valueHex: valueHex ?? "0x0",
                                                      dataHex: dataHex ?? "0x", rpc: rpc)
            gasLimit = est.map { $0 + $0 / 5 } ?? 150_000
        }

        let tx = EthereumTransaction(
            chainId: UInt64(activeChain.id),
            nonce: nonce,
            maxPriorityFeePerGas: gasFee.maxPriorityFeePerGas,
            maxFeePerGas: gasFee.maxFeePerGas,
            gasLimit: gasLimit,
            to: toHex,
            valueWei: valueBytes,
            data: data
        )
        guard let raw = tx.signedRawTransaction(privateKey: key) else { return (nil, "Signing failed.") }
        let result = await WalletNetwork.sendRawTransaction(raw, rpc: rpc)
        if let hash = result.txHash {
            let isContract = !data.isEmpty
            WalletActivityStore.shared.record(WalletActivityEntry(
                hash: hash, kind: isContract ? .contract : .send, tokenSymbol: activeChain.nativeSymbol,
                amount: TxPreview(to: toHex, valueHex: valueHex, dataHex: dataHex).valueEth,
                counterparty: toHex, timestamp: Date(), status: .pending,
                pending: PendingTxInfo(nonce: nonce, to: toHex, valueHex: valueHex ?? "0x0", dataHex: dataHex ?? "0x",
                                       gasLimit: gasLimit, maxFeePerGas: gasFee.maxFeePerGas,
                                       maxPriorityFeePerGas: gasFee.maxPriorityFeePerGas,
                                       accountIndex: idx)))
            WalletActivityStore.shared.trackPending(hash: hash, rpc: rpc)
            Task { await refreshBalancesAndPrices() }
        }
        return (hash: result.txHash, error: result.error)
    }

    // MARK: - Replace-by-fee (speed up / cancel a stuck pending tx)

    /// Replacement gas must exceed the original by enough for nodes to accept it (geth requires
    /// +10%). We bump by +25% and at least +1 gwei to be safely above that floor.
    private func bumpedGas(_ v: UInt64) -> UInt64 { max(v + v / 4, v + 1_000_000_000) }

    /// The HD account index that sent a pending tx (for replace-by-fee). Falls back to the active
    /// account only for legacy entries that predate the stored index.
    private func senderIndex(for p: PendingTxInfo) -> Int { p.accountIndex >= 0 ? p.accountIndex : activeAccountIndex }

    /// Rebroadcasts a pending tx at the same nonce with higher gas so it confirms faster.
    func speedUpTransaction(_ entry: WalletActivityEntry, pin: String) async -> (hash: String?, error: String?) {
        guard let p = entry.pending else { return (nil, "This transaction can't be sped up.") }
        // Sign with the SAME account that sent the original (the nonce belongs to it), not whatever
        // account happens to be active now.
        let idx = senderIndex(for: p)
        guard let key = privateKey(forPIN: pin, accountIndex: idx) else { return (nil, "Couldn't unlock the sending account.") }
        let tx = EthereumTransaction(
            chainId: UInt64(entry.chainId), nonce: p.nonce,
            maxPriorityFeePerGas: bumpedGas(p.maxPriorityFeePerGas), maxFeePerGas: bumpedGas(p.maxFeePerGas),
            gasLimit: p.gasLimit, to: p.to,
            valueWei: Array(RLP.dataFromHex(p.valueHex)), data: RLP.dataFromHex(p.dataHex))
        return await broadcastReplacement(tx, key: key, replacing: entry, kind: entry.kind,
                                          symbol: entry.tokenSymbol, amount: entry.amount, counterparty: p.to,
                                          senderIndex: idx)
    }

    /// Replaces a pending tx with a 0-value self-send at the same nonce — cancels the original.
    func cancelTransaction(_ entry: WalletActivityEntry, pin: String) async -> (hash: String?, error: String?) {
        guard let p = entry.pending else { return (nil, "This transaction can't be cancelled.") }
        let idx = senderIndex(for: p)
        // The cancel must be a self-send from the ORIGINAL sender (same nonce owner), not the active
        // account — otherwise it could replace an unrelated tx of a different account at that nonce.
        guard let from = address(forAccount: idx) else { return (nil, "Couldn't resolve the sending account.") }
        guard let key = privateKey(forPIN: pin, accountIndex: idx) else { return (nil, "Couldn't unlock the sending account.") }
        let tx = EthereumTransaction(
            chainId: UInt64(entry.chainId), nonce: p.nonce,
            maxPriorityFeePerGas: bumpedGas(p.maxPriorityFeePerGas), maxFeePerGas: bumpedGas(p.maxFeePerGas),
            gasLimit: 21_000, to: from, valueWei: [], data: Data())
        return await broadcastReplacement(tx, key: key, replacing: entry, kind: .send,
                                          symbol: (WalletChain.by(id: entry.chainId) ?? activeChain).nativeSymbol,
                                          amount: "0", counterparty: from, cancel: true, senderIndex: idx)
    }

    /// The RPC for a given chain id (mirrors `activeRPCURL`'s custom-on-Base rule).
    private func rpcURL(forChain chainId: Int) -> String {
        let chain = WalletChain.by(id: chainId) ?? activeChain
        if chain.id == WalletChain.base.id, !customRPCURL.isEmpty { return customRPCURL }
        return chain.rpcURLs.first ?? activeRPCURL
    }

    private func broadcastReplacement(_ tx: EthereumTransaction, key: Data, replacing entry: WalletActivityEntry,
                                      kind: WalletActivityEntry.Kind, symbol: String, amount: String,
                                      counterparty: String, cancel: Bool = false, senderIndex: Int) async -> (hash: String?, error: String?) {
        guard let raw = tx.signedRawTransaction(privateKey: key) else { return (nil, "Signing failed.") }
        // Broadcast on the chain the original tx was on (not necessarily the active chain).
        let rpc = rpcURL(forChain: entry.chainId)
        let result = await WalletNetwork.sendRawTransaction(raw, rpc: rpc)
        guard let hash = result.txHash else { return (nil, result.error ?? "Replacement failed to broadcast.") }

        WalletActivityStore.shared.markReplaced(hash: entry.hash)
        let newPending = PendingTxInfo(
            nonce: tx.nonce, to: tx.to,
            valueHex: "0x" + (tx.valueWei.isEmpty ? "0" : tx.valueWei.map { String(format: "%02x", $0) }.joined()),
            dataHex: tx.data.isEmpty ? "0x" : "0x" + tx.data.map { String(format: "%02x", $0) }.joined(),
            gasLimit: tx.gasLimit, maxFeePerGas: tx.maxFeePerGas, maxPriorityFeePerGas: tx.maxPriorityFeePerGas,
            accountIndex: senderIndex)
        WalletActivityStore.shared.record(WalletActivityEntry(
            hash: hash, kind: cancel ? .send : kind, tokenSymbol: symbol,
            amount: cancel ? "0" : amount, counterparty: counterparty, timestamp: Date(),
            status: .pending, pending: newPending))
        WalletActivityStore.shared.trackPending(hash: hash, rpc: rpc)
        return (hash: hash, error: nil)
    }

    // MARK: - Swap execution (0x)

    /// Approves the sell token if needed (waiting for confirmation), then submits the 0x swap tx.
    func executeSwap(quote: SwapQuote, pin: String) async -> (hash: String?, error: String?) {
        let rpc = activeRPCURL

        if let spender = quote.needsAllowanceTo, let sellContract = quote.sellToken.contractAddress {
            let amountBytes = WeiConverter.baseUnitBytes(amount: quote.sellAmount, decimals: quote.sellToken.decimals)
            let approveData = EthereumTransaction.erc20ApproveData(spender: spender, amountBytes: amountBytes)
            let approveHex = "0x" + approveData.map { String(format: "%02x", $0) }.joined()
            let approve = await dappSendTransaction(toHex: sellContract, valueHex: "0x0", dataHex: approveHex, gasHex: nil, pin: pin)
            guard let approveHash = approve.hash else { return (nil, approve.error ?? "Token approval failed") }
            // Wait for the approval to be mined before swapping.
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if await WalletNetwork.transactionReceipt(hash: approveHash, rpc: rpc) != .pending { break }
            }
        }

        return await dappSendTransaction(toHex: quote.to, valueHex: quote.value, dataHex: quote.data, gasHex: nil, pin: pin)
    }

    // MARK: - Revoke a token approval

    /// Sets a spender's allowance back to 0 (`approve(spender, 0)`) — undoes a risky approval.
    func revokeApproval(tokenContract: String, spender: String, pin: String) async -> (hash: String?, error: String?) {
        let data = EthereumTransaction.erc20ApproveData(spender: spender, amountBytes: [])
        let hex = "0x" + data.map { String(format: "%02x", $0) }.joined()
        return await dappSendTransaction(toHex: tokenContract, valueHex: "0x0", dataHex: hex, gasHex: nil, pin: pin)
    }

    // MARK: - Helpers

    private func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func placeholderMnemonic() -> [String] {
        ["abandon","ability","able","about","above","absent",
         "absorb","abstract","absurd","abuse","access","accident"]
    }
}
