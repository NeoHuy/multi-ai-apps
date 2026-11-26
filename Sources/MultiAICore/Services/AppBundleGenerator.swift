import AppKit
import Foundation

/// Resolved process launch configuration for an `AppInstance`.
public struct LaunchSpec: Equatable, Sendable {
    public let sourceAppPath: String
    public let arguments: [String]
    public let environment: [String: String]
}

/// Builds isolated profile directories, launcher scripts, and standalone `.app` bundles.
public enum AppBundleGenerator {
    /// Wraps a shell token in single quotes safely for `zsh`.
    public static func shellQuote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Parses shell-style extra CLI arguments while respecting single/double quotes and backslash escapes.
    public static func splitShellArguments(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaping = false
        var hasToken = false

        for ch in raw {
            if escaping {
                current.append(ch)
                escaping = false
                hasToken = true
                continue
            }

            if ch == "\\" && !inSingleQuote {
                escaping = true
                hasToken = true
                continue
            }

            if ch == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                hasToken = true
                continue
            }

            if ch == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                hasToken = true
                continue
            }

            if ch.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if hasToken {
                    result.append(current)
                    current = ""
                    hasToken = false
                }
                continue
            }

            current.append(ch)
            hasToken = true
        }

        if hasToken {
            result.append(current)
        }
        return result
    }

    /// Builds exact arguments and environment variables for launching an isolated instance.
    public static func buildLaunchSpec(
        for instance: AppInstance,
        paths: MultiAIPaths = .default,
        realHomeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> LaunchSpec {
        var args: [String] = []
        var env: [String: String] = [
            "MULTIAI_INSTANCE_ID": instance.id.uuidString
        ]

        let userDataPath = instance.userDataDirectoryURL(paths: paths).path
        let extensionsPath = instance.extensionsDirectoryURL(paths: paths).path
        let homePath = instance.homeDirectoryURL(paths: paths).path
        let xdgRoot = instance.xdgDirectoryURL(paths: paths)

        switch instance.engine {
        case .vscodeIDE:
            args.append("--user-data-dir=\(userDataPath)")
            if instance.isolateExtensions {
                args.append("--extensions-dir=\(extensionsPath)")
            }

        case .electron:
            args.append("--user-data-dir=\(userDataPath)")

        case .chromiumBrowserApp:
            args.append("--user-data-dir=\(userDataPath)")
            args.append("--no-first-run")
            args.append("--no-default-browser-check")
            if let rawURL = instance.targetURL?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawURL.isEmpty {
                args.append("--app=\(rawURL)")
            }

        case .nativeMacOS:
            env["XDG_CONFIG_HOME"] = xdgRoot.appendingPathComponent("config", isDirectory: true).path
            env["XDG_DATA_HOME"] = xdgRoot.appendingPathComponent("data", isDirectory: true).path
            env["XDG_CACHE_HOME"] = xdgRoot.appendingPathComponent("cache", isDirectory: true).path
        }

        if instance.isolateHomeDirectory {
            env["HOME"] = homePath
            env["MULTIAI_REAL_HOME"] = realHomeURL.standardizedFileURL.path
            env["MULTIAI_ISOLATED_HOME"] = homePath
        }

        for entry in instance.envVars {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            env[key] = entry.value
        }

        let extra = splitShellArguments(instance.extraArgs)
        args.append(contentsOf: extra)

        return LaunchSpec(
            sourceAppPath: instance.sourceAppPath,
            arguments: args,
            environment: env
        )
    }

    /// Generates the `zsh` launcher script embedded inside `Contents/MacOS/launcher`.
    public static func generateLauncherScript(
        for instance: AppInstance,
        paths: MultiAIPaths = .default,
        realHomeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        let spec = buildLaunchSpec(for: instance, paths: paths, realHomeURL: realHomeURL)
        var dirsToCreate: [String] = [
            instance.profileDirectoryURL(paths: paths).path
        ]

        switch instance.engine {
        case .vscodeIDE:
            dirsToCreate.append(instance.userDataDirectoryURL(paths: paths).path)
            if instance.isolateExtensions {
                dirsToCreate.append(instance.extensionsDirectoryURL(paths: paths).path)
            }
        case .electron, .chromiumBrowserApp:
            dirsToCreate.append(instance.userDataDirectoryURL(paths: paths).path)
        case .nativeMacOS:
            let xdg = instance.xdgDirectoryURL(paths: paths)
            dirsToCreate.append(xdg.appendingPathComponent("config", isDirectory: true).path)
            dirsToCreate.append(xdg.appendingPathComponent("data", isDirectory: true).path)
            dirsToCreate.append(xdg.appendingPathComponent("cache", isDirectory: true).path)
        }

        if instance.isolateHomeDirectory {
            dirsToCreate.append(instance.homeDirectoryURL(paths: paths).path)
        }

        var lines: [String] = [
            "#!/bin/zsh",
            "set -euo pipefail",
            ""
        ]

        for dir in dirsToCreate {
            lines.append("/bin/mkdir -p \(shellQuote(dir))")
        }

        lines.append("")

        if instance.isolateHomeDirectory {
            let resolvedRealHome = realHomeURL.standardizedFileURL.path
            let resolvedIsoHome = instance.homeDirectoryURL(paths: paths).standardizedFileURL.path
            let excludedCasePattern = excludedHomeMirrorItems.sorted().joined(separator: "|")
            lines.append("_multiai_real_home=\(shellQuote(resolvedRealHome))")
            lines.append("_multiai_iso_home=\(shellQuote(resolvedIsoHome))")
            lines.append("if [[ \"$_multiai_iso_home\" != \"$_multiai_real_home\" && -d \"$_multiai_real_home\" ]]; then")
            lines.append("  for _multiai_item in \"$_multiai_real_home\"/*(DN); do")
            lines.append("    _multiai_base=\"${_multiai_item:t}\"")
            lines.append("    case \"$_multiai_base\" in")
            lines.append("      \(excludedCasePattern))")
            lines.append("        continue")
            lines.append("        ;;")
            lines.append("    esac")
            lines.append("    if [[ \"$_multiai_item\" == \"$_multiai_iso_home\" || \"$_multiai_iso_home\" == \"$_multiai_item\"/* ]]; then")
            lines.append("      continue")
            lines.append("    fi")
            lines.append("    if [[ ! -e \"$_multiai_iso_home/$_multiai_base\" && ! -L \"$_multiai_iso_home/$_multiai_base\" ]]; then")
            lines.append("      /bin/ln -s \"$_multiai_item\" \"$_multiai_iso_home/$_multiai_base\" || true")
            lines.append("    fi")
            lines.append("  done")
            lines.append("fi")
            lines.append("")
        }

        var commandParts: [String] = ["exec", "/usr/bin/open", "-n"]
        for key in spec.environment.keys.sorted() {
            guard let val = spec.environment[key] else { continue }
            commandParts.append("--env")
            commandParts.append(shellQuote("\(key)=\(val)"))
        }
        commandParts.append("-a")
        commandParts.append(shellQuote(spec.sourceAppPath))

        if !spec.arguments.isEmpty {
            commandParts.append("--args")
            for arg in spec.arguments {
                commandParts.append(shellQuote(arg))
            }
        }

        lines.append(commandParts.joined(separator: " "))
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static let excludedHomeMirrorItems: Set<String> = [
        ".gemini",
        ".antigravity",
        ".antigravity-ide",
        ".antigravity-profiles",
        ".antigravity_cockpit",
        "Library",
        ".Trash",
        ".DS_Store",
        ".CFUserTextEncoding",
        ".zshenv",
        ".bashrc",
        ".bash_profile"
    ]

    // Never include antigravity/, jetski-standalone-oauth-token, oauth_creds.json, google_accounts.json, or state.json
    private static let sharedGeminiRootItems: [String] = [
        "GEMINI.md", "projects.json", "trustedFolders.json"
    ]

    private static let sharedGeminiConfigItems: [String] = [
        "projects", "config.json", "mcp_config.json", "plugins", "sidecars"
    ]

    /// Ensures the isolated profile directories exist on disk, mirroring safe HOME entries and shell shims when `isolateHomeDirectory` is enabled.
    public static func ensureProfileDirectories(
        for instance: AppInstance,
        paths: MultiAIPaths = .default,
        realHomeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        let fm = FileManager.default
        let profileDir = instance.profileDirectoryURL(paths: paths)
        try fm.createDirectory(at: profileDir, withIntermediateDirectories: true)

        switch instance.engine {
        case .vscodeIDE:
            try fm.createDirectory(at: instance.userDataDirectoryURL(paths: paths), withIntermediateDirectories: true)
            if instance.isolateExtensions {
                try fm.createDirectory(at: instance.extensionsDirectoryURL(paths: paths), withIntermediateDirectories: true)
            }
        case .electron, .chromiumBrowserApp:
            try fm.createDirectory(at: instance.userDataDirectoryURL(paths: paths), withIntermediateDirectories: true)
        case .nativeMacOS:
            let xdg = instance.xdgDirectoryURL(paths: paths)
            try fm.createDirectory(at: xdg.appendingPathComponent("config", isDirectory: true), withIntermediateDirectories: true)
            try fm.createDirectory(at: xdg.appendingPathComponent("data", isDirectory: true), withIntermediateDirectories: true)
            try fm.createDirectory(at: xdg.appendingPathComponent("cache", isDirectory: true), withIntermediateDirectories: true)
        }

        if instance.isolateHomeDirectory {
            let homeURL = instance.homeDirectoryURL(paths: paths)
            try fm.createDirectory(at: homeURL, withIntermediateDirectories: true)

            populateMirroredHomeSymlinks(
                in: homeURL,
                profileDirURL: profileDir,
                from: realHomeURL,
                fileManager: fm
            )
            try installChildShellShims(in: homeURL, fileManager: fm)
            try syncSharedAntigravityLinks(
                in: homeURL,
                from: realHomeURL,
                enabled: instance.shareAntigravityProjects,
                fileManager: fm
            )
        }
    }

    private static func populateMirroredHomeSymlinks(
        in isolatedHomeURL: URL,
        profileDirURL: URL,
        from realHomeURL: URL,
        fileManager fm: FileManager
    ) {
        let resolvedIsolatedHome = isolatedHomeURL.standardizedFileURL
        let resolvedRealHome = realHomeURL.standardizedFileURL
        guard resolvedIsolatedHome != resolvedRealHome else { return }

        guard let sourceItems = try? fm.contentsOfDirectory(
            at: resolvedRealHome,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: []
        ) else {
            return
        }

        let backupDir = profileDirURL.appendingPathComponent("shadowed-home-backup", isDirectory: true)

        for sourceURL in sourceItems {
            let itemName = sourceURL.lastPathComponent
            guard !excludedHomeMirrorItems.contains(itemName) else { continue }

            let resolvedSource = sourceURL.standardizedFileURL
            if resolvedSource == resolvedIsolatedHome
                || resolvedIsolatedHome.path.hasPrefix(resolvedSource.path + "/") {
                continue
            }

            let destURL = resolvedIsolatedHome.appendingPathComponent(itemName)

            if (try? fm.attributesOfItem(atPath: destURL.path)) != nil {
                let values = try? destURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                if values?.isSymbolicLink == true {
                    continue
                }

                if values?.isDirectory == true,
                   let contents = try? fm.contentsOfDirectory(atPath: destURL.path),
                   contents.isEmpty {
                    try? fm.removeItem(at: destURL)
                } else {
                    do {
                        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
                        var backupDest = backupDir.appendingPathComponent(itemName)
                        if (try? fm.attributesOfItem(atPath: backupDest.path)) != nil {
                            backupDest = backupDir.appendingPathComponent("\(itemName)-\(UUID().uuidString.prefix(8))")
                        }
                        try fm.moveItem(at: destURL, to: backupDest)
                    } catch {
                        continue
                    }
                }
            }

            try? fm.createSymbolicLink(at: destURL, withDestinationURL: sourceURL)
        }
    }

    private static func installChildShellShims(
        in isolatedHomeURL: URL,
        fileManager fm: FileManager
    ) throws {
        let shims: [(name: String, content: String)] = [
            (
                ".zshenv",
                """
                # Managed by MultiAI: restore real HOME in child shells so CLI tools & macOS Keychain work
                if [[ -n "${MULTIAI_REAL_HOME:-}" && -z "${ANTIGRAVITY_RESOLVING_ENVIRONMENT:-}" && -z "${VSCODE_RESOLVING_ENVIRONMENT:-}" ]]; then
                  export HOME="$MULTIAI_REAL_HOME"
                fi
                if [[ -n "${MULTIAI_REAL_HOME:-}" && -f "$MULTIAI_REAL_HOME/.zshenv" ]]; then
                  source "$MULTIAI_REAL_HOME/.zshenv"
                fi

                """
            ),
            (
                ".bash_profile",
                """
                # Managed by MultiAI: restore real HOME in child shells so CLI tools & macOS Keychain work
                if [ -n "${MULTIAI_REAL_HOME:-}" ] && [ -z "${ANTIGRAVITY_RESOLVING_ENVIRONMENT:-}" ] && [ -z "${VSCODE_RESOLVING_ENVIRONMENT:-}" ]; then
                  export HOME="$MULTIAI_REAL_HOME"
                fi
                if [ -n "${MULTIAI_REAL_HOME:-}" ] && [ -f "$MULTIAI_REAL_HOME/.bash_profile" ]; then
                  . "$MULTIAI_REAL_HOME/.bash_profile"
                fi

                """
            ),
            (
                ".bashrc",
                """
                # Managed by MultiAI: restore real HOME in child shells so CLI tools & macOS Keychain work
                if [ -n "${MULTIAI_REAL_HOME:-}" ] && [ -z "${ANTIGRAVITY_RESOLVING_ENVIRONMENT:-}" ] && [ -z "${VSCODE_RESOLVING_ENVIRONMENT:-}" ]; then
                  export HOME="$MULTIAI_REAL_HOME"
                fi
                if [ -n "${MULTIAI_REAL_HOME:-}" ] && [ -f "$MULTIAI_REAL_HOME/.bashrc" ]; then
                  . "$MULTIAI_REAL_HOME/.bashrc"
                fi

                """
            )
        ]

        for shim in shims {
            let shimURL = isolatedHomeURL.appendingPathComponent(shim.name, isDirectory: false)
            // Always remove any existing entry (especially symlinks from older profiles) before writing
            if (try? fm.attributesOfItem(atPath: shimURL.path)) != nil {
                try fm.removeItem(at: shimURL)
            }
            try shim.content.write(to: shimURL, atomically: true, encoding: .utf8)
        }
    }

    /// Returns true if an isolated-HOME instance's standalone `.app` launcher predates `MULTIAI_REAL_HOME`.
    public static func needsLauncherUpgrade(
        for instance: AppInstance,
        paths: MultiAIPaths = .default
    ) -> Bool {
        guard instance.isolateHomeDirectory, instance.createStandaloneApp else {
            return false
        }

        let appPath: String
        if let existing = instance.standaloneAppPath, !existing.isEmpty {
            appPath = existing
        } else {
            appPath = instance.expectedStandaloneAppURL(paths: paths).path
        }

        let launcherURL = URL(fileURLWithPath: appPath, isDirectory: true)
            .appendingPathComponent("Contents/MacOS/launcher", isDirectory: false)
        guard FileManager.default.fileExists(atPath: launcherURL.path),
              let contents = try? String(contentsOf: launcherURL, encoding: .utf8) else {
            return false
        }

        return !contents.contains("MULTIAI_REAL_HOME=")
    }

    private static func syncSharedAntigravityLinks(
        in isolatedHomeURL: URL,
        from realHomeURL: URL,
        enabled: Bool,
        fileManager fm: FileManager
    ) throws {
        let resolvedIsolatedHome = isolatedHomeURL.standardizedFileURL
        let resolvedRealHome = realHomeURL.standardizedFileURL
        guard resolvedIsolatedHome != resolvedRealHome else { return }

        let isoGemini = resolvedIsolatedHome.appendingPathComponent(".gemini", isDirectory: true)
        let isoConfig = isoGemini.appendingPathComponent("config", isDirectory: true)
        let realGemini = resolvedRealHome.appendingPathComponent(".gemini", isDirectory: true)
        let realConfig = realGemini.appendingPathComponent("config", isDirectory: true)

        if enabled {
            try fm.createDirectory(at: isoConfig, withIntermediateDirectories: true)

            for item in sharedGeminiRootItems {
                linkSharedItem(
                    from: realGemini.appendingPathComponent(item),
                    to: isoGemini.appendingPathComponent(item),
                    fileManager: fm
                )
            }
            for item in sharedGeminiConfigItems {
                linkSharedItem(
                    from: realConfig.appendingPathComponent(item),
                    to: isoConfig.appendingPathComponent(item),
                    fileManager: fm
                )
            }
        } else {
            for item in sharedGeminiRootItems {
                unlinkIfSymlink(at: isoGemini.appendingPathComponent(item), fileManager: fm)
            }
            for item in sharedGeminiConfigItems {
                unlinkIfSymlink(at: isoConfig.appendingPathComponent(item), fileManager: fm)
            }
        }
    }

    private static func linkSharedItem(from sourceURL: URL, to destURL: URL, fileManager fm: FileManager) {
        guard fm.fileExists(atPath: sourceURL.path) else { return }

        if (try? fm.attributesOfItem(atPath: destURL.path)) != nil {
            let values = try? destURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if values?.isSymbolicLink == true {
                return
            }
            // Replace an empty directory created by an earlier isolated launch, never overwrite non-empty data
            if values?.isDirectory == true,
               let contents = try? fm.contentsOfDirectory(atPath: destURL.path),
               contents.isEmpty {
                try? fm.removeItem(at: destURL)
            } else {
                return
            }
        }

        try? fm.createSymbolicLink(at: destURL, withDestinationURL: sourceURL)
    }

    private static func unlinkIfSymlink(at url: URL, fileManager fm: FileManager) {
        let isSymlink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
        if isSymlink {
            try? fm.removeItem(at: url)
        }
    }

    /// Safely deletes an isolated profile directory by unlinking all symlinks inside it recursively first.
    public static func removeProfileDirectorySafely(at profileURL: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: profileURL.path) else { return }

        unlinkSymlinksRecursively(in: profileURL, fileManager: fm)
        try fm.removeItem(at: profileURL)
    }

    private static func unlinkSymlinksRecursively(in directory: URL, fileManager fm: FileManager) {
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: []
        ) else {
            return
        }

        for item in items {
            let values = try? item.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            if values?.isSymbolicLink == true {
                // Remove only the symlink itself and never descend into its target
                try? fm.removeItem(at: item)
            } else if values?.isDirectory == true {
                unlinkSymlinksRecursively(in: item, fileManager: fm)
            }
        }
    }

    /// Creates or updates the standalone `.app` wrapper bundle in `~/Applications/MultiAI Apps/`.
    @discardableResult
    public static func createOrUpdateStandaloneApp(
        for instance: AppInstance,
        paths: MultiAIPaths = .default,
        registerWithLaunchServices: Bool = true
    ) throws -> URL {
        let fm = FileManager.default
        try ensureProfileDirectories(for: instance, paths: paths)
        try fm.createDirectory(at: paths.standaloneAppsDirectory, withIntermediateDirectories: true)

        let targetURL = instance.expectedStandaloneAppURL(paths: paths)

        // Remove previous bundle if renamed
        if let previousPath = instance.standaloneAppPath,
           !previousPath.isEmpty,
           URL(fileURLWithPath: previousPath).standardizedFileURL != targetURL.standardizedFileURL {
            try? removeStandaloneApp(at: previousPath, paths: paths)
        }

        let contentsURL = targetURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        try fm.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        // Write Info.plist safely via PropertyListSerialization
        let shortID = instance.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        let plistDict: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": instance.name,
            "CFBundleExecutable": "launcher",
            "CFBundleIconFile": "AppIcon",
            "CFBundleIdentifier": "com.multiai.instance.\(shortID)",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": instance.name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": true,
            "NSHighResolutionCapable": true
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist", isDirectory: false)
        try plistData.write(to: infoPlistURL, options: [.atomic])

        // Write launcher script with +x permissions
        let script = generateLauncherScript(for: instance, paths: paths)
        let launcherURL = macOSURL.appendingPathComponent("launcher", isDirectory: false)
        try script.write(to: launcherURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: launcherURL.path)

        // Write multi-resolution badged .icns
        let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns", isDirectory: false)
        try IconBadgeRenderer.writeICNS(to: icnsURL) { size in
            try IconBadgeRenderer.renderBadgedIcon(
                sourceAppPath: instance.sourceAppPath,
                badgeText: instance.normalizedBadgeText,
                badgeColor: instance.badgeColor,
                pixelSize: size
            )
        }

        // Write profile metadata for transparency
        let metaEncoder = JSONEncoder()
        metaEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        metaEncoder.dateEncodingStrategy = .iso8601
        if let metaData = try? metaEncoder.encode(instance) {
            let metaURL = instance.profileDirectoryURL(paths: paths).appendingPathComponent("meta.json", isDirectory: false)
            try? metaData.write(to: metaURL, options: [.atomic])
        }

        // Touch bundle modification date so Finder refreshes icon cache
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: targetURL.path)

        if registerWithLaunchServices {
            bestEffortRun("/usr/bin/codesign", arguments: ["--force", "--deep", "--sign", "-", targetURL.path])
            bestEffortRun(
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
                arguments: ["-f", targetURL.path]
            )
            NSWorkspace.shared.noteFileSystemChanged(targetURL.path)
        }

        return targetURL
    }

    /// Safely removes a generated `.app` bundle only if it lives inside `paths.standaloneAppsDirectory`.
    public static func removeStandaloneApp(
        at path: String,
        paths: MultiAIPaths = .default
    ) throws {
        let fm = FileManager.default
        let targetURL = URL(fileURLWithPath: path).standardizedFileURL
        let allowedRoot = paths.standaloneAppsDirectory.standardizedFileURL.path

        guard targetURL.path.hasPrefix(allowedRoot + "/"),
              targetURL.pathExtension.lowercased() == "app",
              fm.fileExists(atPath: targetURL.path) else {
            return
        }
        try fm.removeItem(at: targetURL)
    }

    private static func bestEffortRun(_ executable: String, arguments: [String]) {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
