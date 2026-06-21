//
//  LocalAIChatAuxiliaryViews.swift
//  Searxly
//

import SwiftUI

// MARK: - Tools List (new transparency feature for the chatbot)

struct ToolsListSheet: View {
    let glassEnabled: Bool
    let onDismiss: () -> Void

    private let manager = LocalIntelligenceManager.shared

    private let tools: [(icon: String, name: String, description: String, example: String)] = [
        ("magnifyingglass", "Web search", "Searches the web using only your private/local SearXNG instance(s). Nothing goes to public search engines. Results are synthesized into an answer that stays in the chat.", "e.g. “search the web for latest iPhone” or “who is Elon Musk?” or “browse and tell me about X”"),
        ("globe", "Open website", "Safely finds the official (or best matching) site for any brand/service using your private SearXNG instance (or direct domain) and opens it in a new tab. Use only for explicit navigation.", "e.g. “open the official X site” or “open Apple website for me” or “go to tesla.com”")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Available Tools")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done", action: onDismiss)
                    .glassPill(glassEnabled: glassEnabled)
                    .controlSize(.small)
            }

            Toggle("AI tool calling", isOn: Binding(
                get: { manager.preferences.toolsEnabled },
                set: { newValue in
                    manager.preferences.toolsEnabled = newValue
                    manager.persistPreferences()
                }
            ))
            .toggleStyle(.switch)

            if manager.toolsEnabled {
                Text("**On**: The assistant receives the two work tools and can proactively call web_search for research questions (answer stays in chat) or open_website for explicit navigation. Tool use is model-driven but heavily constrained by the rules.")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Text("**Off**: No tool instructions are provided to the model. The AI will not proactively call web_search or open_website. Control is 100% via the chips and very clear imperative sentences (or this toggle).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(tools, id: \.name) { tool in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: tool.icon)
                        .font(.title3)
                        .frame(width: 28)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.name)
                            .font(.callout.weight(.semibold))
                        Text(tool.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(tool.example)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }

            Text("All tool activity is logged in AI Activity for full transparency. Tools only ever use data and services you control.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            Divider()

            Text(AIPromptLibrary.userFacingSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()
        }
        .padding(20)
        .background(
            (glassEnabled ? .ultraThinMaterial : .regularMaterial),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .frame(minWidth: 440, minHeight: 400)
    }
}

struct CustomInstructionsEditor: View {
    let glassEnabled: Bool
    @Binding var instructions: String
    let onDismiss: () -> Void

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Custom Instructions for this Chat")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Cancel", action: onDismiss)
                    .glassPill(glassEnabled: glassEnabled)
                    .controlSize(.small)
                Button("Save") {
                    instructions = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    onDismiss()
                }
                .glassPill(isProminent: true, glassEnabled: glassEnabled)
                .controlSize(.small)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && instructions.isEmpty)
            }

            Text("These preferences apply only to this chat session and stay entirely on your Mac. They are prepended to the prompt but **core privacy, grounding, and tool rules always take precedence** and cannot be overridden.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(0.2))
                .padding(.vertical, 4)

            Text("Examples: \"Always be concise and use bullet points\", \"Focus on technical details and cite sources by domain\", \"Remember that I prefer privacy-first options\".")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if !instructions.isEmpty {
                Button("Clear instructions for this chat") {
                    draft = ""
                    instructions = ""
                    onDismiss()
                }
                .font(.caption)
                .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(20)
        .background(
            (glassEnabled ? .ultraThinMaterial : .regularMaterial),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .frame(minWidth: 480, minHeight: 320)
        .onAppear {
            draft = instructions
        }
    }
}