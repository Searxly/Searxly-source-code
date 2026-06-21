//
//  LocalSearxngManager+Lifecycle
//  Searxly
//

import Foundation
import SwiftUI
import Observation
import Security

extension LocalSearxngManager {
    // MARK: - Public API

    func start() async {
        guard !isBusy else { return }

        if cachedDockerPath == nil {
            await refreshStatus()
        }
        if case .notInstalled = status {
            lastError = lastError ?? "Docker CLI not found. Install Docker Desktop, launch it, wait until it reports 'Docker Desktop is running', then tap Recheck."
            logs.append("❌ " + (lastError ?? ""))
            logs.append("💡 " + dockerDaemonHint())
            return
        }

        // Make sure the project folder exists (defensive — onboarding should have created it)
        await updateProjectFolderExists()
        if !projectFolderExists {
            lastError = "Local SearXNG folder not found. Use the 'Create Local SearXNG Setup Folder' button in Onboarding or Settings first."
            status = .error(lastError!)
            logs.append("❌ " + (lastError ?? ""))
            return
        }

        if await isLocalWebReady() {
            status = .running
            lastError = nil
            return
        }

        // Container already up but HTTP not ready yet — poll only, never re-run compose.
        if await checkIfContainerIsRunning() {
            isBusy = true
            status = .starting
            lastError = nil
            logs.append("⏳ SearXNG container is already running — waiting for web server...")
            let ready = await waitForLocalWebReady(maxAttempts: 30, delaySeconds: 2, logProgress: true)
            isBusy = false
            if ready {
                status = .running
                lastError = nil
            } else {
                await refreshStatus()
            }
            return
        }

        // For users who set up before the lean-engine optimization (very common),
        // automatically slim down the engine list on next start. This is the biggest
        // lever for "SearXNG taking too long to load" *and* for avoiding engine load
        // crashes/restart loops (ahmia, bandcamp dupes, missing .py etc.).
        // Safe: only touches engines section, backs up the file, runs at most once.
        await ensureFastEngineConfigIfNeeded()
        await ensureMediaEnginesMigratedIfNeeded()

        isBusy = true
        lastError = nil
        status = .starting
        logs.append("▶️ Starting SearXNG...")
        logs.append("   bindToLocalhostOnly = \(bindToLocalhostOnly) (this controls whether we publish 127.0.0.1:8080 or 0.0.0.0:8080 on the host)")

        let alreadyRunning = await checkIfContainerIsRunning()

        currentTask = Task {
            // Only force-recreate when the container is not already running — avoids restarting
            // a healthy SearXNG instance during onboarding auto-detect or status refresh.
            let upArgs = alreadyRunning ? ["up", "-d"] : ["up", "-d", "--force-recreate"]
            await runDockerComposeCommand(upArgs)

            // Extra diagnostics: prints exactly what host:port Docker mapped for the container.
            logs.append("🔍 Querying actual published port for searxng:8080 ...")
            let portResult = await withCheckedContinuation {
                (continuation: CheckedContinuation<(Int32, String, String), Never>) in
                if let proxy = DockerHelperClient.shared.proxy() {
                    proxy.runDockerCompose(
                        args: ["port", "searxng", "8080"],
                        projectPath: self.projectFolderURL.path,
                        extraEnv: [:]
                    ) { code, out, err in
                        continuation.resume(returning: (code, out, err))
                    }
                } else {
                    continuation.resume(returning: (-1, "", "XPC helper unavailable"))
                }
            }
            let portOutput = portResult.1.trimmingCharacters(in: .whitespacesAndNewlines)
            if !portOutput.isEmpty {
                logs.append("📍 Docker published: " + portOutput)
            } else {
                logs.append("📍 'docker compose port' gave no output (check with `docker compose ps` in Terminal)")
            }
        }
        await currentTask?.value

        isBusy = false

        if lastError == nil {
            // Only emit the long guidance message on true first-start scenarios (not every re-entry into start()
            // during onboarding detection). This prevents the scary multi-line block from spamming the UI logs
            // disclosure when the instance is already healthy or the user just re-tapped Recheck.
            let shouldShowLongWaitHint = logs.isEmpty || !logs.contains { $0.contains("Waiting for SearXNG to become ready") }
            if shouldShowLongWaitHint {
                logs.append("⏳ Waiting for SearXNG to become ready (lean config; first boot can take 30-90s on 8/16 GB Macs)...")
            }

            // When the container was already running, only HTTP-probe — a second `compose up --wait`
            // can disturb a healthy instance and contributed to restart loops on app launch.
            var ready = false
            if alreadyRunning {
                ready = await waitForLocalWebReady(maxAttempts: 15, delaySeconds: 2, logProgress: true)
            } else {
                // Prefer Docker's healthcheck when available (we added one to docker-compose.yml).
                let composePath = projectFolderURL.appendingPathComponent("docker-compose.yml").path
                let composeExists = await DockerHelperClient.shared.proxy()?.fileExistsAsync(atPath: composePath) ?? false
                if composeExists {
                    let hostBindPrefix = bindToLocalhostOnly ? "127.0.0.1:" : ""
                    _ = await withCheckedContinuation {
                        (continuation: CheckedContinuation<(Int32, String, String), Never>) in
                        if let proxy = DockerHelperClient.shared.proxy() {
                            proxy.runDockerCompose(
                                args: ["up", "-d", "--wait", "--wait-timeout", "120"],
                                projectPath: self.projectFolderURL.path,
                                extraEnv: [
                                    "SEARXNG_HOST_BIND": hostBindPrefix,
                                    "SEARXNG_BIND_ADDRESS": "0.0.0.0",
                                ]
                            ) { code, out, err in
                                continuation.resume(returning: (code, out, err))
                            }
                        } else {
                            continuation.resume(returning: (-1, "", ""))
                        }
                    }
                }

                ready = await waitForLocalWebReady(maxAttempts: 30, delaySeconds: 2, logProgress: true)
            }

            if !ready {
                logs.append("⚠️ SearXNG container is up but web server not responding (connection refused).")
                logs.append("   This usually means the container was created with old port settings *or* engine configuration errors in settings.yml")
                logs.append("   (e.g. ahmia engine loading failed, bandcamp ambiguous/duplicate name, missing .py for stackoverflow/arxiv,")
                logs.append("    or leftover engines from the full upstream example causing worker crash + restart loop).")
                logs.append("   The 'Download & start...' button + 'Recreate (fresh)' in the manual section now guarantee a minimal")
                logs.append("   compatible lean engines list (no ahmia/bandcamp/stackoverflow/arxiv).")
                logs.append("   Quick fixes: 1) Use the 'Recreate folder (fresh)' / 'Recreate (fresh)' option in the manual disclosure (safest — deletes and rebuilds clean settings + secret).")
                logs.append("   2) In Terminal: cd ~/searxng-local && docker compose down && docker compose up -d")
                logs.append("   3) Check `docker logs searxng` inside Docker Desktop (look for 'engine loading failed', 'ambiguous name', or python tracebacks).")
                logs.append("   4) As last resort: edit docker-compose.yml to pin an older searxng/searxng tag and `docker compose up -d --force-recreate`.")
            }
            await refreshStatus()
        }
    }

