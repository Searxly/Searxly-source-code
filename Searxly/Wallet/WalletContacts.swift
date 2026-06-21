//
//  WalletContacts.swift
//  Searxly
//
//  A simple address book of saved recipients. Who you pay is private, so contacts are kept
//  encrypted + device-only in the Keychain. Saving a recipient as a contact also makes the
//  Send screen recognise the address and show the name, reducing paste mistakes.
//

import Foundation
import Observation

struct WalletContact: Codable, Identifiable, Equatable {
    let address: String
    var label: String

    var id: String { address.lowercased() }
    var shortAddress: String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}

@MainActor
@Observable
final class WalletContactsStore {
    static let shared = WalletContactsStore()

    private(set) var contacts: [WalletContact] = []

    private init() { contacts = WalletKeychain.loadContacts() }

    func label(for address: String) -> String? {
        contacts.first { $0.id == address.lowercased() }?.label
    }

    func isSaved(_ address: String) -> Bool {
        contacts.contains { $0.id == address.lowercased() }
    }

    func add(address: String, label: String) {
        let addr = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard addr.hasPrefix("0x"), addr.count == 42 else { return }
        let name = label.trimmingCharacters(in: .whitespaces)
        contacts.removeAll { $0.id == addr.lowercased() }
        contacts.insert(WalletContact(address: addr, label: name.isEmpty ? shortened(addr) : name), at: 0)
        WalletKeychain.saveContacts(contacts)
    }

    func remove(id: String) {
        contacts.removeAll { $0.id == id }
        WalletKeychain.saveContacts(contacts)
    }

    private func shortened(_ a: String) -> String { a.count > 10 ? "\(a.prefix(6))…\(a.suffix(4))" : a }
}
