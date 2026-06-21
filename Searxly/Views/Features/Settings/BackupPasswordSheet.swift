//
//  BackupPasswordSheet.swift
//  Searxly
//
//  Extracted + polished from the inline .sheet in SettingsView during the complete settings UI rework.
//  Self-contained, minimal, consistent with premium dark/material aesthetic.
//  Used for both encrypted backup creation and restore (conditional title + button label).
//  Host remains in SettingsView (owns the @State + perform* methods for now).
//

import SwiftUI

struct BackupPasswordSheet: View {
    let isRestore: Bool
    @Binding var password: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(isRestore ? "Enter Backup Password" : "Encrypt Backup with Password")
                    .font(.headline)

                Text(isRestore
                     ? "Enter the password used when this backup was created."
                     : "Choose a strong password. This encrypts your entire local data (optionally including the recovery key). Store it safely.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField(isRestore ? "Backup password" : "Strong password", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button(isRestore ? "Restore" : "Create Backup") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
            }
        }
        .padding(32)
        .frame(width: 420)
        .background(.regularMaterial)
    }
}
