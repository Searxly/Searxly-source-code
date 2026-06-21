//
//  PasswordEntryEditorSheet.swift
//  Searxly
//

import SwiftUI

struct PasswordEntryEditorSheet: View {
    enum Mode {
        case add
        case edit(PasswordVaultEntry)

        var title: String {
            switch self {
            case .add: return "Add Login"
            case .edit: return "Edit Login"
            }
        }

        var confirmLabel: String {
            switch self {
            case .add: return "Save Login"
            case .edit: return "Save Changes"
            }
        }
    }

    let mode: Mode
    var initialDomain: String = ""
    var initialUsername: String = ""
    var initialPassword: String = ""
    var initialNotes: String = ""
    let onCancel: () -> Void
    let onSaved: () -> Void

    @State private var domain: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var notes: String = ""
    @State private var showPassword = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var vault = PasswordVaultManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(mode.title)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 14) {
                labeledField("Website", prompt: "example.com") {
                    TextField("example.com", text: $domain)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Username or email") {
                    TextField("username@example.com", text: $username)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField("Password") {
                    HStack(spacing: 8) {
                        Group {
                            if showPassword {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textFieldStyle(.roundedBorder)

                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(showPassword ? "Hide password" : "Show password")

                        Button("Generate") {
                            Task {
                                password = await vault.suggestPasswordWithAI(for: domain)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                labeledField("Notes (optional)") {
                    TextField("Recovery codes, hints…", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(mode.confirmLabel) {
                    save()
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || domain.trimmingCharacters(in: .whitespaces).isEmpty || username.isEmpty || password.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 440)
        .onAppear {
            domain = initialDomain
            username = initialUsername
            password = initialPassword
            notes = initialNotes

            if case .edit(let entry) = mode {
                domain = entry.domain
                username = entry.username
                notes = entry.notes ?? ""
                if password.isEmpty, let stored = vault.password(for: entry.id) {
                    password = stored
                }
            }
        }
    }

    @ViewBuilder
    private func labeledField<F: View>(_ title: String, prompt: String? = nil, @ViewBuilder field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            field()
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        switch mode {
        case .add:
            if vault.addEntry(domain: domain, username: username, password: password, notes: notes) != nil {
                onSaved()
            } else {
                errorMessage = "Could not save login. Check your entries and try again."
                isSaving = false
            }

        case .edit(let entry):
            if vault.updateEntry(id: entry.id, domain: domain, username: username, password: password, notes: notes) {
                onSaved()
            } else {
                errorMessage = "Could not update login."
                isSaving = false
            }
        }
    }
}