    func stop() async {
        guard !isBusy else { return }

        if cachedDockerPath == nil {
            await refreshStatus()
        }
        if case .notInstalled = status {
            lastError = lastError ?? "Docker CLI not found."
            return
        }

        isBusy = true
        lastError = nil
        status = .stopping
        logs.append("⏹ Stopping SearXNG...")

        currentTask = Task {
            await runDockerComposeCommand(["down"])
        }
        await currentTask?.value

        isBusy = false

        if lastError == nil {
            await refreshStatus()
        }
    }

    func restart() async {
        await stop()
        await start()
    }

    func refreshStatus() async {
        await updateProjectFolderExists()

        let dockerAvailable = await checkDockerAvailable()
        if !dockerAvailable {
            status = .notInstalled
            lastError = "Docker CLI not found. Install and launch Docker Desktop, wait until it says it's running (menu bar icon), then tap Recheck."
            return
        }

        // Docker is available — clear stale error if we were in notInstalled state
        if case .notInstalled = status {
            lastError = nil
        }

        // Prefer a live HTTP probe — works even when the Docker CLI is missing from PATH
        // but SearXNG is already serving on the default local port.
        if await isLocalWebReady() {
            status = .running
            if lastError?.contains("not ready") == true || lastError?.contains("not running") == true {
                lastError = nil
            }
            return
        }

        let daemonReachable = await isDockerDaemonReachable()
        if !daemonReachable {
            status = .stopped
            if isDockerDesktopInstalled {
                lastError = "Docker Desktop is installed but the engine is not running. Open Docker from Applications, wait for the menu bar whale icon, then tap Recheck."
            } else {
                lastError = nil
            }
            return
        }

        // Check container + whether the web server inside is actually responding.
        // Pure `docker ps` is not enough — SearXNG can take 5-30s to become ready after "up".
        let containerRunning = await checkIfContainerIsRunning()
        if containerRunning {
            status = .starting
            lastError = "Container is running but SearXNG is still starting up. Wait a few seconds and tap refresh (or the status badge)."
        } else {
            status = .stopped
            lastError = nil
        }
    }

