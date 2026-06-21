//
//  AICitationLink.swift
//  Searxly
//
//  NEW FILE (Phase 0 scaffold, behavior in Phase 2).
//  Tappable citation marker that can highlight the corresponding SearchResultCard.
//

import SwiftUI

struct AICitationLink: View {
    let citation: Citation
    let onHighlight: (Citation) -> Void

    var body: some View {
        Button {
            onHighlight(citation)
        } label: {
            Text("[\(citation.id)]")
                .font(.caption2.bold())
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .help(citation.title)
    }
}