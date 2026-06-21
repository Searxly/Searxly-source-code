//
//  PasswordsSettingsView.swift
//  Searxly
//

import SwiftUI

struct PasswordsSettingsView: View {
    var onOpenVault: () -> Void = {}

    private var vault = PasswordVaultManager.shared
    private var lockManager = VaultLockManager.shared

    @State private var passphraseSheetMode: VaultPassphraseSetupSheet.Mode?
    @State private var showingPassphraseSheet = false

    var body: some View {
        SettingsPane {
            SettingsPaneHeader(
                title: Localization.string("passwords_title", defaultValue: "Passwords"),
                subtitle: "Save logins on this Mac, fill them in the browser, and manage everything in the vault."
            )

            SettingsSection(title: "Vault") {
                SettingsProminentAction(
                    title: "Open Password Vault",
                    systemImage: "key.fill",
                    action: onOpenVault
                )

                SettingsDivider()

                HStack {
                    Label("Saved logins", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(savedLoginCountLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Text("Open the vault to add, edit, or remove saved credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsSection(
                title: "Autofill",
                footer: "Searxly uses lightweight page detection — not macOS system autofill. Saved passwords never leave this device."
            ) {
                SettingsToggleRow(
                    title: "Autofill saved logins",
                    description: "Fill username and password fields when you choose a saved login from the vault or toolbar.",
                    isOn: Binding(
                        get: { vault.autofillEnabled },
                        set: { vault.autofillEnabled = $0 }
                    )
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Offer to save new logins",
                    description: "Detect sign-in and sign-up pages and remind you to save credentials for this site.",
                    isOn: Binding(
                        get: { vault.offerToSaveEnabled },
                        set: { vault.offerToSaveEnabled = $0 }
                    )
                )

                SettingsDivider()

                SettingsToggleRow(
                    title: "Suggest strong passwords",
                    description: "Let the key icon in the toolbar generate and fill a strong password on signup pages.",
                    isOn: Binding(
                        get: { vault.suggestPasswordsEnabled },
                        set: { vault.suggestPasswordsEnabled = $0 }
                    )
                )

                if vault.suggestPasswordsEnabled {
                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Copy generated passwords",
                        description: "Also copy newly generated passwords to the clipboard (auto-clears after 45 seconds).",
                        isOn: Binding(
                            get: { vault.copyGeneratedToClipboard },
                            set: { vault.copyGeneratedToClipboard = $0 }
                        )
                    )
                }
            }

            SettingsSection(
                title: "Vault security",
                footer: "Passwords are stored in the macOS Keychain. Copied passwords auto-clear from the clipboard after 45 seconds and when the vault locks."
            ) {
                if lockManager.useCustomPassphrase {
                    HStack {
                        Label("Vault passphrase", systemImage: "lock.fill")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text("Enabled")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    SettingsDivider()

                    SettingsProminentAction(
                        title: "Change Vault Passphrase",
                        systemImage: "arrow.triangle.2.circlepath",
                        action: { presentPassphraseSheet(.change) }
                    )

                    SettingsDivider()

                    Button("Remove Vault Passphrase") {
                        presentPassphraseSheet(.disable)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.vertical, 6)
                } else {
                    SettingsProminentAction(
                        title: "Set Vault Passphrase",
                        systemImage: "lock.fill",
                        action: { presentPassphraseSheet(.enable) }
                    )

                    Text("Optional: require a passphrase instead of Touch ID to unlock the vault.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SettingsDivider()

                SettingsPickerRow(
                    title: "Lock vault after",
                    description: "Require authentication again after this period of inactivity inside the vault.",
                    selection: Binding(
                        get: { vault.autoLockMinutes },
                        set: { vault.autoLockMinutes = $0 }
                    )
                ) {
                    Picker("", selection: Binding(
                        get: { vault.autoLockMinutes },
                        set: { vault.autoLockMinutes = $0 }
                    )) {
                        Text("Never").tag(0)
                        Text("1 minute").tag(1)
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            SettingsCallout(
                title: "On-device only",
                message: "Saved passwords stay in the macOS Keychain on this Mac. They are never synced to Searxly servers.",
                tint: .secondary,
                systemImage: "lock.shield"
            )
        }
        .onAppear {
            vault.reloadFromPersistence()
        }
        .sheet(isPresented: $showingPassphraseSheet) {
            if let mode = passphraseSheetMode {
                VaultPassphraseSetupSheet(
                    mode: mode,
                    onCancel: { showingPassphraseSheet = false },
                    onComplete: {
                        showingPassphraseSheet = false
                        vault.reloadFromPersistence()
                    }
                )
            }
        }
    }

    private func presentPassphraseSheet(_ mode: VaultPassphraseSetupSheet.Mode) {
        passphraseSheetMode = mode
        showingPassphraseSheet = true
    }

    private var savedLoginCountLabel: String {
        switch vault.savedLoginCount {
        case 0: return "None yet"
        case 1: return "1 login"
        default: return "\(vault.savedLoginCount) logins"
        }
    }
}