    func clearLogs() {
        logs.removeAll()
    }

    /// Human-friendly guidance for the exact Docker socket/daemon error the user is seeing
    /// in the Xcode console ("failed to connect to the docker API at unix:///.../docker.sock").
    func dockerDaemonHint() -> String {
        "Docker Desktop daemon is not running (or the socket at ~/.docker/run/docker.sock does not exist).\n" +
        "→ Launch Docker Desktop from /Applications, wait until it reports the daemon is ready, then use the status badge or Settings to retry."
    }

    /// Allows the user (or UI) to force re-detection of the Docker CLI.
    /// Useful after the user installs or launches Docker Desktop.
    func resetDockerDetection() {
        cachedDockerPath = nil
        status = .stopped
    }

    /// Clears cached Docker CLI path without forcing status to stopped (safe for Recheck during onboarding).
    func clearDockerPathCache() {
        cachedDockerPath = nil
    }

    // MARK: - Launch warm-up

    /// Schedules a single coalesced launch warm-up. Only runs after onboarding is complete.
    func scheduleLaunchWarmUp() {
        guard mayAutoStartLocalContainer else { return }
        if launchWarmUpTask != nil { return }
        launchWarmUpTask = Task { @MainActor in
            await warmUpLocalSearchOnLaunchIfNeeded()
            launchWarmUpTask = nil
        }
    }

    /// Probe-first launch path: never re-runs compose against a healthy or booting container,
    /// never launches/restarts Docker Desktop, and only starts SearXNG when the daemon is up
    /// and the container is genuinely stopped.
    func warmUpLocalSearchOnLaunchIfNeeded() async {
        guard mayAutoStartLocalContainer else { return }

        await updateProjectFolderExists()
        await refreshStatus()

        if await isLocalWebReady() {
            status = .running
            lastError = nil
            return
        }

        if await checkIfContainerIsRunning() {
            status = .starting
            lastError = nil
            if await waitForLocalWebReady(maxAttempts: 45, delaySeconds: 2) {
                status = .running
                lastError = nil
            } else {
                await refreshStatus()
            }
            return
        }

        guard projectFolderExists else { return }
        guard await isDockerDaemonReachable() else { return }
        guard !isBusy else { return }

        await start()
    }

    // MARK: - High-level automatic provisioning APIs (for "almost nothing to do" onboarding)

    /// The main "make it just work" API for the automatic onboarding path.
    /// Ensures the folder+configs exist (real secret injected), starts the container if necessary,
    /// and waits for the web server to be responsive (reusing the existing readiness logic).
    /// Updates status, logs, and lastError for the UI to observe.
    ///
    /// Now also automatically downloads Docker Desktop (the runtime needed for the "local private SearXNG container")
    /// if it's not on the device, launches it, waits for the daemon, then provisions and starts the SearXNG container.
    /// This makes the one button in onboarding "completely working" with minimal user intervention.
    func ensureReadyAndRunning() async {
        if let warmUp = launchWarmUpTask {
            await warmUp.value
        }

        if let existing = ensureReadyTask {
            await existing.value
            return
        }

        let task = Task { @MainActor in
            await performEnsureReadyAndRunning()
        }
        ensureReadyTask = task
        await task.value
        ensureReadyTask = nil
    }

