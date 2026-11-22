import Foundation

/// Scans installed `.app` bundles on macOS and detects the best isolation engine for each.
public enum AppDiscoveryService {
    private static let chromiumBundlePrefixes: [String] = [
        "com.google.chrome",
        "com.microsoft.edgemac",
        "com.brave.browser",
        "org.chromium.chromium",
        "company.thebrowser.browser",
        "com.vivaldi.vivaldi",
        "com.operasoftware.opera"
    ]

    private static let priorityNameKeywords: [String] = [
        "claude", "antigravity", "chatgpt", "cursor", "windsurf",
        "perplexity", "codex", "ollama", "lm studio", "poe",
        "gemini", "grok", "deepseek", "vscode", "visual studio code",
        "google chrome", "microsoft edge", "brave", "arc"
    ]

    private static let priorityBundlePrefixes: [String] = [
        "com.anthropic.claudefordesktop",
        "com.google.antigravity",
        "com.openai.",
        "com.todesktop.",
        "com.exafunction.",
        "ai.perplexity.",
        "com.microsoft.vscode",
        "com.google.chrome",
        "com.microsoft.edgemac",
        "com.brave.browser",
        "company.thebrowser.browser"
    ]

    private static let knownKeychainNativeBundleIDs: Set<String> = [
        "com.openai.codex",
        "com.openai.chat"
    ]

    private static let homeIsolatedBundlePrefixes: [String] = [
        "com.google.antigravity"
    ]

    /// Scans `/Applications` and `~/Applications` non-recursively, returning priority AI/Browser apps first.
    public static func scanInstalledApps(
        searchDirectories: [URL]? = nil,
        paths: MultiAIPaths = .default
    ) -> [InstalledApp] {
        let fm = FileManager.default
        let directories = searchDirectories ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        let skippedNames: Set<String> = [
            "MultiAI.app",
            "MultiAI Apps",
            "Chrome Apps.localized",
            "Edge Apps.localized"
        ]

        var seenPaths = Set<String>()
        var results: [InstalledApp] = []

        for dir in directories {
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for item in items {
                guard item.pathExtension.lowercased() == "app" else { continue }
                let fileName = item.lastPathComponent
                if skippedNames.contains(fileName) { continue }
                if item.standardizedFileURL.path.hasPrefix(paths.standaloneAppsDirectory.standardizedFileURL.path) {
                    continue
                }

                let resolvedPath = item.standardizedFileURL.path
                guard !seenPaths.contains(resolvedPath) else { continue }
                seenPaths.insert(resolvedPath)

                if let app = inspectApp(at: resolvedPath, checkEntitlementsOnUnknownNative: false) {
                    results.append(app)
                }
            }
        }

        return results.sorted(by: sortApps)
    }

    /// Inspects a single `.app` bundle on disk and determines its metadata and isolation engine.
    public static func inspectApp(
        at appPath: String,
        checkEntitlementsOnUnknownNative: Bool = true
    ) -> InstalledApp? {
        let appURL = URL(fileURLWithPath: appPath, isDirectory: true)
        let infoPlistURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Info.plist", isDirectory: false)

        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }

        let fallbackName = appURL.deletingPathExtension().lastPathComponent
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? fallbackName
        let bundleID = (plist["CFBundleIdentifier"] as? String) ?? ""
        let executable = (plist["CFBundleExecutable"] as? String) ?? fallbackName

        let engine = detectEngine(at: appURL, bundleIdentifier: bundleID)
        let isPriority = matchesPriorityApp(name: name, bundleIdentifier: bundleID)
        let lowerBundle = bundleID.lowercased()
        let recommendsIsolatedHome = homeIsolatedBundlePrefixes.contains(where: { lowerBundle.hasPrefix($0) })

        let usesKeychain: Bool
        if engine == .nativeMacOS {
            if knownKeychainNativeBundleIDs.contains(lowerBundle) {
                usesKeychain = true
            } else if checkEntitlementsOnUnknownNative || isPriority {
                usesKeychain = hasKeychainEntitlement(at: appPath)
            } else {
                usesKeychain = false
            }
        } else {
            usesKeychain = recommendsIsolatedHome
        }

        return InstalledApp(
            name: name,
            path: appURL.standardizedFileURL.path,
            bundleIdentifier: bundleID,
            executableName: executable,
            detectedEngine: engine,
            usesKeychainIsolationCaveat: usesKeychain,
            recommendsIsolatedHome: recommendsIsolatedHome,
            isPriorityAIApp: isPriority
        )
    }

    /// Determines the isolation engine from bundle identifier and bundle internals.
    public static func detectEngine(at appURL: URL, bundleIdentifier: String) -> IsolationEngine {
        let lowerBundle = bundleIdentifier.lowercased()
        if chromiumBundlePrefixes.contains(where: { lowerBundle.hasPrefix($0) }) {
            return .chromiumBrowserApp
        }

        let fm = FileManager.default
        let electronFramework = appURL
            .appendingPathComponent("Contents/Frameworks/Electron Framework.framework", isDirectory: true)
        if fm.fileExists(atPath: electronFramework.path) {
            let productJSON = appURL
                .appendingPathComponent("Contents/Resources/app/product.json", isDirectory: false)
            if fm.fileExists(atPath: productJSON.path) {
                return .vscodeIDE
            }
            return .electron
        }

        return .nativeMacOS
    }

    private static func matchesPriorityApp(name: String, bundleIdentifier: String) -> Bool {
        let lowerName = name.lowercased()
        let lowerBundle = bundleIdentifier.lowercased()
        if priorityBundlePrefixes.contains(where: { lowerBundle.hasPrefix($0) }) {
            return true
        }
        return priorityNameKeywords.contains(where: { lowerName.contains($0) })
    }

    private static func hasKeychainEntitlement(at appPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", ":-", appPath]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8) {
                return text.contains("keychain-access-groups") || text.contains("com.apple.security.application-groups")
            }
        } catch {
            return false
        }
        return false
    }

    private static func sortApps(_ lhs: InstalledApp, _ rhs: InstalledApp) -> Bool {
        if lhs.isPriorityAIApp != rhs.isPriorityAIApp {
            return lhs.isPriorityAIApp && !rhs.isPriorityAIApp
        }
        if lhs.isPriorityAIApp && rhs.isPriorityAIApp && lhs.isBrowser != rhs.isBrowser {
            // Put dedicated AI desktop apps ahead of Chromium browsers
            return !lhs.isBrowser && rhs.isBrowser
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}
