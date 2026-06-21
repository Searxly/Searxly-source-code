//
//  WeiConverter.swift
//  Searxly
//
//  Exact conversion of human token amounts → integer base units (wei / smallest unit)
//  as a big-endian byte array, using decimal-string arithmetic to avoid float loss.
//

import Foundation

enum WeiConverter {

    /// Converts a decimal token amount to its integer base-unit big-endian byte array.
    /// e.g. amount = 1.5, decimals = 18  →  1500000000000000000 (as bytes)
    static func baseUnitBytes(amount: Decimal, decimals: Int) -> [UInt8] {
        let intString = baseUnitDecimalString(amount: amount, decimals: decimals)
        return decimalStringToBytes(intString)
    }

    /// Returns the integer base-unit value as a plain decimal string.
    static func baseUnitDecimalString(amount: Decimal, decimals: Int) -> String {
        // Use the plain (non-scientific) string form of the Decimal.
        var amt = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &amt, decimals, .down)

        let str = "\(rounded)"
        let parts = str.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intPart = String(parts[0])
        var fracPart = parts.count > 1 ? String(parts[1]) : ""

        // Pad or trim fractional part to exactly `decimals` digits
        if fracPart.count < decimals {
            fracPart += String(repeating: "0", count: decimals - fracPart.count)
        } else if fracPart.count > decimals {
            fracPart = String(fracPart.prefix(decimals))
        }

        var combined = (intPart == "0" ? "" : intPart) + fracPart
        // Strip leading zeros
        while combined.first == "0" { combined.removeFirst() }
        return combined.isEmpty ? "0" : combined
    }

    /// Converts a non-negative decimal integer string to a minimal big-endian byte array.
    /// Schoolbook division of the decimal digits by 256.
    static func decimalStringToBytes(_ decimalString: String) -> [UInt8] {
        var digits = decimalString.compactMap { $0.wholeNumberValue }
        guard !digits.isEmpty else { return [] }

        var bytes = [UInt8]()
        while !(digits.count == 1 && digits[0] == 0) {
            var remainder = 0
            var quotient = [Int]()
            for d in digits {
                let acc = remainder * 10 + d
                quotient.append(acc / 256)
                remainder = acc % 256
            }
            bytes.insert(UInt8(remainder), at: 0)
            // Strip leading zeros from quotient
            while quotient.count > 1 && quotient.first == 0 { quotient.removeFirst() }
            digits = quotient
            if quotient.count == 1 && quotient[0] == 0 { break }
        }
        return bytes.isEmpty ? [0] : bytes
    }
}
