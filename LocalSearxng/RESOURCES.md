# Local SearXNG Resources (Bundled with Searxly)

This folder is the **single source of truth** for the files that Searxly bundles into the app and copies to `~/searxng-local/` on first automatic (or manual) setup of the user's private local SearXNG instance.

## Contents
- `docker-compose.yml` — the compose file (mounts the config dir + the premium Searxly `custom/` theme).
- `searxng/settings.yml.example` — safe template (placeholder secret). At runtime Searxly generates a strong random `secret_key` and writes a real `settings.yml`.
- `searxng/limiter.toml` — permissive limiter for local private use.
- `custom/` — the premium xAI/SpaceX-inspired Searxly theme (templates + static CSS). Mounted into the container so the beautiful minimal results page is present from day one.

## How bundling works
1. In Xcode: the `LocalSearxng` folder must be added to the **Searxly** target via **Add Files → Create folder references** (not "Create groups").
2. After changes: **Product > Clean Build Folder** (⇧⌘K) then build.
3. At runtime `LocalSearxngManager` uses defensive `Bundle.main` lookups (it searches flat, under `LocalSearxng/`, under `local-searxng/`, etc.) so it works reliably regardless of how the folder reference landed inside the .app bundle.

The high-level `provisionIfNeeded()` / `ensureReadyAndRunning()` (and the old `ensureProjectFolderExists`) do the copy + secret injection + theme deployment into the user's `~/searxng-local`.

## For developers
- Keep this folder minimal. Stray files (including old .txt docs) will be bundled and copied to every user's machine.
- The committed `settings.yml.example` must never contain a real secret.
- The manager now guarantees a real secret is written for new setups.
- Duplicate `local-searxng/` folders at the project root have been removed in favor of this canonical location.

## Docker CLI requirement (user education)
After the user installs Docker Desktop they **must** go to Docker Desktop → Settings → General and enable "Docker CLI". Sandboxed macOS apps cannot see the `docker` binary otherwise. The onboarding and Settings UIs give clear guidance and a "check again" button.

This setup (combined with the automatic flow in onboarding) means that after downloading Searxly, a user only needs to install Docker Desktop + tick the one CLI checkbox. Everything else for a working, private, local SearXNG with the Searxly theme is handled automatically via big buttons.

An optional "Manual / advanced" disclosure is also surfaced in onboarding and Settings → Instances for power users who want folder-only creation, copy-paste compose commands, or a custom local URL.
