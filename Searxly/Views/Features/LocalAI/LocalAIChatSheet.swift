//
//  LocalAIChatSheet.swift
//  Searxly
//
//  Main chat UI for Searxly Agent (on-device + tool calling).
//  Uses ConversationEngine for prompt/context preparation.
//

import SwiftUI
import UniformTypeIdentifiers   // for fileImporter + UTType
import PDFKit                   // for safe text extraction from user-chosen PDFs (local only)

#if canImport(FoundationModels)
import FoundationModels
#endif

// New premium components for the Siri AI-style redesign
// (all logic and state handling remain in this file's methods below)

struct LocalAIChatSheet: View {
    @Binding var isPresented: Bool

    /// The two (and only two) work tool closures.
    /// - performPrivateSearch: used by web_search (research/knowledge questions → answer in chat)
    /// - openWebsite: used by open_website (explicit "open the ... site" navigation → opens tab + dismisses sheet)
    ///
    /// All previous agentic tools (history, open tabs, bookmark, new private search tab) have been removed.
    var performPrivateSearch: ((String) async -> [SearXNGResult])? = nil
    var openWebsite: ((String) -> Void)? = nil

    /// The last search query the user ran, passed in by the parent view from BrowserState.lastSearchQuery.
    /// Using an in-memory property avoids writing sensitive search queries to unencrypted UserDefaults.
    var lastSearchQuery: String = ""

    /// Closure to retrieve RAG items for the current query (Phase 4).
    /// Provided by parent so we can use the live history/bookmarks from BrowserState.
    /// Now async because RAGEngine.retrieve (and thus the semantic query embedding) is async.
    /// The previous blocking semaphore version was causing actor/task violations ("task XXX" errors at sema.wait())
    /// and could starve the main thread / WebContent processes.
    var retrieveRAG: ((String) async -> [RAGItem])? = nil

    @State var messages: [ChatMessage] = []
    @State var inputText: String = ""
    @State var isThinking = false
    @State var attachedSearchContext: String? = nil

    /// Pending tool request that the model has asked for (shown as a confirmation card).
    @State var pendingToolRequest: PendingToolRequest? = nil

    /// Shows the list of available tools the AI can request (when toolsEnabled).
    @State var showingToolsList = false

    /// User-set custom instructions for this chat only (style, focus, reminders, etc.).
    @State var customInstructions: String = ""
    @State var showingInstructionsEditor = false

    /// Tiny follow-up chips under the latest assistant message.
    @State var currentFollowUpSuggestions: [String] = []

    @State var attachedFiles: [ChatAttachment] = []
    @State var showingFileImporter = false
    @State var showingConversationsList = false

    @AppStorage("reduceLiquidGlass") var reduceLiquidGlass = false
    var glassEnabled: Bool { !reduceLiquidGlass }

    var manager: LocalIntelligenceManager { LocalIntelligenceManager.shared }
    let conversationEngine = ConversationEngine()

    struct PendingToolRequest: Equatable {
        let toolName: String
        let payload: String   // the argument string after the tool name (e.g. query, "url1,url2", "url|title|note", etc.)
    }

