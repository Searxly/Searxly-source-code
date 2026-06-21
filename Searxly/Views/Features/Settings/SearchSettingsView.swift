//
//  SearchSettingsView.swift
//  Searxly
//

import SwiftUI

struct SearchSettingsView: View {
    @Binding var knowledgePanelEnabled: Bool

    @AppStorage("searchLanguageOverride") private var searchLanguageOverride: String = ""
    @AppStorage("searchQueryHistoryEnabled") private var searchQueryHistoryEnabled: Bool = true

    @State private var showClearConfirmation = false

    var body: some View {
        SettingsPane {
            SettingsPaneHeader(
                title: "Search",
                subtitle: "Control how Searxly presents search results on your Mac."
            )

            languageSection

            searchHistorySection

            SettingsSection(
                title: "Knowledge panel",
                footer: "Shows entity cards on the right side of web results. Disable this if you want zero external connections — your main search always stays private through your local SearXNG."
            ) {
                SettingsCallout(
                    title: "Connects directly to Grokipedia",
                    message: "When enabled, Searxly fetches article data directly from grokipedia.com for every entity card shown. Your search query reaches Grokipedia's servers — it does not go through your private SearXNG instance. Grokipedia can see what you searched and your IP address (or your VPN exit IP if a VPN is active).",
                    tint: .orange,
                    systemImage: "exclamationmark.triangle.fill"
                )

                SettingsToggleRow(
                    title: "Knowledge panel on search results",
                    description: "Google-style info cards for brands, people, and dictionary words.",
                    isOn: $knowledgePanelEnabled
                )
            }
        }
    }

    // MARK: - Language section

    @ViewBuilder
    private var languageSection: some View {
        SettingsSection(
            title: "Search Language",
            footer: "Controls which language and region SearXNG passes to search engines. Set this if your results appear in the wrong language despite your Mac being set to English."
        ) {
            let effectiveLabel: String = {
                if searchLanguageOverride.isEmpty {
                    return "System (\(AppLanguage.systemSearchLanguageCode))"
                }
                return SearchLanguage.all.first(where: { $0.code == searchLanguageOverride })?.label
                    ?? searchLanguageOverride
            }()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Language for search results")
                        .font(.callout)
                    Text("Active: \(effectiveLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Button {
                        searchLanguageOverride = ""
                    } label: {
                        HStack {
                            Text("System default (\(AppLanguage.systemSearchLanguageCode))")
                            if searchLanguageOverride.isEmpty { Image(systemName: "checkmark") }
                        }
                    }

                    Divider()

                    ForEach(SearchLanguage.all) { lang in
                        Button {
                            searchLanguageOverride = lang.code
                        } label: {
                            HStack {
                                Text(lang.label)
                                if lang.code == searchLanguageOverride { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(effectiveLabel)
                            .font(.callout)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            if !searchLanguageOverride.isEmpty {
                Button("Reset to system default") {
                    searchLanguageOverride = ""
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
    }

    // MARK: - Search history section

    @ViewBuilder
    private var searchHistorySection: some View {
        SettingsSection(
            title: "Search History",
            footer: "When enabled, past search queries are suggested as you type. Only queries that returned results are saved — nothing leaves your device."
        ) {
            SettingsToggleRow(
                title: "Suggest recent searches",
                description: "Show past search queries in the address bar dropdown.",
                isOn: $searchQueryHistoryEnabled
            )

            if searchQueryHistoryEnabled {
                HStack {
                    Button("Clear search history") {
                        SearchQueryHistoryStore.shared.clearAll()
                        showClearConfirmation = true
                    }
                    .font(.callout)
                    .buttonStyle(.link)
                    .foregroundStyle(.red)

                    Spacer()
                }
                .alert("Search history cleared", isPresented: $showClearConfirmation) {
                    Button("OK") {}
                }
            }
        }
    }
}

// MARK: - Language list

struct SearchLanguage: Identifiable {
    let code: String   // SearXNG format: "en-US", "fr-FR", etc.
    let label: String
    var id: String { code }

    static let all: [SearchLanguage] = [
        SearchLanguage(code: "en-US",  label: "English (US)"),
        SearchLanguage(code: "en-GB",  label: "English (UK)"),
        SearchLanguage(code: "en-CA",  label: "English (Canada)"),
        SearchLanguage(code: "en-AU",  label: "English (Australia)"),
        SearchLanguage(code: "fr-FR",  label: "French (France)"),
        SearchLanguage(code: "fr-CA",  label: "French (Canada)"),
        SearchLanguage(code: "de-DE",  label: "German"),
        SearchLanguage(code: "es-ES",  label: "Spanish (Spain)"),
        SearchLanguage(code: "es-MX",  label: "Spanish (Mexico)"),
        SearchLanguage(code: "it-IT",  label: "Italian"),
        SearchLanguage(code: "pt-PT",  label: "Portuguese (Portugal)"),
        SearchLanguage(code: "pt-BR",  label: "Portuguese (Brazil)"),
        SearchLanguage(code: "nl-NL",  label: "Dutch"),
        SearchLanguage(code: "sv-SE",  label: "Swedish"),
        SearchLanguage(code: "no-NO",  label: "Norwegian"),
        SearchLanguage(code: "da-DK",  label: "Danish"),
        SearchLanguage(code: "fi-FI",  label: "Finnish"),
        SearchLanguage(code: "pl-PL",  label: "Polish"),
        SearchLanguage(code: "ru-RU",  label: "Russian"),
        SearchLanguage(code: "tr-TR",  label: "Turkish"),
        SearchLanguage(code: "ar-SA",  label: "Arabic"),
        SearchLanguage(code: "ja-JP",  label: "Japanese"),
        SearchLanguage(code: "ko-KR",  label: "Korean"),
        SearchLanguage(code: "zh-CN",  label: "Chinese (Simplified)"),
        SearchLanguage(code: "zh-TW",  label: "Chinese (Traditional)"),
        SearchLanguage(code: "hi-IN",  label: "Hindi"),
        SearchLanguage(code: "id-ID",  label: "Indonesian"),
        SearchLanguage(code: "uk-UA",  label: "Ukrainian"),
        SearchLanguage(code: "cs-CZ",  label: "Czech"),
        SearchLanguage(code: "ro-RO",  label: "Romanian"),
        SearchLanguage(code: "hu-HU",  label: "Hungarian"),
        SearchLanguage(code: "el-GR",  label: "Greek"),
        SearchLanguage(code: "he-IL",  label: "Hebrew"),
        SearchLanguage(code: "th-TH",  label: "Thai"),
        SearchLanguage(code: "vi-VN",  label: "Vietnamese"),
    ]
}
