# MultiAI — macOS Multi-Account Desktop App Manager

**MultiAI** is a lightweight, native macOS (SwiftUI) manager that lets you create, organize, and run **multiple isolated accounts simultaneously** for installed desktop AI applications.

Each account is wrapped into its own standalone `.app` bundle inside `~/Applications/MultiAI Apps/` with a custom colored icon badge and an isolated profile directory (`~/Library/Application Support/MultiAI/Profiles/<UUID>`), so you can launch and switch between accounts from the Dashboard, Menu Bar, Spotlight, or Dock.

> [!NOTE]
> **Compatibility Status:** Currently, **only Antigravity (`Antigravity.app`) has been tested in practice**. MultiAI also detects and generates isolation profiles for other Electron apps (e.g., Claude Desktop), VS Code-based IDEs (e.g., Cursor, VS Code), Chromium Browser App Mode (`gemini.google.com`, `chatgpt.com`, `claude.ai`), and generic native macOS apps, though those have not yet been verified end-to-end.

---

## Requirements

- macOS 14.0 (Sonoma) or newer
- Xcode / Swift 5.10+ toolchain

---

## Build & Install

Run the unit tests:
```bash
swift test
```

Build `build/MultiAI.app`:
```bash
./scripts/build-app.sh
```

Build and install directly into `~/Applications/MultiAI.app`:
```bash
./scripts/build-app.sh --install
```

Launch the app:
```bash
open ~/Applications/MultiAI.app
```
(Or open **MultiAI** via Spotlight with `Cmd + Space`.)

---

## Usage Guide

### 1. Add an Account (`Cmd + N`)
1. Open **MultiAI** and click **Thêm Tài khoản / Add Account** (`Cmd + N`).
2. Select an installed desktop app (or browse for any `.app` bundle).
3. Enter a display name, pick a 1–2 character badge label and badge color, and review the auto-detected isolation settings.
4. Click **Tạo Tài khoản / Create** — MultiAI creates an isolated profile and builds a standalone `.app` wrapper in `~/Applications/MultiAI Apps/`.

### 2. Antigravity Notes
- MultiAI automatically enables **isolated `HOME`** for `Antigravity.app` so each account keeps its own login (`~/.gemini/jetski-standalone-oauth-token`), runtime state/conversations (`~/.gemini/antigravity/`), and `~/Library` (`credential-user-scope`, Keychain isolation, caches, logs).
- Top-level developer directories, CLI configs, and dotfiles from your real `~/` (`.config`, `.claude`, `.aws`, `.kube`, `.ssh`, `.gitconfig`, `workspace`, `Desktop`, etc.) are mirrored via symlinks into each isolated `HOME` (excluding `.gemini`, `.antigravity*`, and `Library`), without overriding `XDG_*` for Electron/IDE apps.
- Managed shell shims (`.zshenv`, `.bash_profile`, `.bashrc`) restore `HOME` in child terminal shells while preserving the isolated `HOME` during Antigravity's own startup environment probes, so macOS Keychain-backed CLIs (`gh`, `claude`, `git`) keep working without colliding Antigravity's Google OAuth session.
- Enable **Share Projects, MCP & Plugins** (`~/.gemini/config`) to share your sidebar Projects list, MCP servers, Plugins, `GEMINI.md`, and `trustedFolders.json` live across accounts.
  *(Active conversations and `language_server` databases in `~/.gemini/antigravity/` remain isolated per account so concurrent instances do not collide.)*

### 3. Launch, Focus & Stop
- Use the **Dashboard** or the **Menu Bar** icon to launch, focus, or stop any account and see live running status (PID).
- Standalone `.app` bundles in `~/Applications/MultiAI Apps/` can also be launched directly from Finder, Spotlight, or the Dock.

### 4. Window Tiling (Side-by-Side / Grid)
- Use the **Window Tiling** toolbar menu (or Menu Bar quick bar when 2+ accounts are running) to arrange windows in **Side by Side**, **Grid**, or **Stacked** layouts.
- On first use, grant **Accessibility** permission to **MultiAI** in **System Settings → Privacy & Security → Accessibility**.

### 5. Other Apps & Profile Storage
- **Electron / VS Code-based IDEs**: Isolated via `--user-data-dir` (and optional `--extensions-dir`).
- **Native macOS Keychain Apps (e.g., `ChatGPT.app`)**: macOS Keychain shares credentials across native app instances under the same macOS user. MultiAI provides a 1-click switch to **Browser App Mode** (`https://chatgpt.com` via Chrome/Edge) for independent sessions.
- **Data & Safe Removal**: Profiles are stored in `~/Library/Application Support/MultiAI/Profiles/<UUID>`. Deleting an account lets you keep or delete profile data; when deleting, MultiAI unlinks symlinks recursively before removing the profile folder so your real `~/` files are never touched.

---

## Project Structure

- `Sources/MultiAICore/` — Core models and services (`AppDiscoveryService`, `IconBadgeRenderer`, `AppBundleGenerator`, `ProcessTracker`, `WindowTiler`, `InstanceStore`)
- `Sources/MultiAI/` — SwiftUI views (`DashboardView`, `InstanceCardView`, `AddEditInstanceSheet`, `MenuBarView`)
- `Tests/MultiAITests/` — Unit tests (`MultiAITests`)
- `scripts/build-app.sh` — Release build, `.icns` icon generation, ad-hoc signing, and installation script
