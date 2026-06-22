//
//  MediaPreviewSheet.swift
//  Searxly
//
//  Premium lightbox/preview for both images and videos (2026 SERP redesign).
//  Threaded proxyBaseURL for high-quality full-size previews via the user's SearXNG instance.
//  Matches the app's premium dark design language (AdaptiveChrome canvas + SERPDesign accent),
//  with the media rendered at its true aspect ratio on a black stage — never stretched.
//

import SwiftUI
import os
import AppKit

struct MediaPreviewSheet: View {
    let result: SearXNGResult
    let isVideo: Bool
    let onOpenPage: () -> Void
    let proxyBaseURL: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("reduceLiquidGlass") private var reduceLiquidGlass = false
    private var glassEnabled: Bool { !reduceLiquidGlass }

    @State private var didCopy = false

    /// Deep lightbox stage — slightly darker than the app canvas so the media "floats".
    private let stageColor = Color(red: 0.02, green: 0.02, blue: 0.028)

    private var previewCandidates: [URL] {
        SearchMediaURLResolver.candidateURLs(for: result, proxyBase: proxyBaseURL, mode: .fullSizePreview)
    }

    private var hostLabel: String? {
        guard let host = URL(string: result.url)?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var canvas: Color {
        AdaptiveChrome.appCanvas(colorScheme, glassEnabled: glassEnabled)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .background(canvas)

            Divider().overlay(AdaptiveChrome.divider(colorScheme))

            imageStage

            Divider().overlay(AdaptiveChrome.divider(colorScheme))

            metaRow
                .background(canvas)

            footer
                .background(canvas)
        }
        .background(canvas)
        .frame(minWidth: 540, idealWidth: 800, minHeight: 480, idealHeight: 660)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title.isEmpty ? (hostLabel ?? "Preview") : result.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let hostLabel {
                    HStack(spacing: 5) {
                        FaviconView(pageURL: result.url, size: 11, cornerRadius: 2, loadRemote: true)
                        Text(hostLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .glassIcon(size: 30, glassEnabled: glassEnabled)
            .keyboardShortcut(.cancelAction)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Image / video stage

    private var imageStage: some View {
        ZStack {
            stageColor

            if !previewCandidates.isEmpty {
                // Dev diagnostic (when you open preview from a blank grid tile under "Images"/"Videos").
                let _ = {
                    if DeveloperSettings.shared.isEnabled, let u = previewCandidates.first {
                        Log.app.info("[Dev][MediaPreview] previewURL=\(u.absoluteString.prefix(110)) isVideo=\(isVideo)")
                    }
                }()

                CachedSearchThumbnail(
                    candidates: previewCandidates,
                    referer: result.url,
                    aspectRatio: isVideo ? 16.0 / 9.0 : 4.0 / 3.0,
                    contentMode: .fit,
                    useNaturalAspect: true,
                    naturalMaxHeight: 560
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 8)
                .overlay {
                    if isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(.white.opacity(0.92))
                            .shadow(radius: 10)
                    }
                }
                .padding(20)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: isVideo ? "video.slash.fill" : "photo")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.32))
                    Text(isVideo ? "No video thumbnail available" : "No image available for preview")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(60)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 300)
    }

    // MARK: - Meta row

    private var metaRow: some View {
        HStack(spacing: 16) {
            if let res = result.resolution, !res.isEmpty {
                metaLabel(res, systemImage: "square.dashed")
            }
            if let format = result.img_format, !format.isEmpty {
                metaLabel(format.uppercased(), systemImage: "doc")
            }
            if let eng = result.enginesDisplay ?? result.primaryEngine {
                metaLabel(eng, systemImage: "magnifyingglass")
            }
            if let pub = result.formattedPublishedDate() {
                metaLabel(pub, systemImage: "calendar")
            }
            Spacer(minLength: 0)
            Text(result.url)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: 220, alignment: .trailing)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func metaLabel(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                onOpenPage()
                dismiss()
            } label: {
                Label("Visit Original Page", systemImage: "arrow.up.right.square")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(SERPDesign.accentGreen)
            .keyboardShortcut(.defaultAction)

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(result.url, forType: .string)
                didCopy = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { didCopy = false }
            } label: {
                Label(didCopy ? "Copied" : Localization.string("search_result_copy_page_url"),
                      systemImage: didCopy ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Button("Close", role: .cancel) {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
    }
}
