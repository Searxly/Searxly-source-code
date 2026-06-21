//
//  LocalAISummarySheet.swift
//  Searxly
//
//  NEW FILE (Phase 0 scaffold, real content in Phase 2).
//  Renders a grounded on-device synthesis of search result *snippets* (per security decision: Option A).
//  Citations are mechanical (derived from the exact results passed in) and tappable.
//

import SwiftUI

struct LocalAISummarySheet: View {
    let summary: AISummary?
    let onDismiss: () -> Void
    /// Optional handler to open/highlight a source (e.g. load the URL).
    var onHighlightCitation: ((Citation) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                Text("Local on-device synthesis")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if let s = summary {
                Text("Query: \(s.query)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(s.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 320)

                if !s.citations.isEmpty {
                    Divider()
                    Text("Sources (tap to open)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(s.citations) { citation in
                        Button {
                            onHighlightCitation?(citation)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.blue)
                                    .frame(width: 28, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(citation.title)
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                    Text(citation.domain)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            } else {
                Text("No summary available.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 420)
        .background(.regularMaterial)
    }
}