    private func performEnsureReadyAndRunning() async {
        // Already serving — do not touch Docker or the container.
        if await isLocalWebReady() {
            status = .running
            lastError = nil
            return
        }

        // Another start/warm-up is in progress — wait for it, then re-check readiness.
        if isBusy {
            await currentTask?.value
            if await isLocalWebReady() {
                status = .running
                lastError = nil
            } else {
                await refreshStatus()
            }
            return
        }

        // Container is up but the web server is still booting — wait, do not run compose again.
        if await checkIfContainerIsRunning() {
            status = .starting
            lastError = nil
            if await waitForLocalWebReady(maxAttempts: 30, delaySeconds: 2) {
                status = .running
                lastError = nil
                return
            }
            await refreshStatus()
            return
        }

        // 0. Make sure the container runtime (Docker) is on the device and ready.
        // This is the key "automatically download the local private SearXNG container platform for them".
        let dockerReady = await downloadDockerDesktopIfNeededAndPrepare()
        if !dockerReady {
            // error already logged and lastError set
            if case .error = status {
                // already in error state
            } else {
                status = .error(lastError ?? "Docker setup failed")
            }
            return
        }

        // 1. Make sure we have the files (real secret etc.). Safe if already present.
        do {
            _ = try await provisionIfNeeded()
        } catch {
            lastError = "Failed to prepare local SearXNG folder: \(error.localizedDescription)"
            logs.append("❌ " + (lastError ?? ""))
            status = .error(lastError!)
            return
        }

        // Apply lean config optimization for existing installs (the common case).
        // This is what usually makes "SearXNG loading" go from painful to reasonable
        // on memory-constrained Macs.
        await ensureFastEngineConfigIfNeeded()
        await ensureMediaEnginesMigratedIfNeeded()

        // Pull when this Mac has never pulled the current pinned tag (not on every app launch).
        // App updates that bump `pinnedImageTag` auto-pull once; deliberate re-pulls use Settings → Instances.
        if needsPinnedImagePull() {
            logs.append("⬇️ Downloading the private SearXNG container image (\(SearxngDockerConfig.pinnedImageReference)). First run can take a few minutes depending on your connection and Docker Desktop.")
            await pullPinnedSearxngImage()
            if lastError == nil {
                markPinnedImagePulled()
            }
        }

        // Make sure compose file + settings.yml have the correct host port publish + inside listen-everywhere settings
        // (in case the folder is old or was created before fixes).
        await ensureDockerComposeHasBindVars()

        // 2. Start only when the container is not already running.
        await start()
    }

