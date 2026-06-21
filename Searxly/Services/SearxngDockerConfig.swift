//
//  SearxngDockerConfig.swift
//  Searxly
//
//  Pinned SearXNG container image for reproducible local installs.
//  Bump `pinnedImageTag` deliberately when validating a newer upstream release.
//

import Foundation

enum SearxngDockerConfig {
    static let imageRepository = "searxng/searxng"

    /// Pinned upstream tag (not `:latest`). See https://hub.docker.com/r/searxng/searxng/tags
    static let pinnedImageTag = "2025.2.12-d456f3dd9"

    static var pinnedImageReference: String {
        "\(imageRepository):\(pinnedImageTag)"
    }

    /// Tag of the pinned image last successfully pulled on this Mac.
    static let imagePulledTagKey = "Searxly.SearxngPinnedImagePulledTag"

    /// Legacy bool from earlier builds; migrated to `imagePulledTagKey` on read.
    static let imagePulledOnceKey = "Searxly.SearxngPinnedImagePulled"

    static let legacyUnknownPulledTag = "__legacy_unknown__"
}