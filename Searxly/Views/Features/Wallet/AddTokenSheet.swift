//
//  AddTokenSheet.swift
//  Searxly
//
//  Lets the user import any ERC-20 token on Base by entering its contract address.
//

import SwiftUI

struct AddTokenSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var wallet = WalletManager.shared

    @State private var contractAddress = ""
    @State private var symbol = ""
    @State private var name = ""
    @State private var decimalsText = "18"
    @State private var error = ""

    private var isValidAddress: Bool {
        let a = contractAddress.trimmingCharacters(in: .whitespaces)
        return a.hasPrefix("0x") && a.count == 42
    }

    private var canAdd: Bool {
        isValidAddress && !symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(decimalsText) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Custom Token")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Base L2 · ERC-20")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Divider().opacity(0.1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    field(label: "Contract Address",
                          placeholder: "0x...",
                          text: $contractAddress,
                          isMonospaced: true,
                          hint: isValidAddress ? nil : (contractAddress.isEmpty ? nil : "Must start with 0x and be 42 characters"),
                          hintIsError: true)

                    field(label: "Token Symbol",
                          placeholder: "e.g. USDC",
                          text: $symbol)

                    field(label: "Token Name",
                          placeholder: "e.g. USD Coin",
                          text: $name)

                    field(label: "Decimals",
                          placeholder: "18",
                          text: $decimalsText,
                          hint: "Most ERC-20 tokens use 18 decimals")

                    // Copy-your-token helper
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text("Find your token's details on Basescan: search the contract address and look for Token Tracker → Symbol / Decimals.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

                    if !error.isEmpty {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 1, green: 0.33, blue: 0.33))
                    }

                    HStack(spacing: 12) {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)

                        Spacer()

                        Button("Add Token") { addToken() }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(.black)
                            .controlSize(.regular)
                            .disabled(!canAdd)
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 400)
        .background(WalletTheme.canvas)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func field(
        label: String,
        placeholder: String,
        text: Binding<String>,
        isMonospaced: Bool = false,
        hint: String? = nil,
        hintIsError: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: isMonospaced ? .monospaced : .default))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.8)
                )

            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(hintIsError ? Color(red: 1, green: 0.33, blue: 0.33) : Color.secondary)
            }
        }
    }

    private func addToken() {
        let addr = contractAddress.trimmingCharacters(in: .whitespaces)
        let sym  = symbol.trimmingCharacters(in: .whitespaces)
        let nm   = name.trimmingCharacters(in: .whitespaces)
        guard let decimals = Int(decimalsText) else { error = "Invalid decimals"; return }

        if wallet.tokens.contains(where: { $0.contractAddress?.lowercased() == addr.lowercased() }) {
            error = "This token is already in your wallet."
            return
        }

        wallet.addCustomToken(contractAddress: addr, symbol: sym, name: nm, decimals: decimals)
        dismiss()
    }
}
