//
//  WalletConnectCrypto.swift
//  Searxly
//
//  The WalletConnect v2 cryptographic envelope, implemented with native CryptoKit (no external
//  SDK). WC v2 uses X25519 key agreement → HKDF-SHA256 → a 32-byte symmetric key, and seals each
//  relay message with ChaCha20-Poly1305. Envelope = base64( type(1) ‖ [senderPubKey(32) if type 1] ‖
//  iv(12) ‖ ciphertext ‖ tag(16) ).
//
//  NOTE: this is a from-scratch protocol implementation. It is correct by construction for the
//  crypto primitives, but the end-to-end relay handshake can only be validated against a live
//  dApp + a WalletConnect Cloud project id.
//

import Foundation
import CryptoKit

enum WalletConnectCrypto {

    // MARK: - Keys

    static func generateKeyPair() -> (privateKey: Curve25519.KeyAgreement.PrivateKey, publicKeyHex: String) {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        return (priv, hex(priv.publicKey.rawRepresentation))
    }

    static func symKey(fromHex hexString: String) -> SymmetricKey? {
        guard let d = data(fromHex: hexString), d.count == 32 else { return nil }
        return SymmetricKey(data: d)
    }

    /// ECDH(self, peer) → HKDF-SHA256(salt = 32 zero bytes, info = empty, len = 32) — the WC convention.
    static func deriveSymKey(privateKey: Curve25519.KeyAgreement.PrivateKey, peerPublicKeyHex: String) -> SymmetricKey? {
        guard let peerData = data(fromHex: peerPublicKeyHex),
              let peerPub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerData),
              let shared = try? privateKey.sharedSecretFromKeyAgreement(with: peerPub) else { return nil }
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self,
                                              salt: Data(repeating: 0, count: 32),
                                              sharedInfo: Data(),
                                              outputByteCount: 32)
    }

    /// The relay topic for a symmetric key is sha256(key) in hex.
    static func topic(forSymKey key: SymmetricKey) -> String {
        let raw = key.withUnsafeBytes { Data($0) }
        return hex(Data(SHA256.hash(data: raw)))
    }

    // MARK: - Envelope

    /// Seals plaintext into a type-0 (symmetric) envelope, base64-encoded.
    static func encrypt(_ plaintext: Data, key: SymmetricKey) -> String? {
        guard let sealed = try? ChaChaPoly.seal(plaintext, using: key) else { return nil }
        var env = Data([0x00])
        env.append(sealed.nonce.withUnsafeBytes { Data($0) })
        env.append(sealed.ciphertext)
        env.append(sealed.tag)
        return env.base64EncodedString()
    }

    /// Opens an envelope. Handles type 0 (symmetric) and type 1 (skips the 32-byte sender key; the
    /// caller derives the matching key for type 1 via `senderPublicKeyHex`).
    static func decrypt(_ base64: String, key: SymmetricKey) -> Data? {
        guard let env = Data(base64Encoded: base64), env.count > 13 else { return nil }
        let type = env[env.startIndex]
        var offset = env.startIndex + 1
        if type == 1 { offset += 32 }
        guard env.count >= (offset - env.startIndex) + 12 + 16 else { return nil }
        let iv = env.subdata(in: offset..<offset + 12)
        let rest = env.subdata(in: offset + 12..<env.endIndex)
        guard rest.count >= 16 else { return nil }
        let ct = rest.subdata(in: 0..<rest.count - 16)
        let tag = rest.subdata(in: rest.count - 16..<rest.count)
        guard let nonce = try? ChaChaPoly.Nonce(data: iv),
              let box = try? ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ct, tag: tag),
              let pt = try? ChaChaPoly.open(box, using: key) else { return nil }
        return pt
    }

    /// The sender's public key from a type-1 envelope (needed to derive the key before decrypting).
    static func senderPublicKeyHex(fromEnvelope base64: String) -> String? {
        guard let env = Data(base64Encoded: base64), env.count > 33, env[env.startIndex] == 1 else { return nil }
        return hex(env.subdata(in: env.startIndex + 1..<env.startIndex + 33))
    }

    // MARK: - Hex

    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    static func data(fromHex hexString: String) -> Data? {
        let h = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        guard h.count % 2 == 0 else { return nil }
        var d = Data(); var i = h.startIndex
        while i < h.endIndex {
            let j = h.index(i, offsetBy: 2)
            guard let b = UInt8(h[i..<j], radix: 16) else { return nil }
            d.append(b); i = j
        }
        return d
    }
}
