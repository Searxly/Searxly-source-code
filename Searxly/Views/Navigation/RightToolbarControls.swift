//
//  RightToolbarControls.swift
//  Searxly
//
//  Extracted the right-hand side of the main toolbar (navigation + bookmarks +
//  downloads + settings). Updated during monster views refactor (ContentView is now thin;
//  state/logic in BrowserState.swift).
//

import SwiftUI
import WebKit

struct RightToolbarControls: View {
    let activeWebView: WKWebView
    let showingWebContent: Bool
    let glassEnabled: Bool
    let toolbarMaterial: Material

    // Live navigation state (updated via KVO in WebViewRepresentable)
    let canGoBack: Bool
    let canGoForward: Bool

    @Binding var bookmarks: [BookmarkItem]
    @Binding var webPageTitle: String
    @Binding var showingBookmarks: Bool
    @Binding var showingFullHistory: Bool
    @Binding var showingDownloads: Bool
    @Binding var showingKeyboardShortcuts: Bool

    // New actions for extracted features (passed from parent to avoid global notifications)
    var onToggleReaderMode: (() -> Void)? = nil
    var onShowFind: (() -> Void)? = nil
    var onOpenLocalAIChat: (() -> Void)? = nil

    /// Optional current web domain for "Save current login" in the passwords pill.
    var currentWebDomain: String? = nil

    /// Lightweight page context for password detection (no full system autofill).
    /// Used to offer "generate password directly in the browser" when a password field is present.
    var hasPasswordFieldOnPage: Bool = false
    var isLikelySignupForm: Bool = false

    /// Callback for generating + filling a password straight into the current page.
    var onGeneratePasswordForPage: (() -> Void)? = nil

    /// Save credentials from the current page into the vault.
    var onSaveLoginFromPage: (() -> Void)? = nil

    /// Fill a saved login on the current page (domain, username, password).
    var onFillLogin: ((String, String, String) -> Void)? = nil

    /// Canonical bookmark action (preferred). Falls back to legacy direct mutation if nil (for old call sites).
    var onBookmarkCurrentPage: (() -> Void)? = nil

    var onGoBack: (() -> Void)? = nil
    var onGoForward: (() -> Void)? = nil

    private var showsNavigationControls: Bool {
        showingWebContent || canGoBack || canGoForward
    }

    var body: some View {
        HStack(spacing: 2) {
            if showsNavigationControls {
                HStack(spacing: 2) {
                    FlatIconButton(
                        systemName: "chevron.backward",
                        isEnabled: canGoBack,
                        shortcutKey: "[",
                        shortcutModifiers: .command
                    ) {
                        if let onGoBack {
                            onGoBack()
                        } else {
                            activeWebView.goBack()
                        }
                    }

                    FlatIconButton(
                        systemName: "chevron.forward",
                        isEnabled: canGoForward,
                        shortcutKey: "]",
                        shortcutModifiers: .command
                    ) {
                        if let onGoForward {
                            onGoForward()
                        } else {
                            activeWebView.goForward()
                        }
                    }

                    if showingWebContent {
                        FlatIconButton(
                            systemName: "arrow.clockwise",
                            isEnabled: true,
                            shortcutKey: "r",
                            shortcutModifiers: .command
                        ) {
                            activeWebView.reload()
                        }
                    }

                    if showingWebContent {
                    // Bookmark toggle (star) — filled when saved; tap again to remove.
                    let currentURLStr = activeWebView.url?.absoluteString
                    let isBookmarked = currentURLStr.map { BookmarkURLMatcher.contains(url: $0, in: bookmarks) } ?? false
                    FlatIconButton(
                        systemName: isBookmarked ? "star.fill" : "star",
                        isEnabled: true,
                        shortcutKey: "d",
                        shortcutModifiers: .command,
                        help: isBookmarked ? "Remove bookmark (⌘D)" : "Bookmark this page (⌘D)"
                    ) {
                        if let bm = onBookmarkCurrentPage {
                            bm()
                        } else if let urlStr = activeWebView.url?.absoluteString {
                            // Legacy direct path (keeps old call sites like legacy TopBarArea working).
                            var updated = bookmarks
                            if BookmarkURLMatcher.contains(url: urlStr, in: updated) {
                                BookmarkURLMatcher.remove(url: urlStr, from: &updated)
                            } else {
                                let title = webPageTitle.isEmpty ? (activeWebView.url?.host ?? "Untitled") : webPageTitle
                                BookmarkURLMatcher.remove(url: urlStr, from: &updated)
                                let item = BookmarkItem(url: urlStr, title: title)
                                updated.insert(item, at: 0)
                                if updated.count > 200 { updated.removeLast(updated.count - 200) }
                            }
                            bookmarks = updated
                            Persistence.saveBookmarks(updated)
                        }
                    }

                    // Reader Mode (strips ads, clutter, etc.)
                    FlatIconButton(
                        systemName: "doc.text",
                        isEnabled: true
                    ) {
                        onToggleReaderMode?()
                    }

                    // Find in Page
                    FlatIconButton(
                        systemName: "magnifyingglass",
                        isEnabled: true,
                        shortcutKey: "f",
                        shortcutModifiers: .command
                    ) {
                        onShowFind?()
                    }
                    }
                }
                .padding(.trailing, 6)
            }

            BookmarksHistoryToolbarControl(showingBookmarks: $showingBookmarks)

            // Passwords control (compact glass capsule icon + rich popover + locked state indicator).
            // Always visible because this is a core privacy feature. Compact icon form keeps the
            // header row stable on narrow windows or when App Lock adds its extra button.
            PasswordsBrowserControl(
                glassEnabled: glassEnabled,
                toolbarMaterial: toolbarMaterial,
                currentWebDomain: currentWebDomain,
                hasPasswordFieldOnPage: hasPasswordFieldOnPage,
                isLikelySignupForm: isLikelySignupForm,
                onGeneratePasswordForPage: onGeneratePasswordForPage,
                onSaveLoginFromPage: onSaveLoginFromPage,
                onFillLogin: onFillLogin
            )

            // Downloads
            FlatIconButton(systemName: "arrow.down.circle", isEnabled: true) {
                showingDownloads = true
            }

            // Keyboard shortcuts help
            FlatIconButton(systemName: "questionmark.circle", isEnabled: true) {
                showingKeyboardShortcuts = true
            }
            .keyboardShortcut("?", modifiers: .command)

            // Local AI Chat button in header
            let ai = LocalIntelligenceManager.shared
            if ai.preferences.masterEnabled && ai.preferences.chatEnabled {
                FlatIconButton(systemName: "sparkles", isEnabled: true) {
                    onOpenLocalAIChat?()
                }
                .help("Local AI Chat (⌘⌥A)")
                .keyboardShortcut("a", modifiers: [.command, .option])
            }

            // Manual App Lock button — placed last so it appears at the very right,
            // right next to the Local AI button when both are enabled.
            if AppLockManager.shared.isAppLockEnabled {
                FlatIconButton(systemName: "lock.fill", isEnabled: true) {
                    AppLockManager.shared.lock()
                }
                .help("Lock Searxly now (⌘⌥L)")
            }
        }
    }
}

