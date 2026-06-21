//  LocalSearxngManager.swift
//  Searxly
//
//  Rank 2: First-class in-app control for the user's local SearXNG Docker instance.
//  (UI surfaces in Onboarding + Settings/InstancesSettingsView post-refactor.)
//  Replaces the previous "run these commands in Terminal" experience.
//

import Foundation
import SwiftUI
import Observation
import Security

enum ContainerStatus: Equatable {
    case notInstalled          // Docker Desktop not found
    case stopped
    case starting
    case running
    case stopping
    case error(String)
}

/// Shared lean engine list for Searxly local Docker (creation + optimization + migration).
enum LeanSearxngEngines {
    static let block = """
engines:
  # Lean SearXNG engines for Searxly private instance (button-driven auto setup).
  # Stable image-shipped engines only. Edit ~/searxng-local/searxng/settings.yml to expand.
  # Wikipedia engine removed: Searxly promotes Grokipedia client-side and suppresses Wikipedia
  # in the native SERP. Knowledge-panel enrichment still fetches wiki text via site: queries.

  - name: bing
    engine: bing
    shortcut: bi

  - name: bing images
    engine: bing_images
    shortcut: bii
    categories: [images]

  - name: bing news
    engine: bing_news
    shortcut: bin
    categories: [news]

  - name: bing videos
    engine: bing_videos
    shortcut: biv
    categories: [videos]

  - name: duckduckgo
    engine: duckduckgo
    shortcut: ddg

  - name: brave
    engine: brave
    shortcut: br

  - name: startpage
    engine: startpage
    shortcut: sp

  - name: openverse
    engine: openverse
    categories: [images]
    shortcut: opv

  - name: flickr
    engine: flickr_noapi
    shortcut: fl
    categories: [images]

  - name: deviantart
    engine: deviantart
    shortcut: da
    categories: [images]

  - name: dailymotion
    engine: dailymotion
    shortcut: dm
    categories: [videos]

  - name: vimeo
    engine: vimeo
    shortcut: vi
    categories: [videos]

  - name: github
    engine: github
    shortcut: gh
    categories: [it, repos]

  - name: currency
    engine: currency_convert
    shortcut: cc
"""

    /// Engines appended to existing lean installs that predate the 2026 media expansion.
    static let mediaMigrationEntries: [(marker: String, yaml: String)] = [
        ("  - name: flickr", """
  - name: flickr
    engine: flickr_noapi
    shortcut: fl
    categories: [images]
"""),
        ("  - name: deviantart", """
  - name: deviantart
    engine: deviantart
    shortcut: da
    categories: [images]
"""),
        ("  - name: dailymotion", """
  - name: dailymotion
    engine: dailymotion
    shortcut: dm
    categories: [videos]
"""),
        ("  - name: vimeo", """
  - name: vimeo
    engine: vimeo
    shortcut: vi
    categories: [videos]
""")
    ]
}

@Observable
@MainActor
final class LocalSearxngManager {
    static let shared = LocalSearxngManager()

    var status: ContainerStatus = .stopped
    var isBusy = false
    var lastError: String?
    var logs: [String] = []

    /// Whether the required ~/searxng-local project folder with docker-compose.yml exists.
    var projectFolderExists = false

    /// When true, the local SearXNG publishes only on 127.0.0.1 (more secure).
    /// Normal users are always localhost-only. Developer Mode exposes an advanced LAN toggle.
    static let bindLocalhostOnlyKey = "SearXNG.BindLocalhostOnly"

    var bindToLocalhostOnly: Bool {
        get {
            migrateBindToLocalhostOnlyIfNeeded()
            if !DeveloperSettings.shared.isEnabled {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.bindLocalhostOnlyKey)
        }
        set {
            if !newValue && !DeveloperSettings.shared.isEnabled {
                return
            }
            UserDefaults.standard.set(newValue, forKey: Self.bindLocalhostOnlyKey)
        }
    }

    /// Whether Developer Mode allows changing the LAN exposure toggle.
    var canConfigureLANExposure: Bool {
        DeveloperSettings.shared.isEnabled
    }

    /// The pinned image tag bundled with this app build (for display in Settings).
    var pinnedSearxngImageTag: String { SearxngDockerConfig.pinnedImageTag }

    /// UserDefaults key mirrored from ContentView's @AppStorage — gates background auto-start.
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"

    /// Default location created by the onboarding "Create Local SearXNG Setup Folder" button.
    /// This is the canonical path Searxly uses for its private local instance.
    let projectFolderURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("searxng-local")

    /// Whether Searxly may start/pull the local Docker container without an explicit user action.
    /// Only true after onboarding is finished — never during the first-run flow.
    var mayAutoStartLocalContainer: Bool {
        UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey)
    }

    /// Whether Docker Desktop.app is present (daemon may still be stopped).
    var isDockerDesktopInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Docker.app")
    }

    /// Default local instance URL respecting the localhost-only bind preference.
    var defaultLocalInstanceURL: String {
        bindToLocalhostOnly ? "http://127.0.0.1:8080" : "http://localhost:8080"
    }

    /// Probe order for local SearXNG health checks. IPv4 first — `localhost` often resolves to `::1`,
    /// which fails when Docker publishes only on `127.0.0.1`.
    var localWebProbeURLs: [String] {
        if bindToLocalhostOnly {
            return ["http://127.0.0.1:8080"]
        }
        return ["http://127.0.0.1:8080", "http://localhost:8080"]
    }

    var currentTask: Task<Void, Never>?

    /// Coalesced launch warm-up (init + loadPersistedData must not each spawn docker probes).
    var launchWarmUpTask: Task<Void, Never>?

    /// Coalesced user-initiated ensure path (search, Local AI, Settings).
    var ensureReadyTask: Task<Void, Never>?

    /// Cached path to a working Docker CLI binary.
    /// We search common macOS locations because /usr/bin/env docker often fails
    /// inside sandboxed / Xcode-launched apps due to restricted PATH.
    var cachedDockerPath: String?

    private init() {
        // projectFolderExists starts false; warm-up is scheduled only after loadPersistedData
        // confirms onboarding is complete (never from init — that races ahead of onboarding UI).
    }

}
