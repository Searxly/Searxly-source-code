//
//  LedgerEthereum.swift
//  Searxly
//
//  Ledger hardware-wallet protocol for the Ethereum app — the device-independent, fully testable
//  core: BIP-32 path encoding, the Ethereum-app APDU commands (get address / sign tx / sign message),
//  response parsing, and the USB-HID packet framing. None of this touches the device; it turns
//  intentions into the exact bytes the device expects, and parses the exact bytes it returns.
//
//  The actual USB transport (IOKit HID open/read/write) is the one piece that needs a physical
//  Ledger and the `com.apple.security.device.usb` entitlement to implement and test — it lives behind
//  the `LedgerTransport` protocol below. `UnavailableLedgerTransport` is the honest default until a
//  device-enabled build provides a real one.
//

import Foundation

enum LedgerError: Error, Equatable {
    case badPath
    case badResponse
    case notConnected
    case deviceError(UInt16)      // a non-0x9000 status word from the device
    case userRejected             // 0x6985
}

// MARK: - BIP-32 path

enum LedgerPath {
    /// Encodes a derivation path (e.g. "m/44'/60'/0'/0/0") as Ledger expects it:
    /// 1 length byte + 4 big-endian bytes per level (hardened levels have the high bit set).
    static func encode(_ path: String) throws -> Data {
        var comps = path.split(separator: "/").map(String.init)
        if comps.first?.lowercased() == "m" { comps.removeFirst() }
        guard !comps.isEmpty, comps.count <= 10 else { throw LedgerError.badPath }
        var out = Data([UInt8(comps.count)])
        for var c in comps {
            var hardened: UInt32 = 0
            if let last = c.last, last == "'" || last == "h" || last == "H" {
                hardened = 0x8000_0000; c.removeLast()
            }
            guard let n = UInt32(c), n < 0x8000_0000 else { throw LedgerError.badPath }
            let v = n | hardened
            out.append(UInt8((v >> 24) & 0xff)); out.append(UInt8((v >> 16) & 0xff))
            out.append(UInt8((v >> 8) & 0xff));  out.append(UInt8(v & 0xff))
        }
        return out
    }
}

// MARK: - APDU commands (Ethereum app, CLA 0xe0)

enum LedgerAPDU {
    static let cla: UInt8 = 0xe0
    static let insGetAddress: UInt8 = 0x02
    static let insSignTx: UInt8 = 0x04
    static let insSignPersonal: UInt8 = 0x08

    /// GET_ETH_ADDRESS — derive an address. `display` asks the device to show it for confirmation.
    static func getAddress(path: String, display: Bool = false, chainCode: Bool = false) throws -> Data {
        let p = try LedgerPath.encode(path)
        var apdu = Data([cla, insGetAddress, display ? 0x01 : 0x00, chainCode ? 0x01 : 0x00, UInt8(p.count)])
        apdu.append(p)
        return apdu
    }

    /// SIGN_TX — `rawUnsignedTx` is the serialized unsigned transaction (for EIP-1559 it includes the
    /// 0x02 type prefix). Returns one or more chunked APDUs (the path leads the first chunk).
    static func signTransaction(path: String, rawUnsignedTx: Data) throws -> [Data] {
        var payload = try LedgerPath.encode(path)
        payload.append(rawUnsignedTx)
        return chunk(payload, ins: insSignTx)
    }

    /// SIGN_PERSONAL_MESSAGE (EIP-191) — payload is path || uint32(BE) message length || message.
    static func signPersonalMessage(path: String, message: Data) throws -> [Data] {
        var payload = try LedgerPath.encode(path)
        let len = UInt32(message.count)
        payload.append(UInt8((len >> 24) & 0xff)); payload.append(UInt8((len >> 16) & 0xff))
        payload.append(UInt8((len >> 8) & 0xff));  payload.append(UInt8(len & 0xff))
        payload.append(message)
        return chunk(payload, ins: insSignPersonal)
    }

    /// Splits a payload into ≤255-byte APDUs. First chunk P1=0x00, continuations P1=0x80.
    static func chunk(_ payload: Data, ins: UInt8) -> [Data] {
        let bytes = [UInt8](payload)
        var apdus: [Data] = []
        var offset = 0
        var first = true
        repeat {
            let len = min(255, bytes.count - offset)
            var apdu = Data([cla, ins, first ? 0x00 : 0x80, 0x00, UInt8(len)])
            if len > 0 { apdu.append(contentsOf: bytes[offset..<offset + len]) }
            apdus.append(apdu)
            offset += len
            first = false
        } while offset < bytes.count
        return apdus
    }

    // MARK: - Response parsing

    /// Parses a GET_ADDRESS response: [pubkeyLen][pubkey][addrLen][address ASCII (40 hex, no 0x)]…
    static func parseAddress(_ resp: Data) throws -> String {
        let b = [UInt8](resp)
        guard b.count > 1 else { throw LedgerError.badResponse }
        let pubLen = Int(b[0])
        var i = 1 + pubLen
        guard i < b.count else { throw LedgerError.badResponse }
        let addrLen = Int(b[i]); i += 1
        guard i + addrLen <= b.count else { throw LedgerError.badResponse }
        guard let ascii = String(bytes: b[i..<i + addrLen], encoding: .ascii) else { throw LedgerError.badResponse }
        return "0x" + ascii.lowercased()
    }

