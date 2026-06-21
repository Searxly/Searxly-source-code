//
//  SearchResultsView.swift
//  Searxly
//
//  Dedicated container/orchestrator for the entire SERP surface.
//

import SwiftUI

struct SearchResultsView: View {
    let results: [SearXNGResult]
    let currentCategory: String?
    let lastSearchQuery: String
    let glassEnabled: Bool
    let proxyBaseURL: String?
    let highlightedResultURL: String?

    let onClear: () -> Void
    let onSelectCategory: (String?) -> Void
    let onOpenPage: (SearXNGResult) -> Void
    let onOpenInNewTab: (SearXNGResult) -> Void
    let onPreviewMedia: (SearXNGResult) -> Void

    var onLoadMore: (() -> Void)? = nil
    var isLoadingMore: Bool = false
    var canLoadMore: Bool = true

    var knowledgePanelState: KnowledgePanelDisplayState = .hidden
    var onOpenKnowledgeURL: ((String) -> Void)? = nil

    private var dedupedResults: [SearXNGResult] {
        SearXNGResult.deduplicated(results)
    }

    private var categoryTabs: [(label: String, value: String?)] {
        [
            (Localization.string("category_all"), nil),
            (Localization.string("category_images"), "images"),
            (Localization.string("category_videos"), "videos"),
            (Localization.string("category_news"), "news")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            serpHeader
                .padding(.horizontal, SERPDesign.listHorizontalPadding)
                .padding(.bottom, 8)

            if !lastSearchQuery.isEmpty || !results.isEmpty {
                SERPCategoryTabs(
                    categories: categoryTabs,
                    selected: currentCategory,
                    glassEnabled: glassEnabled,
                    onSelect: onSelectCategory
                )
                .padding(.horizontal, SERPDesign.listHorizontalPadding - 4)
                .padding(.bottom, 12)
            }

            Divider()
                .opacity(0.35)
                .padding(.horizontal, SERPDesign.listHorizontalPadding)

            resultsBody
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var serpHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                if !lastSearchQuery.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lastSearchQuery)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text("\(dedupedResults.count.formatted()) results")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    Text(Localization.string("results_header_results"))
                        .font(.system(size: 22, weight: .regular))
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    SERPGlassIconButton(
                        systemName: "xmark",
                        glassEnabled: glassEnabled,
                        help: Localization.string("button_clear"),
                        action: onClear
                    )
                }
            }
        }
    }

    // MARK: - Results body

    @ViewBuilder
    private var resultsBody: some View {
        if currentCategory == "images" {
            ImageResultsGrid(
                results: dedupedResults,
                glassEnabled: glassEnabled,
                onOpenPage: onOpenPage,
                onPreview: onPreviewMedia,
                proxyBaseURL: proxyBaseURL,
                onLoadMore: onLoadMore,
                isLoadingMore: isLoadingMore,
                canLoadMore: canLoadMore
            )
        } else if currentCategory == "videos" {
            VideoResultsGrid(
                results: dedupedResults,
                glassEnabled: glassEnabled,
                onOpenPage: onOpenPage,
                onPreview: onPreviewMedia,
                proxyBaseURL: proxyBaseURL,
                onLoadMore: onLoadMore,
                isLoadingMore: isLoadingMore,
                canLoadMore: canLoadMore
            )
        } else if currentCategory == "news" {
            paginatedList(rows: dedupedResults) { result in
                NewsResultRow(
                    result: result,
                    glassEnabled: glassEnabled,
                    query: lastSearchQuery,
                    isHighlighted: highlightedResultURL == result.url,
                    onOpenInNewTab: { onOpenInNewTab(result) }
                ) {
                    onOpenPage(result)
                }
            }
        } else {
            paginatedList(rows: dedupedResults) { result in
                WebResultRow(
                    result: result,
                    glassEnabled: glassEnabled,
                    query: lastSearchQuery,
                    isHighlighted: highlightedResultURL == result.url,
                    onOpenInNewTab: { onOpenInNewTab(result) }
                ) {
                    onOpenPage(result)
                }
            }
        }
    }

    private var showsKnowledgePanel: Bool {
        currentCategory != "images" && currentCategory != "videos"
    }

    @ViewBuilder
    private func paginatedList<Row: View>(
        rows: [SearXNGResult],
        @ViewBuilder rowBuilder: @escaping (SearXNGResult) -> Row
    ) -> some View {
        GeometryReader { geometry in
            let panelFits = geometry.size.width >= SERPDesign.minWidthForKnowledgePanel
            let showPanel = showsKnowledgePanel && panelFits && knowledgePanelState != .hidden

            HStack(alignment: .top, spacing: showPanel ? SERPDesign.knowledgePanelSpacing : 0) {
                ScrollView {
                    resultsList(rows: rows, rowBuilder: rowBuilder)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showPanel {
                    let panelHeight = max(
                        geometry.size.height - 8,
                        SERPDesign.knowledgePanelMinContentHeight
                    )
                    ScrollView(.vertical, showsIndicators: false) {
                        knowledgePanelColumn(minHeight: panelHeight)
                    }
                    .frame(width: SERPDesign.knowledgePanelWidth, alignment: .topLeading)
                }
            }
            .padding(.horizontal, SERPDesign.listHorizontalPadding)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func resultsList<Row: View>(
        rows: [SearXNGResult],
        @ViewBuilder rowBuilder: @escaping (SearXNGResult) -> Row
    ) -> some View {
        LazyVStack(alignment: .leading, spacing: SERPDesign.resultSpacing) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, result in
                rowBuilder(result)
                    .onAppear {
                        if canLoadMore, !isLoadingMore, index >= rows.count - 3 {
                            onLoadMore?()
                        }
                    }

                if index < rows.count - 1 {
                    Divider()
                        .opacity(0.2)
                        .padding(.leading, 10)
                }
            }

            if isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.85)
                        .padding(.vertical, 16)
                    Spacer()
                }
            } else if canLoadMore, !rows.isEmpty {
                // Sentinel: fires onLoadMore when it scrolls into view (infinite-scroll trigger).
                Color.clear
                    .frame(height: 40)
                    .onAppear {
                        onLoadMore?()
                    }
            }
        }
        .frame(maxWidth: SERPDesign.maxListWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func knowledgePanelColumn(minHeight: CGFloat) -> some View {
        switch knowledgePanelState {
        case .hidden:
            EmptyView()
        case .loading:
            KnowledgePanelLoadingView(minHeight: minHeight, glassEnabled: glassEnabled)
        case .ready(let content):
            if let openURL = onOpenKnowledgeURL {
                KnowledgePanelView(
                    content: content,
                    proxyBase: proxyBaseURL,
                    minHeight: minHeight,
                    glassEnabled: glassEnabled,
                    onOpenURL: openURL
                )
            }
        }
    }
}