    // Current orb state derived from thinking (future: can expand with provider generating flag)
    private var orbState: AIOrbState {
        if isThinking { return .thinking }

        // Brief "responding" visual after an assistant message lands (Siri-like "speaking" feel).
        // Uses the message timestamp (preserved by streaming + native paths) for a short window.
        if let last = messages.last(where: { $0.role == .assistant }),
           Date().timeIntervalSince(last.timestamp) < 2.8 {
            return .responding
        }

        return .idle
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — flat, monochrome (Searxly design language)
            HStack(spacing: 11) {
                SearxlyChatMark(color: WalletTheme.textPrimary, lineWidth: 1.4, filledDot: true)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Searxly AI")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(WalletTheme.textPrimary)
                    if manager.canUseFeatures {
                        HStack(spacing: 5) {
                            Circle().fill(WalletTheme.positive).frame(width: 6, height: 6)
                            Text(backendStatusText)
                                .font(.caption2)
                                .foregroundStyle(WalletTheme.textSecondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                if manager.canUseFeatures {
                    modelSwitcher

                    headerIcon("clock.arrow.circlepath", help: "Previous conversations") { showingConversationsList = true }
                    headerIcon("square.and.pencil", help: "New conversation") { startNewConversation() }
                    headerIcon("slider.horizontal.3", help: "Tools & AI tool calling") { showingToolsList = true }
                    headerIcon("text.quote", help: customInstructions.isEmpty ? "Custom instructions" : "Edit custom instructions (active)") { showingInstructionsEditor = true }
                } else {
                    Text("Enable in Settings → Searxly AI")
                        .font(.caption2)
                        .foregroundStyle(WalletTheme.warning)
                }

                headerIcon("xmark", help: "Close", emphasized: true) {
                    attachedFiles.removeAll()
                    attachedSearchContext = nil
                    customInstructions = ""
                    safelyResetAIState()
                    Task { await LocalIntelligenceManager.shared.currentIntelligenceProvider.unload() }
                    isPresented = false
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty {
                            // Empty state — monochrome
                            VStack(spacing: 18) {
                                SearxlyChatMark(color: WalletTheme.textPrimary.opacity(0.92), lineWidth: 1.6, filledDot: true)
                                    .frame(width: 54, height: 54)
                                    .padding(.top, 30)

                                VStack(spacing: 6) {
                                    Text("Searxly AI")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(WalletTheme.textPrimary)
                                    Text(emptyStateSubtitle)
                                        .font(.callout)
                                        .foregroundStyle(WalletTheme.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.horizontal, 24)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    examplePrompt("Search this topic privately")
                                    examplePrompt("What do my files say?")
                                    examplePrompt("Open the official site")
                                    examplePrompt("Summarize my results")
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 12)
                        }

                        ForEach(messages) { msg in
                            if msg.role == .system {
                                Text(msg.text)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 3)
                                    .multilineTextAlignment(.center)
                            } else {
                                chatBubble(for: msg)
                                    .id(msg.id)

                                // Tiny elegant follow-up suggestions (glass pills) only under latest assistant
                                if msg.role == .assistant && isLastAssistantMessage(msg) && !currentFollowUpSuggestions.isEmpty {
                                    HStack(spacing: 6) {
                                        ForEach(currentFollowUpSuggestions, id: \.self) { suggestion in
                                            Button {
                                                inputText = suggestion
                                                send()
                                            } label: {
                                                Text(suggestion)
                                                    .font(.caption2)
                                                    .lineLimit(1)
                                                    .foregroundStyle(WalletTheme.textSecondary)
                                                    .padding(.horizontal, 11)
                                                    .padding(.vertical, 6)
                                                    .background(Capsule().fill(WalletTheme.surface))
                                                    .overlay(Capsule().strokeBorder(WalletTheme.hairline, lineWidth: 0.7))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.leading, 33)
                                    .padding(.top, 2)
                                }
                            }
                        }

                        if showTypingIndicator {
                            HStack(alignment: .top, spacing: 11) {
                                SearxlyChatMark(color: WalletTheme.textSecondary, lineWidth: 1.4)
                                    .frame(width: 22, height: 22)
                                    .padding(.top, 2)
                                TypingDots()
                                    .padding(.top, 5)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .onChange(of: messages.count) { _, _ in
                    safeScrollToBottom(proxy: proxy, animated: false)
                }
                .onChange(of: isThinking) { _, newValue in
                    DispatchQueue.main.async {
                        if newValue {
                            if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        } else if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: pendingToolRequest) { oldValue, newValue in
                    if oldValue != nil && newValue == nil && isThinking {
                        DispatchQueue.main.async {
                            if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }

            // Tool confirmation — now a premium glass card (no more harsh orange warning)
            if let pending = pendingToolRequest {
                toolConfirmationCard(for: pending)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }

            // The new Siri-style glassy composer (big win for feel)
            ChatComposer(
                inputText: $inputText,
                isThinking: isThinking,
                canUseFeatures: manager.canUseFeatures,
                glassEnabled: glassEnabled,
                placeholder: composerPlaceholder,
                footnote: composerFootnote,
                attachedFiles: attachedFiles,
                onRemoveAttachment: removeAttachment,
                onTapAttachment: { file in
                    // Quick system note with excerpt (future: nicer preview sheet)
                    messages.append(ChatMessage(role: .system, text: "Attached file excerpt (local only): \(file.filename) — \(file.extractedText.prefix(140))..."))
                },
                onWebSearchChip: {
                    Task { @MainActor in await executeUserWebSearch() }
                },
                onOpenSiteChip: {
                    inputText = "open the official site for me"
                },
                onSend: send,
                onAttachFile: { showingFileImporter = true },
                onDrop: handleDroppedFiles
            )
        }
        .background(WalletTheme.canvas)
        // Size is dictated by the fixed-size floating panel host in ContentView (no more min here;
        // the outer frame is chosen large enough to avoid all internal layout breaks/crowding).
        .onAppear(perform: seedIfNeeded)
        .onDisappear {
            if !manager.preferences.lowMemoryMode {
                LocalIntelligenceManager.shared.considerIdleUnload()
            } else {
                Task { await LocalIntelligenceManager.shared.unloadAll() }
            }
        }
        .sheet(isPresented: $showingToolsList) {
            ToolsListSheet(glassEnabled: glassEnabled, onDismiss: { showingToolsList = false })
        }
        .sheet(isPresented: $showingInstructionsEditor) {
            CustomInstructionsEditor(
                glassEnabled: glassEnabled,
                instructions: $customInstructions,
                onDismiss: { showingInstructionsEditor = false }
            )
        }
        .sheet(isPresented: $showingConversationsList) {
            conversationsListSheet
        }
        // File importer (unchanged contract)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.plainText, .pdf, UTType(filenameExtension: "md") ?? .text, .commaSeparatedText, .json],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for url in urls { addLocalFile(url: url) }
            case .failure(let error):
                messages.append(ChatMessage(role: .system, text: "Couldn't attach file: \(error.localizedDescription)"))
            }
        }
    }
}
