//
//  EthereumMessageSigner.swift
//  Searxly
//
//  Off-chain message signing for dApp requests:
//   - personal_sign (EIP-191)
//   - eth_signTypedData_v4 (EIP-712)
//  Both produce a 65-byte r‖s‖v hex signature (v = recid + 27).
//

import Foundation

enum EthereumMessageSigner {

    // MARK: - personal_sign (EIP-191)

    /// `message` may be a 0x-hex string (decoded to bytes) or a plain UTF-8 string.
    static func personalSign(message: String, privateKey: Data) -> String? {
        let msg = decodeMessageBytes(message)
        var preimage = Data("\u{19}Ethereum Signed Message:\n\(msg.count)".utf8)
        preimage.append(msg)
        let digest = Keccak256.hash(preimage)
        return EthereumSigner.signedHex65(hash32: digest, privateKey: privateKey)
    }

    /// The exact digest personal_sign signs — exposed for preview/verification.
    static func personalSignDigest(message: String) -> Data {
        let msg = decodeMessageBytes(message)
        var preimage = Data("\u{19}Ethereum Signed Message:\n\(msg.count)".utf8)
        preimage.append(msg)
        return Keccak256.hash(preimage)
    }

    private static func decodeMessageBytes(_ message: String) -> Data {
        if message.hasPrefix("0x") { return RLP.dataFromHex(message) }
        return Data(message.utf8)
    }

    // MARK: - eth_signTypedData_v4 (EIP-712)

    static func signTypedDataV4(json: String, privateKey: Data) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return signTypedDataV4(typedData: obj, privateKey: privateKey)
    }

    static func signTypedDataV4(typedData: [String: Any], privateKey: Data) -> String? {
        guard let digest = typedDataDigest(typedData) else { return nil }
        return EthereumSigner.signedHex65(hash32: digest, privateKey: privateKey)
    }

    /// The EIP-712 digest: keccak256(0x19 0x01 ‖ domainSeparator ‖ hashStruct(primaryType, message)).
    static func typedDataDigest(_ typedData: [String: Any]) -> Data? {
        // Parse leniently: JSONSerialization yields NSArray/NSDictionary, so deep generic casts
        // like [String: [[String: Any]]] are unreliable. Cast one level at a time.
        guard let typesRaw = typedData["types"] as? [String: Any],
              let primaryType = typedData["primaryType"] as? String
        else { return nil }

        // Normalize types to [String: [(name,type)]]
        var types: [String: [(name: String, type: String)]] = [:]
        for (k, v) in typesRaw {
            let fields = (v as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
            types[k] = fields.compactMap { f in
                guard let n = f["name"] as? String, let t = f["type"] as? String else { return nil }
                return (n, t)
            }
        }

        let domain = (typedData["domain"] as? [String: Any]) ?? [:]
        let message = (typedData["message"] as? [String: Any]) ?? [:]

        guard let domainSep = hashStruct("EIP712Domain", domain, types),
              let messageHash = hashStruct(primaryType, message, types)
        else { return nil }

        var preimage = Data([0x19, 0x01])
        preimage.append(domainSep)
        preimage.append(messageHash)
        return Keccak256.hash(preimage)
    }

    // MARK: - EIP-712 encoding

    private static func hashStruct(_ primaryType: String, _ data: [String: Any],
                                   _ types: [String: [(name: String, type: String)]]) -> Data? {
        guard let encoded = encodeData(primaryType, data, types) else { return nil }
        return Keccak256.hash(encoded)
    }

    private static func encodeData(_ primaryType: String, _ data: [String: Any],
                                   _ types: [String: [(name: String, type: String)]]) -> Data? {
        guard let fields = types[primaryType] else { return nil }
        var result = Data()
        result.append(typeHash(primaryType, types))   // 32 bytes
        for field in fields {
            guard let enc = encodeValue(field.type, data[field.name] ?? NSNull(), types) else { return nil }
            result.append(enc)
        }
        return result
    }

    private static func encodeValue(_ type: String, _ value: Any,
                                    _ types: [String: [(name: String, type: String)]]) -> Data? {
        // Arrays: keccak256(concat(encodeValue(base, element)))
        if type.hasSuffix("]") {
            guard let arr = value as? [Any] else { return nil }
            let base = String(type[..<type.lastIndex(of: "[")!])
            var concat = Data()
            for el in arr {
                guard let enc = encodeValue(base, el, types) else { return nil }
                concat.append(enc)
            }
            return Keccak256.hash(concat)
        }

        // Custom struct type
        if types[type] != nil {
            guard let dict = value as? [String: Any], let enc = encodeData(type, dict, types) else { return nil }
            return Keccak256.hash(enc)
        }

        switch type {
        case "string":
            let s = (value as? String) ?? ""
            return Keccak256.hash(Data(s.utf8))
        case "bytes":
            let bytes = (value as? String).map { RLP.dataFromHex($0) } ?? Data()
            return Keccak256.hash(bytes)
        case "bool":
            let b = (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
            return pad32(left: [b ? 1 : 0])
        case "address":
            let addr = RLP.dataFromHex((value as? String) ?? "0x")
            return pad32(left: Array(addr.suffix(20)))
        default:
            if type.hasPrefix("uint") || type.hasPrefix("int") {
                return pad32(left: uintBytes(value))
            }
            if type.hasPrefix("bytes") {  // fixed bytesN — right-padded
                let bytes = (value as? String).map { RLP.dataFromHex($0) } ?? Data()
                return pad32(right: Array(bytes))
            }
            return nil
        }
    }

    // encodeType + typeHash

    private static func typeHash(_ primaryType: String,
                                 _ types: [String: [(name: String, type: String)]]) -> Data {
        Keccak256.hash(Data(encodeType(primaryType, types).utf8))
    }

    private static func encodeType(_ primaryType: String,
                                   _ types: [String: [(name: String, type: String)]]) -> String {
        var deps = collectDependencies(primaryType, types, found: [])
        deps.remove(primaryType)
        let ordered = [primaryType] + deps.sorted()
        return ordered.map { t in
            let fields = types[t] ?? []
            let inner = fields.map { "\($0.type) \($0.name)" }.joined(separator: ",")
            return "\(t)(\(inner))"
        }.joined()
    }

    private static func collectDependencies(_ type: String,
                                            _ types: [String: [(name: String, type: String)]],
                                            found: Set<String>) -> Set<String> {
        var result = found
        let base = type.hasSuffix("]") ? String(type[..<type.firstIndex(of: "[")!]) : type
        guard types[base] != nil, !result.contains(base) else { return result }
        result.insert(base)
        for field in types[base] ?? [] {
            result = collectDependencies(field.type, types, found: result)
        }
        return result
    }

    // MARK: - Helpers

    /// Encodes an integer value (decimal string, hex string, or NSNumber) to minimal big-endian bytes.
    private static func uintBytes(_ value: Any) -> [UInt8] {
        if let s = value as? String {
            if s.hasPrefix("0x") { return Array(RLP.dataFromHex(s)) }
            return WeiConverter.decimalStringToBytes(s)
        }
        if let n = value as? NSNumber {
            return WeiConverter.decimalStringToBytes(n.stringValue)
        }
        return [0]
    }

    private static func pad32(left bytes: [UInt8]) -> Data {
        let b = Array(bytes.suffix(32))
        return Data([UInt8](repeating: 0, count: 32 - b.count) + b)
    }

    private static func pad32(right bytes: [UInt8]) -> Data {
        let b = Array(bytes.prefix(32))
        return Data(b + [UInt8](repeating: 0, count: 32 - b.count))
    }
}
