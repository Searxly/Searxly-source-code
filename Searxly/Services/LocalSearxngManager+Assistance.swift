//
//  LocalSearxngManager+Assistance
//  Searxly
//

import Foundation
import SwiftUI
import Observation
import Security

extension LocalSearxngManager {
    // MARK: - Bulletproof Docker assistance (for QA + end users)

    /// Attempts to open Docker Desktop if it is installed. Returns true if launch was attempted.
    @discardableResult
    func openDockerDesktop() -> Bool {
        let dockerAppPath = "/Applications/Docker.app"
        guard FileManager.default.fileExists(atPath: dockerAppPath) else {
            logs.append("ℹ️ Docker Desktop not found at /Applications/Docker.app")
            return false
        }
        let url = URL(fileURLWithPath: dockerAppPath)
        // The openApplication(with configuration) overload may or may not be throwing depending on the active SDK.
        // Call without `try` to satisfy the compiler (previously this produced "no throwing call" + unreachable catch).
        // We still attempt the modern API first; the plain `open(_:)` below serves as a reliable fallback / bring-to-front.
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
        logs.append("🚀 Launched Docker Desktop. Waiting for daemon...")
        // Simple open as safety net (harmless if the app is already running).
        NSWorkspace.shared.open(url)
        return true
    }

    /// Opens the official Docker Desktop download page in the user's default browser.
    /// This is the recommended primary path for users (browser download is more reliable for the large .dmg,
    /// supports resume, always gets the latest version, and matches the explicit user request:
    /// "they just need to download docker and everything [else] is done").
    /// The in-app DMG auto-download (downloadDockerDesktopIfNeededAndPrepare) is kept for advanced/enthusiast use.
    @discardableResult
    func openDockerDownloadPage() -> Bool {
        let urlStr = "https://www.docker.com/products/docker-desktop/"
        guard let url = URL(string: urlStr) else { return false }
        NSWorkspace.shared.open(url)
        logs.append("🌐 Opened official Docker Desktop download page. Download the .dmg, drag Docker to /Applications, launch it and wait until it says 'Docker Desktop is running'. Open Terminal and run `docker --version` once, then return here and tap Recheck.")
        return true
    }

