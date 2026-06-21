//
//  ClearBrowsingDataView.swift
//  Searxly
//
//  A focused, self-contained "Clear Browsing Data" dialog (Safari-style).
//  Reuses PrivacyManager for all actual clearing work.
//  Keeps the heavy logic out of SettingsView and ContentView.
//

import SwiftUI

// (Old YubiKey auth checks removed)


enum ClearTimeRange: String, CaseIterable, Identifiable {
    case lastHour = "Last hour"
    case lastDay = "Last 24 hours"
    case lastWeek = "Last 7 days"
    case allTime = "All time"

    var id: String { rawValue }

    var sinceDate: Date? {
        let now = Date()
        switch self {
        case .lastHour: return now.addingTimeInterval(-3600)
        case .lastDay:  return now.addingTimeInterval(-86400)
        case .lastWeek: return now.addingTimeInterval(-86400 * 7)
        case .allTime:  return nil
        }
    }
}

enum ClearCategory: String, CaseIterable, Identifiable {
    case history = "Browsing history"
    case cookiesAndSiteData = "Cookies & site data (Standard tabs only)"
    case cachedFiles = "Cached images and files"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .cookiesAndSiteData: return "shield.lefthalf.filled"
        case .cachedFiles: return "internaldrive"
        }
    }
}

struct ClearBrowsingDataView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRange: ClearTimeRange = .allTime
    @State private var selectedCategories: Set<ClearCategory> = [.history, .cookiesAndSiteData, .cachedFiles]

    @State private var isClearing = false
    @State private var showConfirmation = false
    @State private var confirmationMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Clear Browsing Data")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.regularMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Time range
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Time range")
                            .font(.headline)

                        Picker("Time range", selection: $selectedRange) {
                            ForEach(ClearTimeRange.allCases) { range in
                                Text(range.rawValue).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // Categories
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Data to clear")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ClearCategory.allCases) { category in
                                Toggle(isOn: Binding(
                                    get: { selectedCategories.contains(category) },
                                    set: { isOn in
                                        if isOn {
                                            selectedCategories.insert(category)
                                        } else {
                                            selectedCategories.remove(category)
                                        }
                                    }
                                )) {
                                    Label(category.rawValue, systemImage: category.systemImage)
                                }
                                .toggleStyle(.switch)
                            }
                        }
                    }

                    // Important note about privacy model
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Note")
                            .font(.subheadline.weight(.semibold))

                        Text("Private tabs use completely separate, non-persistent storage that is automatically deleted when the tab closes. This dialog only affects Standard tabs and the local history/suggestions stored by Searxly.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(20)
            }

            Divider()

            // Action bar
            HStack {
                Spacer()

                Button(role: .destructive) {
                    performClear()
                } label: {
                    if isClearing {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Clear", systemImage: "trash")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedCategories.isEmpty || isClearing)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
        }
        .frame(width: 480, height: 420)
        .alert("Data Cleared", isPresented: $showConfirmation) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private func performClear() {
        guard !selectedCategories.isEmpty else { return }

        isClearing = true
        let since = selectedRange.sinceDate

        // History
        if selectedCategories.contains(.history) {
            Task {
                PrivacyManager.shared.clearHistory(since: since)
            }
        }

        // Web data (cookies + cache + storage for Standard tabs)
        if selectedCategories.contains(.cookiesAndSiteData) || selectedCategories.contains(.cachedFiles) {
            // We clear the full web data set when either is chosen (they live in the same store).
            PrivacyManager.shared.clearStandardWebData(since: since) {
                finishClear()
            }
            return // async path
        }

        finishClear()
    }

    private func finishClear() {
        isClearing = false

        let count = selectedCategories.count
        confirmationMessage = "\(count) data type\(count == 1 ? "" : "s") cleared for the selected time range."

        // Post a broader notification so any open sheets can refresh if needed
        NotificationCenter.default.post(name: PrivacyManager.allPrivacyDataClearedNotification, object: nil)

        showConfirmation = true
    }
}