    /// Parses a signature response (`v` 1 byte, `r` 32, `s` 32) into a 65-byte r‖s‖v hex string.
    static func parseSignature(_ resp: Data) throws -> String {
        let b = [UInt8](resp)
        guard b.count >= 65 else { throw LedgerError.badResponse }
        let v = b[0], r = Array(b[1..<33]), s = Array(b[33..<65])
        return "0x" + (r + s + [v]).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - USB-HID packet framing

/// Ledger's HID transport wraps each APDU in 64-byte packets: a 5-byte header
/// (channel:2, tag:0x05, seq:2), with the first packet also carrying a 2-byte total length, then the
/// payload zero-padded to the packet size. This is pure byte-shuffling — fully testable offline.
enum LedgerHID {
    static let tag: UInt8 = 0x05
    static let packetSize = 64

    static func frame(_ apdu: Data, channel: UInt16 = 0x0101) -> [Data] {
        let bytes = [UInt8](apdu)
        let total = bytes.count
        var packets: [Data] = []
        var offset = 0
        var seq: UInt16 = 0
        repeat {
            var p = Data([UInt8(channel >> 8), UInt8(channel & 0xff), tag, UInt8(seq >> 8), UInt8(seq & 0xff)])
            if seq == 0 { p.append(UInt8(total >> 8)); p.append(UInt8(total & 0xff)) }
            let cap = packetSize - p.count
            let take = min(cap, total - offset)
            if take > 0 { p.append(contentsOf: bytes[offset..<offset + take]); offset += take }
            if p.count < packetSize { p.append(Data(repeating: 0, count: packetSize - p.count)) }
            packets.append(p)
            seq &+= 1
        } while offset < total
        return packets
    }

    /// Reassembles a full response APDU from its HID packets (strips headers, honors the length prefix).
    static func unframe(_ packets: [Data]) throws -> Data {
        var result = Data()
        var expected = -1
        var seq = 0
        for pkt in packets {
            let b = [UInt8](pkt)
            guard b.count >= 5 else { throw LedgerError.badResponse }
            var i = 5
            if seq == 0 {
                guard b.count >= 7 else { throw LedgerError.badResponse }
                expected = Int(b[5]) << 8 | Int(b[6]); i = 7
            }
            guard expected >= 0 else { throw LedgerError.badResponse }
            let take = min(expected - result.count, b.count - i)
            if take > 0 { result.append(contentsOf: b[i..<i + take]) }
            seq += 1
            if result.count >= expected { break }
        }
        guard result.count == expected else { throw LedgerError.badResponse }
        return result
    }

    /// Splits a device response into its status word and data: response = data ‖ SW(2 bytes).
    static func splitStatus(_ resp: Data) throws -> (data: Data, sw: UInt16) {
        guard resp.count >= 2 else { throw LedgerError.badResponse }
        let b = [UInt8](resp)
        let sw = UInt16(b[b.count - 2]) << 8 | UInt16(b[b.count - 1])
        return (resp.prefix(resp.count - 2), sw)
    }
}

// MARK: - Transport seam

/// The device I/O boundary. A real implementation opens the Ledger over IOKit HID and exchanges
/// framed packets. Kept abstract so the protocol core above stays testable without hardware.
protocol LedgerTransport {
    /// Sends one APDU (framed internally) and returns the raw response APDU including its status word.
    func exchange(_ apdu: Data) async throws -> Data
    var isConnected: Bool { get }
}

/// The default until a device-enabled build ships the IOKit HID transport. Every call fails clearly
/// rather than pretending a Ledger is attached.
struct UnavailableLedgerTransport: LedgerTransport {
    var isConnected: Bool { false }
    func exchange(_ apdu: Data) async throws -> Data { throw LedgerError.notConnected }
}

// MARK: - High-level operations

/// Orchestrates the APDUs above over a `LedgerTransport`. The byte-building and parsing are tested;
/// the end-to-end path is exercised once a real transport is attached to a device.
enum LedgerEthereum {
    private static func send(_ apdu: Data, over t: LedgerTransport) async throws -> Data {
        let resp = try await t.exchange(apdu)
        let (data, sw) = try LedgerHID.splitStatus(resp)
        switch sw {
        case 0x9000: return data
        case 0x6985: throw LedgerError.userRejected
        default:     throw LedgerError.deviceError(sw)
        }
    }

    static func getAddress(path: String, display: Bool = false, over t: LedgerTransport) async throws -> String {
        let data = try await send(try LedgerAPDU.getAddress(path: path, display: display), over: t)
        return try LedgerAPDU.parseAddress(data)
    }

    /// Signs an unsigned EIP-1559 tx and returns a 65-byte r‖s‖v signature hex.
    static func signTransaction(path: String, rawUnsignedTx: Data, over t: LedgerTransport) async throws -> String {
        var last = Data()
        for apdu in try LedgerAPDU.signTransaction(path: path, rawUnsignedTx: rawUnsignedTx) {
            last = try await send(apdu, over: t)
        }
        return try LedgerAPDU.parseSignature(last)
    }

    static func signPersonalMessage(path: String, message: Data, over t: LedgerTransport) async throws -> String {
        var last = Data()
        for apdu in try LedgerAPDU.signPersonalMessage(path: path, message: message) {
            last = try await send(apdu, over: t)
        }
        return try LedgerAPDU.parseSignature(last)
    }
}