// Flat icon button for header toolbar (no glassy bubble/circle).
// Clean, modern, subtle hover state only.
private struct FlatIconButton: View {
    let systemName: String
    let isEnabled: Bool

    // Optional keyboard shortcut support (for common browser shortcuts like ⌘R, ⌘[, etc.)
    // Declared before `action` so trailing closure syntax continues to work when providing shortcuts.
    var shortcutKey: KeyEquivalent? = nil
    var shortcutModifiers: EventModifiers = []
    var help: String? = nil

    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.35))
                .frame(width: 26, height: 26)
        }
        .disabled(!isEnabled)
        .buttonStyle(.plain)
        .padding(5)
        .background(
            isHovering && isEnabled
                ? Color.white.opacity(0.065)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .opacity(isEnabled ? 1.0 : 0.5)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .if(shortcutKey != nil) { view in
            view.keyboardShortcut(shortcutKey!, modifiers: shortcutModifiers)
        }
        .if(help != nil) { view in
            view.help(help!)
        }
    }
}

// Small helper to conditionally apply a modifier (keeps call sites clean)
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - PasswordsBrowserControl
struct PasswordsBrowserControl: View {
    let glassEnabled: Bool
    let toolbarMaterial: Material

    var currentWebDomain: String? = nil
    var hasPasswordFieldOnPage: Bool = false
    var isLikelySignupForm: Bool = false

    var onGeneratePasswordForPage: (() -> Void)? = nil
    var onSaveLoginFromPage: (() -> Void)? = nil
    var onFillLogin: ((String, String, String) -> Void)? = nil

    @State private var showingPopover = false
    @State private var isHovering = false

    private var vault = PasswordVaultManager.shared
    private var domainLogins: [PasswordVaultEntry] {
        guard let domain = currentWebDomain else { return [] }
        return vault.entries(forDomain: domain)
    }

    private var passwordsHelp: String {
        if domainLogins.isEmpty {
            return "Passwords"
        }
        let countLabel = domainLogins.count == 1 ? "login" : "logins"
        return "Passwords — \(domainLogins.count) saved \(countLabel) for this site"
    }

