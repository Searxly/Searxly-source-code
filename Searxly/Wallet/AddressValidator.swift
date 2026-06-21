//
//  AddressValidator.swift
//  Searxly
//
//  Recipient-address safety checks for sends. On Base, ETH and every ERC-20 share the same
//  0x…40-hex address format, so "wrong address" means one of: not an EVM address at all (a
//  Bitcoin/Solana address pasted by mistake), wrong length / bad characters, a mistyped address
//  that fails its EIP-55 checksum, the burn address, or a token *contract* address (sending
//  coins to a contract usually destroys them). Each case returns a plain-language message.
//

import Foundation

enum AddressValidator {

    enum Result: Equatable {
        case ok                      // valid, nothing to flag
        case info(String)            // valid but worth a note (your own address)
        case warning(String)         // valid format but risky destination — needs explicit confirm
        case invalid(String)         // not a usable address — block the send

        /// Whether a send may proceed at all (warnings are sendable after the user confirms).
        var isSendable: Bool { if case .invalid = self { return false } else { return true } }
        /// Whether the user must explicitly acknowledge the risk before sending.
        var requiresConfirm: Bool { if case .warning = self { return true } else { return false } }

        var message: String? {
            switch self {
            case .ok: return nil
            case .info(let m), .warning(let m), .invalid(let m): return m
            }
        }
    }

    /// Validates a recipient `0x` address for an EVM transfer.
    /// - Parameters:
    ///   - raw: the address as typed (already resolved from a name, if any).
    ///   - selfAddress: the wallet's own address, to flag self-sends.
    ///   - knownTokenContracts: contract addresses the wallet knows about, to flag token-contract sends.
    ///   - knownRecipients: addresses the user has actually sent to before, to catch address-poisoning
    ///     look-alikes (a scam address that mimics the first/last 4 chars of one you really used).
    static func validate(_ raw: String, selfAddress: String?, knownTokenContracts: [String],
                         knownRecipients: [String] = []) -> Result {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return .invalid("Enter the address you want to send to.") }

        // Not a 0x address — try to name what it actually is so the message is useful.
        guard s.hasPrefix("0x") || s.hasPrefix("0X") else {
            if looksLikeBitcoin(s) {
                return .invalid("That looks like a Bitcoin address. This wallet only sends on Base — paste a 0x… address.")
            }
            if looksLikeSolana(s) {
                return .invalid("That looks like a Solana address. This wallet only sends on Base — paste a 0x… address.")
            }
            return .invalid("That's not a Base address. Base addresses start with “0x”.")
        }

        let hex = String(s.dropFirst(2))
        guard hex.count == 40 else {
            return .invalid(hex.count < 40
                ? "Address is too short — a Base address is 42 characters (0x + 40)."
                : "Address is too long — a Base address is 42 characters (0x + 40).")
        }
        guard hex.allSatisfy({ $0.isHexDigit }) else {
            return .invalid("Address has invalid characters — it can only contain 0–9 and a–f.")
        }

        let lower = "0x" + hex.lowercased()

        // Burn / zero address.
        if hex.allSatisfy({ $0 == "0" }) {
            return .invalid("That's the burn address (0x0…0). Anything sent there is destroyed.")
        }

        // EIP-55 checksum — only enforce when the address is mixed-case (i.e. it claims to be
        // checksummed). All-lower or all-upper addresses are valid but un-checksummed.
        let hasUpper = hex.contains { $0.isLetter && $0.isUppercase }
        let hasLower = hex.contains { $0.isLetter && $0.isLowercase }
        if hasUpper && hasLower, !isChecksumValid(hex) {
            return .invalid("This address has a typo — its checksum doesn't match. Re-check every character.")
        }

        // Sending coins to a token's own contract address is a classic, irreversible mistake.
        if knownTokenContracts.contains(where: { $0.lowercased() == lower }) {
            return .warning("This is a token's contract address, not a personal wallet. Coins sent here are almost always lost forever.")
        }

        // Self-send — allowed, but worth pointing out.
        if let me = selfAddress?.lowercased(), me == lower {
            return .info("This is your own wallet address.")
        }

        // Address-poisoning guard: if this isn't an address you've used, but it mimics the visible
        // ends (first 4 + last 4 hex) of one you HAVE sent to, it's almost certainly a poisoning scam.
        if let impersonated = lookAlike(of: lower, in: knownRecipients) {
            return .warning("This looks like an address you've used before (\(shortForm(impersonated))) but it is NOT the same address. This is how address-poisoning scams steal funds — check every character, or pick the real one from your history.")
        }

        return .ok
    }

    // MARK: - Address-poisoning detection

    /// Returns a known recipient that this address visually imitates (same first-4 and last-4 hex)
    /// without being identical — the classic poisoning look-alike. nil if none / it's a real match.
    private static func lookAlike(of lower: String, in knownRecipients: [String]) -> String? {
        let known = knownRecipients
            .map { $0.lowercased() }
            .filter { $0.hasPrefix("0x") && $0.count == 42 }
        guard known.count > 0, !known.contains(lower) else { return nil }   // exact match → trusted
        let body = lower.dropFirst(2)
        let head = body.prefix(4), tail = body.suffix(4)
        for k in known {
            let kb = k.dropFirst(2)
            if kb.prefix(4) == head && kb.suffix(4) == tail { return k }     // same eyeballed ends, different middle
        }
        return nil
    }

    private static func shortForm(_ address: String) -> String {
        guard address.count >= 10 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }

    // MARK: - EIP-55 checksum

    private static func isChecksumValid(_ hex: String) -> Bool {
        let chars = Array(hex)
        let hash = Keccak256.hash(Data(hex.lowercased().utf8))   // 32 bytes
        for i in 0..<40 {
            let byte = hash[i / 2]
            let nibble = (i % 2 == 0) ? Int(byte >> 4) : Int(byte & 0x0f)
            let c = chars[i]
            if c.isLetter, (nibble >= 8) != c.isUppercase { return false }
        }
        return true
    }

    // MARK: - Other-chain heuristics (only used to make the error message helpful)

    private static let base58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

    private static func looksLikeBitcoin(_ s: String) -> Bool {
        if s.lowercased().hasPrefix("bc1") { return s.count >= 14 }
        if (s.hasPrefix("1") || s.hasPrefix("3")), (26...35).contains(s.count) {
            return s.allSatisfy { base58.contains($0) }
        }
        return false
    }

    private static func looksLikeSolana(_ s: String) -> Bool {
        (32...44).contains(s.count) && s.allSatisfy { base58.contains($0) }
    }
}