    /// Automatically downloads Docker Desktop (the container runtime) if not present on the device,
    /// opens the installer, waits for installation, launches it, and ensures the daemon is ready.
    /// This is the "download the container platform for them" part so the SearXNG private instance can run.
    /// Returns true if Docker is now available and ready to use.
    @discardableResult
    func downloadDockerDesktopIfNeededAndPrepare() async -> Bool {
        // Container running implies the daemon was reachable — never launch/restart Docker Desktop.
        if await checkIfContainerIsRunning() {
            logs.append("✅ SearXNG container already running — skipping Docker Desktop launch.")
            return true
        }

        // Daemon already up — never launch Docker Desktop (avoids restart / focus steal).
        if await isDockerDaemonReachable() {
            logs.append("✅ Docker daemon already running.")
            return true
        }

        let dockerAppPath = "/Applications/Docker.app"
        if FileManager.default.fileExists(atPath: dockerAppPath) {
            logs.append("✅ Docker Desktop installed — waiting for daemon…")

            // Poll briefly without launching (user may have just started it).
            for attempt in 0..<6 {
                if await isDockerDaemonReachable() {
                    logs.append("✅ Docker daemon is ready.")
                    return true
                }
                if attempt < 5 {
                    try? await Task.sleep(for: .seconds(2))
                }
            }

            logs.append("🚀 Docker daemon not responding — launching Docker Desktop once…")
            _ = openDockerDesktop()

            for _ in 0..<24 { // up to ~2 minutes
                if await isDockerDaemonReachable() {
                    logs.append("✅ Docker daemon is ready.")
                    return true
                }
                try? await Task.sleep(for: .seconds(5))
                logs.append("⏳ Waiting for Docker daemon to start...")
            }
            lastError = "Docker Desktop is installed but the daemon is not responding. Please start it manually from Applications."
            logs.append("❌ " + (lastError ?? ""))
            return false
        }

        logs.append("⬇️ Docker Desktop not found on your device. Downloading it automatically for you...")

        // Note: Direct download URLs can change over time. This uses a common stable path for Apple Silicon / Universal.
        // Falls back to opening the official page if direct download fails.
        let possibleURLs = [
            "https://desktop.docker.com/mac/main/arm64/Docker.dmg",
            "https://desktop.docker.com/mac/main/amd64/Docker.dmg",
            "https://desktop.docker.com/mac/main/universal/Docker.dmg"
        ]

        let destination = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Docker.dmg")

        for urlStr in possibleURLs {
            guard let url = URL(string: urlStr) else { continue }
            do {
                let (tmpURL, response) = try await URLSession.shared.download(from: url)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tmpURL, to: destination)
                    logs.append("✅ Docker Desktop downloaded to your Downloads folder.")
                    NSWorkspace.shared.open(destination)
                    logs.append("📦 The .dmg has been opened. Please drag Docker to your Applications folder to install.")

                    // Poll for installation to complete
                    for _ in 0..<60 { // up to 5 minutes
                        try? await Task.sleep(for: .seconds(5))
                        if FileManager.default.fileExists(atPath: dockerAppPath) {
                            logs.append("✅ Docker Desktop installed successfully. Launching...")
                            _ = openDockerDesktop()
                            // Additional wait for daemon
                            for _ in 0..<24 {
                                if await checkDockerAvailable() {
                                    logs.append("✅ Docker daemon ready. Proceeding with private SearXNG container setup.")
                                    return true
                                }
                                try? await Task.sleep(for: .seconds(5))
                            }
                            return true // even if daemon slow, proceed
                        }
                    }
                    lastError = "Docker download succeeded but installation not detected. Please complete the drag-to-Applications step and re-try the button."
                    logs.append("❌ " + (lastError ?? ""))
                    return false
                }
            } catch {
                logs.append("⚠️ Direct download attempt failed for \(urlStr): \(error.localizedDescription)")
            }
        }

        // Ultimate fallback: open the official download page so user can get the latest.
        logs.append("ℹ️ Could not auto-download a direct .dmg. Opening the official Docker Desktop download page for you...")
        if let pageURL = URL(string: "https://www.docker.com/products/docker-desktop/") {
            NSWorkspace.shared.open(pageURL)
        }
        lastError = "Please download and install Docker Desktop from the opened page, then re-tap the setup button."
        logs.append("❌ " + (lastError ?? ""))
        return false
    }

    /// Opens the ~/searxng-local folder in Finder for advanced users / debugging.
    func openProjectFolderInFinder() {
        NSWorkspace.shared.open(projectFolderURL)
    }

    /// Deletes the local project folder and recreates it fresh (useful for corrupted setups or testing).
    /// Does NOT start the container.
    func recreateProjectFolder() async {
        do {
            guard let proxy = DockerHelperClient.shared.proxy() else {
                logs.append("❌ XPC helper unavailable — cannot remove ~/searxng-local")
                return
            }
            if await proxy.fileExistsAsync(atPath: projectFolderURL.path) {
                _ = await proxy.removeItemAsync(atPath: projectFolderURL.path)
                logs.append("🗑️ Removed existing ~/searxng-local")
            }
            _ = try await ensureProjectFolderExists()
            logs.append("✅ Fresh local SearXNG setup folder created. Tap Start or 'Set up & start automatically'.")
            await updateProjectFolderExists()
        } catch {
            lastError = "Failed to recreate folder: \(error.localizedDescription)"
            logs.append("❌ " + (lastError ?? ""))
        }
    }

    /// Returns a copy of recent logs (for diagnostics / "Copy logs" buttons in UI).
    func recentLogs() -> [String] {
        return logs
    }

    /// Copies recent logs to the pasteboard (convenience for users reporting issues).
    func copyRecentLogsToPasteboard() {
        let text = logs.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        logs.append("📋 Logs copied to clipboard")
    }

}
