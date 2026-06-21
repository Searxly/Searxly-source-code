//
//  MediaPreviewSheetView.swift
//  Searxly
//
//  Extracted the image/video preview sheet to reduce expression complexity
//  in the main modifier chain.
//

import SwiftUI

// Legacy thin wrapper (kept for any other call sites). Now forwards to the new modular
// MediaPreviewSheet in Views/SearchResults/ (SERP redesign 2026).
struct MediaPreviewSheetView: View {
    let result: SearXNGResult
    let isVideo: Bool
    let onOpen: () -> Void
    var proxyBaseURL: String? = nil

    var body: some View {
        MediaPreviewSheet(result: result, isVideo: isVideo, onOpenPage: onOpen, proxyBaseURL: proxyBaseURL)
    }
}
