//
//  EncryptionRecoveryView.swift
//  Searxly
//
//  Blocking full-screen recovery when encrypted AppData.json cannot be read.
//  Offers recovery-code import or restore from an encrypted .searxlybackup file.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct EncryptionRecoveryView: View {
    var glassEnabled: Bool = true
    var toolbarMaterial: Material = .ultraThinMaterial

    @Environment(\.colorScheme) private var colorScheme

    @State private var recoveryCode = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showingBackupPasswordPrompt = false
    @State private var backupPassword = ""
    @State private var pendingBackupURL: URL?

    @State private var recoveryManager = EncryptionRecoveryManager.shared

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color(nsColor: .windowBackgroundColor))
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.orange)

                VStack(spacing: 8) {
                    Text("Unlock your encrypted data")
                        .font(.title2.weight(.semibold))

                    Text("Searxly cannot read your encrypted local data. Enter your recovery code or restore from a backup file.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let hint = recoveryManager.errorMessage {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecureField("Recovery code", text: $recoveryCode)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: 420)

                Button {
                    attemptRecoveryCode()
                } label: {
                    Text(isWorking ? "Unlocking…" : "Unlock with recovery code")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(recoveryCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)

                HStack {
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                }
                .frame(maxWidth: 420)

                Button {
                    pickBackupFile()
                } label: {
                    Label("Restore from backup file…", systemImage: "arrow.counterclockwise.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }

                Text("Your encrypted data file was not modified. Without a valid recovery code or backup, your history and settings cannot be read.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            .padding(32)
            .frame(maxWidth: 480)
            .background(cardSurface)
            .overlay(cardBorder)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 24, y: 10)
        }
        .sheet(isPresented: $showingBackupPasswordPrompt) {
            BackupPasswordSheet(
                isRestore: true,
                password: $backupPassword,
                onCancel: {
                    showingBackupPasswordPrompt = false
                    pendingBackupURL = nil
                    backupPassword = ""
                },
                onConfirm: {
                    performBackupRestore()
                }
            )
        }
    }

    @ViewBuilder
    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        if glassEnabled {
            shape.fill(toolbarMaterial)
        } else {
            shape.fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
    }

    private func attemptRecoveryCode() {
        isWorking = true
        errorMessage = nil

        let success = recoveryManager.recoverWithRecoveryCode(recoveryCode)
        if !success {
            errorMessage = "That recovery code did not unlock your data. Check the code and try again, or restore from a backup."
        }
        isWorking = false
    }

    private func pickBackupFile() {
        let panel = NSOpenPanel()
        panel.title = "Restore from Encrypted Backup"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            pendingBackupURL = url
            backupPassword = ""
            showingBackupPasswordPrompt = true
        }
    }

    private func performBackupRestore() {
        guard let url = pendingBackupURL, !backupPassword.isEmpty else { return }

        isWorking = true
        errorMessage = nil

        do {
            try recoveryManager.recoverFromBackup(at: url, password: backupPassword)
            pendingBackupURL = nil
            backupPassword = ""
            showingBackupPasswordPrompt = false
        } catch {
            errorMessage = error.localizedDescription
        }

        isWorking = false
    }
}