    var body: some View {
        Button {
            showingPopover = true
        } label: {
            ZStack(alignment: .topTrailing) {
                let hasReadyLogins = vault.isVaultUnlocked && !domainLogins.isEmpty
                Image(systemName: "key.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(hasReadyLogins ? Color.accentColor : Color.primary)
                    .frame(width: 26, height: 26)
                    .animation(.easeInOut(duration: 0.2), value: hasReadyLogins)

                if !domainLogins.isEmpty {
                    Circle()
                        .fill(vault.isVaultUnlocked ? Color.accentColor : Color.primary.opacity(0.55))
                        .frame(width: 6, height: 6)
                        .offset(x: 4, y: -2)
                        .animation(.easeInOut(duration: 0.2), value: vault.isVaultUnlocked)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(5)
        .background(
            isHovering
                ? Color.white.opacity(0.065)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(passwordsHelp)
        .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
            PasswordsPopoverContent(
                currentWebDomain: currentWebDomain,
                domainLogins: domainLogins,
                hasPasswordFieldOnPage: hasPasswordFieldOnPage,
                isLikelySignupForm: isLikelySignupForm,
                onGeneratePasswordForPage: onGeneratePasswordForPage,
                onSaveLoginFromPage: onSaveLoginFromPage,
                onFillLogin: onFillLogin,
                onClose: { showingPopover = false }
            )
        }
        .onAppear {
            vault.reloadFromPersistence()
        }
    }
}

private struct PasswordsPopoverContent: View {
    let currentWebDomain: String?
    let domainLogins: [PasswordVaultEntry]
    let hasPasswordFieldOnPage: Bool
    let isLikelySignupForm: Bool

    var onGeneratePasswordForPage: (() -> Void)? = nil
    var onSaveLoginFromPage: (() -> Void)? = nil
    var onFillLogin: ((String, String, String) -> Void)? = nil
    let onClose: () -> Void

    private var vault = PasswordVaultManager.shared

    @State private var passphraseInput: String = ""
    @State private var unlockError: Bool = false
    @State private var isUnlocking: Bool = false

    @State private var revealedEntryIDs: Set<UUID> = []
    @State private var revealedPasswords: [UUID: String] = [:]

    @State private var isAddingNew: Bool = false
    @State private var newUsername: String = ""
    @State private var newPassword: String = ""
    @State private var showNewPassword: Bool = false

    var body: some View {
        Group {
            if !vault.isVaultUnlocked {
                lockedView
            } else if isAddingNew {
                addLoginView
            } else {
                unlockedView
            }
        }
        .frame(width: 320)
        .animation(.spring(response: 0.26, dampingFraction: 0.84), value: vault.isVaultUnlocked)
        .animation(.spring(response: 0.26, dampingFraction: 0.84), value: isAddingNew)
    }

    // MARK: - Locked

    private var lockedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverHeader(
                icon: "lock.fill",
                iconTint: Color.primary.opacity(0.55),
                iconBackground: Color.primary.opacity(0.07),
                title: "Passwords",
                subtitle: "Vault is locked"
            )

            Divider().padding(.horizontal, 12)

            VStack(spacing: 10) {
                if vault.useCustomVaultPassphrase {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Vault password")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        SecureField("Enter vault password", text: $passphraseInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await unlockWithPassphrase() } }
                    }

                    if unlockError {
                        Text("Incorrect password. Try again.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await unlockWithPassphrase() }
                    } label: {
                        HStack(spacing: 6) {
                            if isUnlocking { ProgressView().controlSize(.small) }
                            Text(isUnlocking ? "Unlocking…" : "Unlock")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(passphraseInput.isEmpty || isUnlocking)

                } else {
                    Button {
                        Task { await unlockWithBiometrics() }
                    } label: {
                        HStack(spacing: 8) {
                            if isUnlocking {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "touchid")
                                    .font(.system(size: 17))
                            }
                            Text(isUnlocking ? "Authenticating…" : "Unlock")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUnlocking)

                    if unlockError {
                        Text("Authentication failed. Try again.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider().padding(.horizontal, 12)
            openVaultRow
        }
    }

    // MARK: - Unlocked

    private var unlockedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "key.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.green.opacity(0.9))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Passwords")
                        .font(.headline)
                    if let domain = currentWebDomain {
                        Text(domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        let n = vault.savedLoginCount
                        Text("\(n) saved login\(n == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { vault.lockVault() } label: {
                    Image(systemName: "lock")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help("Lock vault")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if !domainLogins.isEmpty {
                Divider().padding(.horizontal, 12)
                Text("Saved for this site")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 2)

                VStack(spacing: 0) {
                    ForEach(domainLogins) { entry in
                        loginRow(entry)
                        if entry.id != domainLogins.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            let showGenerate = hasPasswordFieldOnPage && vault.suggestPasswordsEnabled && onGeneratePasswordForPage != nil
            let showSave = (hasPasswordFieldOnPage || isLikelySignupForm) && vault.offerToSaveEnabled && onSaveLoginFromPage != nil
            let showNewEntry = currentWebDomain != nil

            if showGenerate || showSave || showNewEntry {
                Divider().padding(.horizontal, 12)
                VStack(spacing: 1) {
                    if showGenerate {
                        actionRow(icon: "wand.and.stars", label: "Generate & fill password") {
                            onGeneratePasswordForPage?(); onClose()
                        }
                    }
                    if showSave {
                        actionRow(icon: "square.and.arrow.down", label: "Save current login") {
                            onSaveLoginFromPage?(); onClose()
                        }
                    }
                    if showNewEntry, let domain = currentWebDomain {
                        actionRow(icon: "plus.circle", label: "New login for \(domain)") {
                            newUsername = ""
                            newPassword = Self.makePassword()
                            showNewPassword = false
                            isAddingNew = true
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider().padding(.horizontal, 12)
            openVaultRow
        }
    }

    // MARK: - Add Login

    private var addLoginView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button { isAddingNew = false } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Login")
                        .font(.headline)
                    if let domain = currentWebDomain {
                        Text(domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().padding(.horizontal, 12)

            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Username or email")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("username@example.com", text: $newUsername)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Password")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            newPassword = Self.makePassword()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .medium))
                                Text("Generate")
                                    .font(.caption.weight(.medium))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                    HStack(spacing: 6) {
                        Group {
                            if showNewPassword {
                                TextField("password", text: $newPassword)
                            } else {
                                SecureField("password", text: $newPassword)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Button {
                            showNewPassword.toggle()
                        } label: {
                            Image(systemName: showNewPassword ? "eye.slash" : "eye")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    Button("Cancel") { isAddingNew = false }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Save Login") { saveNewLogin() }
                        .buttonStyle(.borderedProminent)
                        .disabled(newUsername.trimmingCharacters(in: .whitespaces).isEmpty || newPassword.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Shared subviews

    @ViewBuilder
    private func popoverHeader(icon: String, iconTint: Color, iconBackground: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconTint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func loginRow(_ entry: PasswordVaultEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(entry.username)
                        .font(.callout)
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let pwd = revealedPasswords[entry.id] {
                        Text(pwd)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("••••••••••")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .tracking(2)
                    }
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Button { toggleReveal(entry) } label: {
                    Image(systemName: revealedEntryIDs.contains(entry.id) ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(revealedEntryIDs.contains(entry.id) ? "Hide password" : "Show password")

                Button { copyPassword(entry) } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Copy password")

                Button { fill(entry) } label: {
                    Text("Autofill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Autofill on this page")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func actionRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(Color.accentColor)
                Text(label)
                    .font(.callout)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
    }

    private var openVaultRow: some View {
        Button {
            NotificationCenter.default.post(name: .showPasswordsVaultTabRequested, object: nil)
            onClose()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentColor)
                Text("Open Vault")
                    .font(.callout)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
    }

    // MARK: - Logic

    private func unlockWithBiometrics() async {
        isUnlocking = true
        unlockError = false
        let success = await vault.unlockVault()
        isUnlocking = false
        if !success { unlockError = true }
    }

    private func unlockWithPassphrase() async {
        guard !passphraseInput.isEmpty else { return }
        isUnlocking = true
        unlockError = false
        let success = await vault.unlockVault(passphrase: passphraseInput)
        isUnlocking = false
        if success { passphraseInput = "" } else { unlockError = true }
    }

    private func toggleReveal(_ entry: PasswordVaultEntry) {
        if revealedEntryIDs.contains(entry.id) {
            revealedEntryIDs.remove(entry.id)
            revealedPasswords.removeValue(forKey: entry.id)
        } else if let pwd = vault.password(for: entry.id) {
            revealedEntryIDs.insert(entry.id)
            revealedPasswords[entry.id] = pwd
        }
    }

    private func copyPassword(_ entry: PasswordVaultEntry) {
        guard let pwd = vault.password(for: entry.id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pwd, forType: .string)
        vault.markEntryUsed(id: entry.id)
    }

    private func fill(_ entry: PasswordVaultEntry) {
        guard vault.autofillEnabled,
              let password = vault.password(for: entry.id),
              let domain = currentWebDomain else { return }
        vault.markEntryUsed(id: entry.id)
        onFillLogin?(domain, entry.username, password)
        onClose()
    }

    private func saveNewLogin() {
        guard let domain = currentWebDomain else { return }
        let user = newUsername.trimmingCharacters(in: .whitespaces)
        guard !user.isEmpty, !newPassword.isEmpty else { return }
        vault.addEntry(domain: domain, username: user, password: newPassword)
        isAddingNew = false
    }

    private static func makePassword(length: Int = 20) -> String {
        let chars = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }
}