    /// Polls the local SearXNG HTTP endpoint until it responds or attempts are exhausted.
    func waitForLocalWebReady(
        maxAttempts: Int = 30,
        delaySeconds: UInt64 = 2,
        logProgress: Bool = false
    ) async -> Bool {
        for attempt in 0..<maxAttempts {
            if await isLocalWebReady() {
                return true
            }
            if logProgress, attempt % 5 == 4 {
                logs.append("⏳ Still waiting for web server (attempt \(attempt + 1)/\(maxAttempts))...")
            }
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(for: .seconds(delaySeconds))
            }
        }
        return false
    }

    /// User-initiated pull for the pinned SearXNG image. Does not restart the container automatically.
    /// Call `restart()` afterward if the image digest changed and you want the new layers running.
    func checkForSearxngImageUpdate() async {
        guard !isBusy else { return }
        logs.append("⬇️ Checking for SearXNG image update (\(SearxngDockerConfig.pinnedImageReference))…")
        await pullPinnedSearxngImage()
        if lastError == nil {
            logs.append("✅ Image pull finished. Use Restart if you want the container to run the freshly pulled layers.")
            markPinnedImagePulled()
        }
    }

    func needsPinnedImagePull() -> Bool {
        migrateImagePulledKeyIfNeeded()
        guard let pulledTag = UserDefaults.standard.string(forKey: SearxngDockerConfig.imagePulledTagKey) else {
            return true
        }
        return pulledTag != SearxngDockerConfig.pinnedImageTag
    }

    func markPinnedImagePulled() {
        UserDefaults.standard.set(SearxngDockerConfig.pinnedImageTag, forKey: SearxngDockerConfig.imagePulledTagKey)
        UserDefaults.standard.set(true, forKey: SearxngDockerConfig.imagePulledOnceKey)
    }

    /// Migrate the legacy bool-only pull flag to a tag-aware key so app updates can detect pin bumps.
    func migrateImagePulledKeyIfNeeded() {
        guard UserDefaults.standard.string(forKey: SearxngDockerConfig.imagePulledTagKey) == nil else { return }
        if UserDefaults.standard.bool(forKey: SearxngDockerConfig.imagePulledOnceKey) {
            UserDefaults.standard.set(SearxngDockerConfig.legacyUnknownPulledTag, forKey: SearxngDockerConfig.imagePulledTagKey)
        }
    }

    func pullPinnedSearxngImage() async {
        await ensureDockerComposeHasBindVars()
        await runDockerComposeCommand(["pull"])
    }

    /// Updates `projectFolderExists` via the XPC helper (required under App Sandbox).
    func updateProjectFolderExists() async {
        guard let proxy = DockerHelperClient.shared.proxy() else {
            projectFolderExists = false
            return
        }
        let composePath = projectFolderURL.appendingPathComponent("docker-compose.yml").path
        projectFolderExists = await proxy.fileExistsAsync(atPath: composePath)
    }

    /// One-time (or on-demand) optimization for existing installs.
    /// The full upstream settings.yml.example has 100+ engines. Even disabled ones make
    /// SearXNG's Python startup much slower and use more memory — especially painful on
    /// 8GB/16GB Macs where Docker Desktop's VM is already memory-starved.
    ///
    /// This safely detects the bloated default and replaces only the engines: section
    /// with our lean fast set (same list we use for brand-new setups). A backup is kept.
    ///
    /// IMPORTANT: The injected list must stay compatible with the engines shipped in
    /// the current `searxng/searxng:latest` image (see creation path for details).
    /// We also force-reapply on any polluted file that still contains ahmia/bandcamp
    /// dupes / stackoverflow / arxiv (even if the DidApplyLean key is already true)
    /// so that users hitting CrashLoop from prior bad writes get automatically fixed.
    func ensureFastEngineConfigIfNeeded() async {
        guard let proxy = DockerHelperClient.shared.proxy() else { return }
        let settingsPath = projectFolderURL.appendingPathComponent("searxng/settings.yml").path
        guard await proxy.fileExistsAsync(atPath: settingsPath) else { return }

        let didOptimizeKey = "Searxly.DidApplyLeanSearxngEngines"

        guard let data = await proxy.readFileAsync(atPath: settingsPath),
              let content = String(data: data, encoding: .utf8) else { return }

        // Robustness for users who previously hit a bad lean write (the cut bug that left
        // ahmia + duplicate bandcamp + arxiv/stackoverflow tail in settings.yml, causing
        // exactly the CrashLoop + "waiting for web server 30 times" the user reported).
        // Even if the DidApplyLean key is true (from the prior bad run), force a re-apply
        // + backup if any known crashing engines are still present.
        // `engine: artstation` is not shipped in the pinned image (FileNotFoundError on every boot);
        // `engine: flickr` (the API variant) needs a flickr.api_key we don't provide — the keyless
        // `flickr_noapi` is the correct engine. Both crash-loop SearXNG workers on cold start, so
        // detecting them here force-reapplies the corrected lean list to already-provisioned folders.
        let hasProblematicEngines = content.contains("  - name: ahmia") ||
                                    content.contains("  - name: stackoverflow") ||
                                    content.contains("  - name: arxiv") ||
                                    content.contains("engine: artstation") ||
                                    content.contains("engine: flickr\n") ||
                                    (content.components(separatedBy: "  - name: bandcamp").count > 2)

        if UserDefaults.standard.bool(forKey: didOptimizeKey) && !hasProblematicEngines {
            return
        }

        // Heuristic: bloated if it still contains several engines we know are in the old full example
        // and we have many engine definitions. (Also catches polluted files from the old cutter.)
        let bloatedSignals = ["360search", "adobe stock", "chinaso", "annas archive", "btdigg", "kickass"]
        let hasBloatedSignal = bloatedSignals.contains { content.contains($0) }
        let engineCount = content.components(separatedBy: "  - name:").count - 1

        guard hasBloatedSignal || engineCount > 25 || hasProblematicEngines else {
            // Looks like user already has a custom/lean list — don't touch it.
            UserDefaults.standard.set(true, forKey: didOptimizeKey)
            return
        }

        // Backup once (or again for polluted recovery) — read current content then write to backup path
        let backupPath = settingsPath + ".bak-pre-lean"
        let backupExists = await proxy.fileExistsAsync(atPath: backupPath)
        if !backupExists {
            if let backupData = await proxy.readFileAsync(atPath: settingsPath) {
                _ = await proxy.writeFileAsync(data: backupData, toPath: backupPath)
                logs.append("📦 Backed up your old settings.yml to settings.yml.bak-pre-lean before applying lean config.")
            }
        }

        // Use the same fast block we use for new folders
        // NOTE: This list must only contain engines that exist in the current
        // searxng/searxng:latest image. 'stackoverflow', 'arxiv', 'ahmia', and
        // 'bandcamp' (duplicate/ambiguous name or load failures) have been observed
        // to be missing or misconfigured in recent images, causing Python import
        // crashes, worker exits, and continuous restart loops. Keep the list minimal
        // for fast, reliable startup.
        let fastEnginesBlock = LeanSearxngEngines.block

        // Replace engines: section (same logic as the new-install path)
        if let enginesStart = content.range(of: "\nengines:") ?? content.range(of: "engines:") {
            var cutPoint = content.endIndex
            let searchFrom = enginesStart.upperBound
            let remaining = content[searchFrom...]

            let markers = ["\nui:", "\noutgoing:", "\nplugins:", "\n# communication", "\nserver:", "\nvalkey:", "\ndoi_resolvers:"]
            for m in markers {
                if let r = remaining.range(of: m) {
                    let distance = remaining.distance(from: remaining.startIndex, to: r.lowerBound)
                    let candidate = content.index(searchFrom, offsetBy: distance)
                    if candidate < cutPoint { cutPoint = candidate }
                }
            }

            // NOTE: The previous "\n\n last resort" splitter has been removed (see creation
            // path for full rationale). Engines: is the last section; we replace to EOF.
            // This + the hasProblematicEngines guard above ensures even previously-polluted
            // ~/searxng-local/searxng/settings.yml (the cause of the user's docker CrashLoop
            // with ahmia + bandcamp duplicate) gets a clean lean list on next Start or
            // auto "Download & start" button press.
            // We now preserve any tail after engines (e.g. doi_resolvers from original) and
            // guarantee default_doi_resolver is present to avoid KeyError in SearXNG startup.

            let before = content[..<enginesStart.lowerBound]
            let tail = content[cutPoint...]
            var newContent = before + "\n" + fastEnginesBlock
            if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                newContent += "\n" + tail
            }
            if !newContent.contains("default_doi_resolver:") {
                newContent += """

# DOI resolvers (preserved / injected by Searxly — required by SearXNG config loader in recent images)
doi_resolvers:
  oadoi.org: 'https://oadoi.org/'
  doi.org: 'https://doi.org/'
  sci-hub.se: 'https://sci-hub.se/'
  sci-hub.st: 'https://sci-hub.st/'
  sci-hub.ru: 'https://sci-hub.ru/'

default_doi_resolver: 'oadoi.org'
"""
            }

            if let newData = newContent.data(using: .utf8),
               await proxy.writeFileAsync(data: newData, toPath: settingsPath) {
                logs.append("✅ Lean/fast engine list applied cleanly to existing SearXNG config (only stable engines; any prior ahmia/bandcamp dupes or old tail removed by the fixed cutter + hasProblematic guard). doi_resolvers section ensured present to fix KeyError on startup.")
                logs.append("   Big startup speed win + no more engine crash loops on low-RAM Macs. The container will use the clean config on its next (re)start.")
                logs.append("   If it's currently running you may want to Stop → Start again (or just tap the main Download & start button).")
                UserDefaults.standard.set(true, forKey: didOptimizeKey)
            } else {
                logs.append("⚠️ Failed to optimize SearXNG config for speed (XPC write failed)")
            }
        }
    }

    /// Appends missing media engines to existing lean Searxly configs without wiping customizations.
    func ensureMediaEnginesMigratedIfNeeded() async {
        let migrationKey = "Searxly.DidMigrateMediaEngines2026"
        guard let proxy = DockerHelperClient.shared.proxy() else { return }
        let settingsPath = projectFolderURL.appendingPathComponent("searxng/settings.yml").path
        guard await proxy.fileExistsAsync(atPath: settingsPath),
              let data = await proxy.readFileAsync(atPath: settingsPath),
              var content = String(data: data, encoding: .utf8) else { return }

        // Only migrate lean Searxly-managed lists (has bing images).
        guard content.contains("  - name: bing images") else { return }

        var appendedAny = false
        for entry in LeanSearxngEngines.mediaMigrationEntries where !content.contains(entry.marker) {
            if let insertPoint = content.range(of: "\ndoi_resolvers:") ?? content.range(of: "\n# DOI resolvers") {
                content.insert(contentsOf: "\n" + entry.yaml, at: insertPoint.lowerBound)
            } else if let githubRange = content.range(of: "  - name: github") {
                content.insert(contentsOf: "\n" + entry.yaml, at: githubRange.lowerBound)
            } else {
                content.append("\n" + entry.yaml)
            }
            appendedAny = true
        }

        guard appendedAny else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        if let newData = content.data(using: .utf8),
           await proxy.writeFileAsync(data: newData, toPath: settingsPath) {
            logs.append("✅ Media engines migration applied (flickr, deviantart, artstation, dailymotion, vimeo). Restart SearXNG to pick up changes.")
            UserDefaults.standard.set(true, forKey: migrationKey)
        } else {
            logs.append("⚠️ Failed to migrate media engines (XPC write failed)")
        }
    }

}
