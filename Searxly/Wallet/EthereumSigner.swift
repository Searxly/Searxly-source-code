//
//  EthereumSigner.swift
//  Searxly
//
//  Shared secp256k1 recoverable signing over a 32-byte hash.
//  Used by both transaction signing (EthereumTransaction) and message signing
//  (EthereumMessageSigner: personal_sign / EIP-712).
//

import Foundation
import libsecp256k1

enum EthereumSigner {

    /// A recoverable ECDSA signature over a 32-byte digest.
    struct RecoverableSignature {
        let r: [UInt8]      // 32 bytes
        let s: [UInt8]      // 32 bytes
        let recid: Int      // 0 or 1 (y-parity)
    }

    /// Signs a pre-computed 32-byte hash with a 32-byte private key.
    /// Uses RFC-6979 deterministic nonces; randomizes the context for side-channel resistance.
    static func sign(hash32: Data, privateKey: Data) -> RecoverableSignature? {
        guard hash32.count == 32, privateKey.count == 32 else { return nil }
        guard let ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_SIGN)) else { return nil }
        defer { secp256k1_context_destroy(ctx) }

        var seed = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, 32, &seed) == errSecSuccess {
            _ = secp256k1_context_randomize(ctx, seed)
        }

        var sig = secp256k1_ecdsa_recoverable_signature()
        let hashBytes = [UInt8](hash32)
        let keyBytes = [UInt8](privateKey)

        guard secp256k1_ecdsa_sign_recoverable(ctx, &sig, hashBytes, keyBytes, nil, nil) == 1 else { return nil }

        var output = [UInt8](repeating: 0, count: 64)
        var recid: Int32 = 0
        guard secp256k1_ecdsa_recoverable_signature_serialize_compact(ctx, &output, &recid, &sig) == 1 else { return nil }

        return RecoverableSignature(r: Array(output[0..<32]), s: Array(output[32..<64]), recid: Int(recid))
    }

    /// Produces a 65-byte `r ‖ s ‖ v` signature hex string ("0x…") for the given hash,
    /// where `v = recid + 27` (the Ethereum convention for personal_sign / typed-data).
    static func signedHex65(hash32: Data, privateKey: Data) -> String? {
        guard let sig = sign(hash32: hash32, privateKey: privateKey) else { return nil }
        var bytes = [UInt8]()
        bytes.append(contentsOf: leftPad32(sig.r))
        bytes.append(contentsOf: leftPad32(sig.s))
        bytes.append(UInt8(sig.recid + 27))
        return "0x" + bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func leftPad32(_ bytes: [UInt8]) -> [UInt8] {
        bytes.count >= 32 ? bytes : [UInt8](repeating: 0, count: 32 - bytes.count) + bytes
    }
}
