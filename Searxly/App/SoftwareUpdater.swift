//
//  SoftwareUpdater.swift
//  Searxly
//
//  Sparkle-backed signed auto-updates. Instantiating this (with `startingUpdater: true`) begins
//  automatic background checks against the `SUFeedURL` in Info.plist, and every downloaded update is
//  verified against the bundled `SUPublicEDKey` before it's allowed to install. The matching PRIVATE
//  signing key never ships — it lives only in the developer's login Keychain — so a tampered or
//  MITM'd update is rejected. This is what stops "replace the whole app" supply-chain attacks.
//

import Foundation
import Sparkle

final class SoftwareUpdater {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// User-initiated check (the "Check for Updates…" menu item).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
}
