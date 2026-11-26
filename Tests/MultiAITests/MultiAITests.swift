import Foundation
import XCTest
@testable import MultiAICore

final class MultiAITests: XCTestCase {
    private func makeTempPaths() throws -> MultiAIPaths {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiAITests-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let apps = root.appendingPathComponent("StandaloneApps", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        return MultiAIPaths(appSupportDirectory: support, standaloneAppsDirectory: apps)
    }

    private func cleanupTempPaths(_ paths: MultiAIPaths) {
        let root = paths.appSupportDirectory.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - 1. Shell Quoting & Argument Splitting

    func testShellQuoteAndSplitArguments() {
        XCTAssertEqual(AppBundleGenerator.shellQuote("simple"), "'simple'")
        XCTAssertEqual(AppBundleGenerator.shellQuote("hello world"), "'hello world'")
        XCTAssertEqual(AppBundleGenerator.shellQuote("it's"), "'it'\\''s'")

        let parsed = AppBundleGenerator.splitShellArguments(
            #"--flag="hello world" --single='foo bar' --plain --escaped\ space"#
        )
        XCTAssertEqual(parsed, [
            "--flag=hello world",
            "--single=foo bar",
            "--plain",
            "--escaped space"
        ])
    }

    // MARK: - 2. Launch Spec & Launcher Script for All 4 Engines

    func testBuildLaunchSpecAndScriptForAllEngines() throws {
        let paths = try makeTempPaths()
        defer { cleanupTempPaths(paths) }

        // 1) VSCode / Antigravity IDE
        let ideInstance = AppInstance(
            id: UUID(),
            name: "Antigravity Work",
            sourceAppPath: "/Applications/Antigravity.app",
            sourceAppName: "Antigravity",
            sourceBundleID: "com.google.antigravity",
            engine: .vscodeIDE,
            badgeText: "W",
            badgeColor: .blue,
            isolateExtensions: true,
            extraArgs: "--new-window",
            envVars: [EnvVarEntry(key: "CUSTOM_KEY", value: "abc 123")]
        )
        let ideSpec = AppBundleGenerator.buildLaunchSpec(for: ideInstance, paths: paths)
        XCTAssertTrue(ideSpec.arguments.contains("--user-data-dir=\(ideInstance.userDataDirectoryURL(paths: paths).path)"))
        XCTAssertTrue(ideSpec.arguments.contains("--extensions-dir=\(ideInstance.extensionsDirectoryURL(paths: paths).path)"))
        XCTAssertTrue(ideSpec.arguments.contains("--new-window"))
        XCTAssertEqual(ideSpec.environment["CUSTOM_KEY"], "abc 123")
        XCTAssertEqual(ideSpec.environment["MULTIAI_INSTANCE_ID"], ideInstance.id.uuidString)

        let ideScript = AppBundleGenerator.generateLauncherScript(for: ideInstance, paths: paths)
        XCTAssertTrue(ideScript.contains("#!/bin/zsh"))
        XCTAssertTrue(ideScript.contains("exec /usr/bin/open -n"))
        XCTAssertTrue(ideScript.contains("--env 'CUSTOM_KEY=abc 123'"))
        XCTAssertTrue(ideScript.contains("--extensions-dir="))

        // 2) Electron (Claude)
        let electronInstance = AppInstance(
            id: UUID(),
            name: "Claude Personal",
            sourceAppPath: "/Applications/Claude.app",
            sourceAppName: "Claude",
            sourceBundleID: "com.anthropic.claudefordesktop",
            engine: .electron,
            badgeText: "P",
            badgeColor: .purple
        )
        let electronSpec = AppBundleGenerator.buildLaunchSpec(for: electronInstance, paths: paths)
        XCTAssertEqual(
            electronSpec.arguments,
            ["--user-data-dir=\(electronInstance.userDataDirectoryURL(paths: paths).path)"]
        )

        // 3) Chromium Browser App Mode (Gemini)
        let browserInstance = AppInstance(
            id: UUID(),
            name: "Gemini 2",
            sourceAppPath: "/Applications/Google Chrome.app",
            sourceAppName: "Google Chrome",
            sourceBundleID: "com.google.Chrome",
            engine: .chromiumBrowserApp,
            badgeText: "2",
            badgeColor: .teal,
            targetURL: "https://gemini.google.com"
        )
        let browserSpec = AppBundleGenerator.buildLaunchSpec(for: browserInstance, paths: paths)
        XCTAssertTrue(browserSpec.arguments.contains("--user-data-dir=\(browserInstance.userDataDirectoryURL(paths: paths).path)"))
        XCTAssertTrue(browserSpec.arguments.contains("--no-first-run"))
        XCTAssertTrue(browserSpec.arguments.contains("--no-default-browser-check"))
        XCTAssertTrue(browserSpec.arguments.contains("--app=https://gemini.google.com"))

        // 4) Native macOS
        let nativeInstance = AppInstance(
            id: UUID(),
            name: "ChatGPT Native 2",
            sourceAppPath: "/Applications/ChatGPT.app",
            sourceAppName: "ChatGPT",
            sourceBundleID: "com.openai.codex",
            engine: .nativeMacOS,
            badgeText: "N",
            badgeColor: .orange,
            isolateHomeDirectory: true
        )
        let nativeSpec = AppBundleGenerator.buildLaunchSpec(for: nativeInstance, paths: paths)
        XCTAssertEqual(
            nativeSpec.environment["XDG_CONFIG_HOME"],
            nativeInstance.xdgDirectoryURL(paths: paths).appendingPathComponent("config").path
        )
        XCTAssertEqual(
            nativeSpec.environment["HOME"],
            nativeInstance.homeDirectoryURL(paths: paths).path
        )
    }

    func testCreateStandaloneAppInIsolatedTempDirectory() throws {
        let paths = try makeTempPaths()
        defer { cleanupTempPaths(paths) }

        let instance = AppInstance(
            name: "Test & Claude <1>",
            sourceAppPath: "/Applications",
            sourceAppName: "Claude",
            sourceBundleID: "com.anthropic.claudefordesktop",
            engine: .electron,
            badgeText: "1",
            badgeColor: .blue
        )

        let bundleURL = try AppBundleGenerator.createOrUpdateStandaloneApp(
            for: instance,
            paths: paths,
            registerWithLaunchServices: false
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.path))
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let launcherURL = bundleURL.appendingPathComponent("Contents/MacOS/launcher")
        let icnsURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")

        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: launcherURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: icnsURL.path))

        let plistData = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        XCTAssertEqual(plist?["CFBundleDisplayName"] as? String, "Test & Claude <1>")
    }

    // MARK: - 3. ProcessTracker Parsing & Filtering

    func testProcessTrackerFiltersHelperSubprocesses() throws {
        let paths = try makeTempPaths()
        defer { cleanupTempPaths(paths) }

        let claudeWork = AppInstance(
            id: UUID(),
            name: "Claude Work",
            sourceAppPath: "/Applications/Claude.app",
            sourceAppName: "Claude",
            sourceBundleID: "com.anthropic.claudefordesktop",
            engine: .electron,
            badgeText: "W",
            badgeColor: .blue
        )
        let nativeApp = AppInstance(
            id: UUID(),
            name: "Native App",
            sourceAppPath: "/Applications/ChatGPT.app",
            sourceAppName: "ChatGPT",
            sourceBundleID: "com.openai.codex",
            engine: .nativeMacOS,
            badgeText: "N",
            badgeColor: .green
        )

        let workDataDir = claudeWork.userDataDirectoryURL(paths: paths).path
        let psOutput = """
          101     1 /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=\(workDataDir)
          102   101 /Applications/Claude.app/Contents/Frameworks/Claude Helper (GPU).app/Contents/MacOS/Claude Helper (GPU) --type=gpu-process --user-data-dir=\(workDataDir)
          103   101 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer) --type=renderer --user-data-dir=\(workDataDir)
          205     1 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT
          309     1 /usr/bin/something --unrelated
        """

        let entries = ProcessTracker.parsePSOutput(psOutput)
        XCTAssertEqual(entries.count, 5)

        let running = ProcessTracker.findRunningPIDs(
            for: [claudeWork, nativeApp],
            entries: entries,
            trackedNativePIDs: [nativeApp.id: 205],
            paths: paths
        )

        XCTAssertEqual(running[claudeWork.id], 101)
        XCTAssertEqual(running[nativeApp.id], 205)
    }

    // MARK: - 4. IconBadgeRenderer ICNS Container Format

    func testWriteICNSGeneratesValidAppleIconContainer() throws {
        let paths = try makeTempPaths()
        defer { cleanupTempPaths(paths) }

        let icnsURL = paths.appSupportDirectory.appendingPathComponent("TestIcon.icns")
        try IconBadgeRenderer.writeICNS(to: icnsURL) { size in
            try IconBadgeRenderer.renderMultiAIManagerIcon(pixelSize: size)
        }

        let data = try Data(contentsOf: icnsURL)
        XCTAssertGreaterThan(data.count, 1024)

        let magic = String(data: data.subdata(in: 0..<4), encoding: .ascii)
        XCTAssertEqual(magic, "icns")

        let declaredLength = data.subdata(in: 4..<8).withUnsafeBytes {
            UInt32(bigEndian: $0.load(as: UInt32.self))
        }
        XCTAssertEqual(Int(declaredLength), data.count)

        var offset = 8
        var chunkTypes: [String] = []
        while offset + 8 <= data.count {
            let chunkType = String(data: data.subdata(in: offset..<(offset + 4)), encoding: .ascii) ?? ""
            let chunkLen = data.subdata(in: (offset + 4)..<(offset + 8)).withUnsafeBytes {
                Int(UInt32(bigEndian: $0.load(as: UInt32.self)))
            }
            XCTAssertGreaterThan(chunkLen, 8)
            XCTAssertLessThanOrEqual(offset + chunkLen, data.count)
            // Verify PNG signature inside ic07..ic10 chunks
            let pngSig = [UInt8](data.subdata(in: (offset + 8)..<(offset + 16)))
            XCTAssertEqual(pngSig, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            chunkTypes.append(chunkType)
            offset += chunkLen
        }

        XCTAssertEqual(offset, data.count)
        XCTAssertEqual(chunkTypes, ["ic07", "ic08", "ic09", "ic10"])
    }

    // MARK: - 5. WindowTiler Frame Geometry

    func testWindowTilerComputeFrames() {
        let visibleFrame = CGRect(x: 0, y: 80, width: 1920, height: 975)
        let primaryHeight: CGFloat = 1080
        // Top margin = 1080 - (80 + 975) = 25

        let sideFrames = WindowTiler.computeFrames(
            count: 2,
            in: visibleFrame,
            primaryScreenHeight: primaryHeight,
            layout: .sideBySide,
            gap: 6
        )
        XCTAssertEqual(sideFrames.count, 2)
        XCTAssertEqual(sideFrames[0].origin.x, 0)
        XCTAssertEqual(sideFrames[0].origin.y, 25)
        XCTAssertEqual(sideFrames[0].height, 975)
        XCTAssertEqual(sideFrames[1].maxX, 1920)
        XCTAssertFalse(sideFrames[0].intersects(sideFrames[1]))

        let stackedFrames = WindowTiler.computeFrames(
            count: 2,
            in: visibleFrame,
            primaryScreenHeight: primaryHeight,
            layout: .stacked,
            gap: 6
        )
        XCTAssertEqual(stackedFrames.count, 2)
        XCTAssertEqual(stackedFrames[0].minY, 25)
        XCTAssertEqual(stackedFrames[1].maxY, 1000)
        XCTAssertFalse(stackedFrames[0].intersects(stackedFrames[1]))

        let gridFrames = WindowTiler.computeFrames(
            count: 3,
            in: visibleFrame,
            primaryScreenHeight: primaryHeight,
            layout: .grid,
            gap: 6
        )
        XCTAssertEqual(gridFrames.count, 3)
        // Row 0 has 2 cells, Row 1 has 1 full-width cell
        XCTAssertFalse(gridFrames[0].intersects(gridFrames[1]))
        XCTAssertFalse(gridFrames[0].intersects(gridFrames[2]))
        XCTAssertFalse(gridFrames[1].intersects(gridFrames[2]))
        XCTAssertEqual(gridFrames[2].width, 1920)
    }

    // MARK: - 6. Real Installed App Detection (if present on this Mac)

    func testAppDiscoveryInspectInstalledApps() {
        let fm = FileManager.default

        if fm.fileExists(atPath: "/Applications/Claude.app") {
            let claude = AppDiscoveryService.inspectApp(at: "/Applications/Claude.app")
            XCTAssertNotNil(claude)
            XCTAssertEqual(claude?.detectedEngine, .electron)
            XCTAssertEqual(claude?.isPriorityAIApp, true)
        }

        if fm.fileExists(atPath: "/Applications/Antigravity.app") {
            let antigravity = AppDiscoveryService.inspectApp(at: "/Applications/Antigravity.app")
            XCTAssertNotNil(antigravity)
            let expectedEngine: IsolationEngine = fm.fileExists(atPath: "/Applications/Antigravity.app/Contents/Resources/app/product.json")
                ? .vscodeIDE
                : .electron
            XCTAssertEqual(antigravity?.detectedEngine, expectedEngine)
            XCTAssertEqual(antigravity?.recommendsIsolatedHome, true)
            XCTAssertEqual(antigravity?.usesKeychainIsolationCaveat, true)
            XCTAssertEqual(antigravity?.isPriorityAIApp, true)
        }

        if fm.fileExists(atPath: "/Applications/ChatGPT.app") {
            let chatgpt = AppDiscoveryService.inspectApp(at: "/Applications/ChatGPT.app")
            XCTAssertNotNil(chatgpt)
            XCTAssertEqual(chatgpt?.detectedEngine, .nativeMacOS)
            XCTAssertEqual(chatgpt?.usesKeychainIsolationCaveat, true)
        }

        if fm.fileExists(atPath: "/Applications/Google Chrome.app") {
            let chrome = AppDiscoveryService.inspectApp(at: "/Applications/Google Chrome.app")
            XCTAssertNotNil(chrome)
            XCTAssertEqual(chrome?.detectedEngine, .chromiumBrowserApp)
        }
    }

    // MARK: - 7. Isolated HOME Symlinks & Safe Profile Deletion

    func testIsolatedHomeSymlinksAndSafeDeletion() throws {
        let paths = try makeTempPaths()
        defer { cleanupTempPaths(paths) }

        let fm = FileManager.default
        let mockRealHome = paths.appSupportDirectory.deletingLastPathComponent()
            .appendingPathComponent("MockRealHome", isDirectory: true)
        let desktopDir = mockRealHome.appendingPathComponent("Desktop", isDirectory: true)
        let geminiDir = mockRealHome.appendingPathComponent(".gemini", isDirectory: true)
        let libraryDir = mockRealHome.appendingPathComponent("Library", isDirectory: true)
        let ghConfigDir = mockRealHome.appendingPathComponent(".config/gh", isDirectory: true)
        let claudeDir = mockRealHome.appendingPathComponent(".claude", isDirectory: true)
        let awsDir = mockRealHome.appendingPathComponent(".aws", isDirectory: true)
        try fm.createDirectory(at: desktopDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: geminiDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: ghConfigDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: awsDir, withIntermediateDirectories: true)

        let keepFile = desktopDir.appendingPathComponent("keep.txt")
        let gitconfigFile = mockRealHome.appendingPathComponent(".gitconfig")
        let secretGeminiFile = geminiDir.appendingPathComponent("secret.txt")
        let prefsFile = libraryDir.appendingPathComponent("prefs.plist")
        let ghHostsFile = ghConfigDir.appendingPathComponent("hosts.yml")
        let claudeSettingsFile = claudeDir.appendingPathComponent("settings.json")
        let claudeJsonFile = mockRealHome.appendingPathComponent(".claude.json")
        let awsConfigFile = awsDir.appendingPathComponent("config")
        let realZshenvFile = mockRealHome.appendingPathComponent(".zshenv")

        try "keep".write(to: keepFile, atomically: true, encoding: .utf8)
        try "[user]\n\tname = Test\n".write(to: gitconfigFile, atomically: true, encoding: .utf8)
        try "secret".write(to: secretGeminiFile, atomically: true, encoding: .utf8)
        try "plist".write(to: prefsFile, atomically: true, encoding: .utf8)
        try "github.com:\n  user: Test\n".write(to: ghHostsFile, atomically: true, encoding: .utf8)
        try "{\"ok\":true}".write(to: claudeSettingsFile, atomically: true, encoding: .utf8)
        try "{\"userID\":\"123\"}".write(to: claudeJsonFile, atomically: true, encoding: .utf8)
        try "[default]\nregion = us-east-1\n".write(to: awsConfigFile, atomically: true, encoding: .utf8)
        try "# real zshenv\n".write(to: realZshenvFile, atomically: true, encoding: .utf8)

        let instance = AppInstance(
            name: "Antigravity Isolated",
            sourceAppPath: "/Applications/Antigravity.app",
            sourceAppName: "Antigravity",
            sourceBundleID: "com.google.antigravity",
            engine: .electron,
            badgeText: "2",
            badgeColor: .purple,
            isolateHomeDirectory: true
        )

        // Simulate upgrading an older profile with stale shadowed dirs/files and an old .zshenv symlink
        let profileDir = instance.profileDirectoryURL(paths: paths)
        let isolatedHome = instance.homeDirectoryURL(paths: paths)
        let staleClaudeDir = isolatedHome.appendingPathComponent(".claude", isDirectory: true)
        let staleClaudeJson = isolatedHome.appendingPathComponent(".claude.json", isDirectory: false)
        let oldZshenvLink = isolatedHome.appendingPathComponent(".zshenv", isDirectory: false)
        try fm.createDirectory(at: staleClaudeDir, withIntermediateDirectories: true)
        try "stale-note".write(to: staleClaudeDir.appendingPathComponent("empty-note.txt"), atomically: true, encoding: .utf8)
        try "{\"stale\":true}".write(to: staleClaudeJson, atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: oldZshenvLink, withDestinationURL: realZshenvFile)

        try AppBundleGenerator.ensureProfileDirectories(for: instance, paths: paths, realHomeURL: mockRealHome)

        let linkedDesktop = isolatedHome.appendingPathComponent("Desktop")
        let linkedGitconfig = isolatedHome.appendingPathComponent(".gitconfig")
        let linkedConfig = isolatedHome.appendingPathComponent(".config")
        let linkedClaude = isolatedHome.appendingPathComponent(".claude")
        let linkedClaudeJson = isolatedHome.appendingPathComponent(".claude.json")
        let linkedAws = isolatedHome.appendingPathComponent(".aws")
        let isolatedGemini = isolatedHome.appendingPathComponent(".gemini")
        let isolatedLibrary = isolatedHome.appendingPathComponent("Library")
        let isolatedZshenv = isolatedHome.appendingPathComponent(".zshenv")

        XCTAssertEqual(try? linkedDesktop.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        XCTAssertEqual(try? linkedGitconfig.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        XCTAssertEqual(try? linkedConfig.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        XCTAssertEqual(try? linkedClaude.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        XCTAssertEqual(try? linkedClaudeJson.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        XCTAssertEqual(try? linkedAws.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        XCTAssertFalse(fm.fileExists(atPath: isolatedGemini.path))
        XCTAssertFalse(fm.fileExists(atPath: isolatedLibrary.path))

        // .zshenv inside isolatedHome must be a regular shim file and real ~/.zshenv must remain untouched
        XCTAssertEqual(try? isolatedZshenv.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, false)
        let shimContents = try String(contentsOf: isolatedZshenv, encoding: .utf8)
        XCTAssertTrue(shimContents.contains("MULTIAI_REAL_HOME"))
        XCTAssertTrue(shimContents.contains("ANTIGRAVITY_RESOLVING_ENVIRONMENT"))
        XCTAssertEqual(try String(contentsOf: realZshenvFile, encoding: .utf8), "# real zshenv\n")

        // Stale shadowed entries must be preserved in shadowed-home-backup
        let backupDir = profileDir.appendingPathComponent("shadowed-home-backup", isDirectory: true)
        XCTAssertTrue(fm.fileExists(atPath: backupDir.appendingPathComponent(".claude/empty-note.txt").path))
        XCTAssertTrue(fm.fileExists(atPath: backupDir.appendingPathComponent(".claude.json").path))

        let spec = AppBundleGenerator.buildLaunchSpec(for: instance, paths: paths, realHomeURL: mockRealHome)
        XCTAssertEqual(spec.environment["HOME"], isolatedHome.path)
        XCTAssertEqual(spec.environment["MULTIAI_REAL_HOME"], mockRealHome.standardizedFileURL.path)
        XCTAssertEqual(spec.environment["MULTIAI_ISOLATED_HOME"], isolatedHome.path)
        XCTAssertNil(spec.environment["XDG_CONFIG_HOME"])
        XCTAssertNil(spec.environment["XDG_DATA_HOME"])
        XCTAssertNil(spec.environment["XDG_CACHE_HOME"])

        let script = AppBundleGenerator.generateLauncherScript(for: instance, paths: paths, realHomeURL: mockRealHome)
        XCTAssertTrue(script.contains("MULTIAI_REAL_HOME="))
        XCTAssertFalse(script.contains("XDG_CONFIG_HOME="))

        try AppBundleGenerator.removeProfileDirectorySafely(at: profileDir)
        XCTAssertFalse(fm.fileExists(atPath: profileDir.path))
        XCTAssertTrue(fm.fileExists(atPath: keepFile.path))
        XCTAssertTrue(fm.fileExists(atPath: secretGeminiFile.path))
        XCTAssertTrue(fm.fileExists(atPath: ghHostsFile.path))
        XCTAssertTrue(fm.fileExists(atPath: claudeJsonFile.path))
        XCTAssertTrue(fm.fileExists(atPath: realZshenvFile.path))
    }

    func testIsolatedHomeZshShimRestoresHomeExceptDuringEnvProbe() throws {
        let paths = try makeTempPaths()
        defer { cleanupTempPaths(paths) }

        let fm = FileManager.default
        let mockRealHome = paths.appSupportDirectory.deletingLastPathComponent()
            .appendingPathComponent("MockRealHomeShim", isDirectory: true)
        try fm.createDirectory(at: mockRealHome, withIntermediateDirectories: true)

        let instance = AppInstance(
            name: "Antigravity Shim Test",
            sourceAppPath: "/Applications/Antigravity.app",
            sourceAppName: "Antigravity",
            sourceBundleID: "com.google.antigravity",
            engine: .electron,
            badgeText: "S",
            badgeColor: .blue,
            isolateHomeDirectory: true
        )

        try AppBundleGenerator.ensureProfileDirectories(for: instance, paths: paths, realHomeURL: mockRealHome)
        let isolatedHome = instance.homeDirectoryURL(paths: paths)
        let expectedRealHome = mockRealHome.standardizedFileURL.path
        let expectedIsolatedHome = isolatedHome.standardizedFileURL.path

        func runZshPrintHome(extraEnv: [String: String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", "printf '%s' \"$HOME\""]
            var env = [
                "PATH": "/usr/bin:/bin",
                "HOME": expectedIsolatedHome,
                "MULTIAI_REAL_HOME": expectedRealHome
            ]
            for (k, v) in extraEnv {
                env[k] = v
            }
            process.environment = env
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        }

        XCTAssertEqual(try runZshPrintHome(extraEnv: [:]), expectedRealHome)
        XCTAssertEqual(try runZshPrintHome(extraEnv: ["ANTIGRAVITY_RESOLVING_ENVIRONMENT": "1"]), expectedIsolatedHome)
        XCTAssertEqual(try runZshPrintHome(extraEnv: ["VSCODE_RESOLVING_ENVIRONMENT": "1"]), expectedIsolatedHome)
    }

    // MARK: - 8. Shared Antigravity Projects & Backwards-Compatible Decoding

    func testShareAntigravityProjectsSymlinksAndSafeDeletion() throws {
        let paths = try makeTempPaths()
        defer { cleanupTempPaths(paths) }

        let fm = FileManager.default
        let mockRealHome = paths.appSupportDirectory.deletingLastPathComponent()
            .appendingPathComponent("MockRealHomeShare", isDirectory: true)
        let realGemini = mockRealHome.appendingPathComponent(".gemini", isDirectory: true)
        let realConfig = realGemini.appendingPathComponent("config", isDirectory: true)
        let realProjects = realConfig.appendingPathComponent("projects", isDirectory: true)
        let realAntigravity = realGemini.appendingPathComponent("antigravity", isDirectory: true)

        try fm.createDirectory(at: realProjects, withIntermediateDirectories: true)
        try fm.createDirectory(at: realAntigravity, withIntermediateDirectories: true)

        let projFile = realProjects.appendingPathComponent("proj1.json")
        let mcpConfigFile = realConfig.appendingPathComponent("mcp_config.json")
        let geminiMdFile = realGemini.appendingPathComponent("GEMINI.md")
        let oauthTokenFile = realGemini.appendingPathComponent("jetski-standalone-oauth-token")
        let statePbtxtFile = realAntigravity.appendingPathComponent("antigravity_state.pbtxt")

        try "{\"id\":\"proj1\"}".write(to: projFile, atomically: true, encoding: .utf8)
        try "{\"mcpServers\":{}}".write(to: mcpConfigFile, atomically: true, encoding: .utf8)
        try "# Rules".write(to: geminiMdFile, atomically: true, encoding: .utf8)
        try "secret-token".write(to: oauthTokenFile, atomically: true, encoding: .utf8)
        try "state".write(to: statePbtxtFile, atomically: true, encoding: .utf8)

        var instance = AppInstance(
            name: "Antigravity Shared Projects",
            sourceAppPath: "/Applications/Antigravity.app",
            sourceAppName: "Antigravity",
            sourceBundleID: "com.google.antigravity",
            engine: .electron,
            badgeText: "2",
            badgeColor: .purple,
            isolateHomeDirectory: true,
            shareAntigravityProjects: true
        )

        // Pre-create an empty projects dir inside isolated profile to simulate upgrading an already-launched profile
        let isoGemini = instance.homeDirectoryURL(paths: paths).appendingPathComponent(".gemini", isDirectory: true)
        let isoConfig = isoGemini.appendingPathComponent("config", isDirectory: true)
        let isoProjects = isoConfig.appendingPathComponent("projects", isDirectory: true)
        try fm.createDirectory(at: isoProjects, withIntermediateDirectories: true)

        try AppBundleGenerator.ensureProfileDirectories(for: instance, paths: paths, realHomeURL: mockRealHome)

        let isoMcp = isoConfig.appendingPathComponent("mcp_config.json")
        let isoGeminiMd = isoGemini.appendingPathComponent("GEMINI.md")
        let isoOauth = isoGemini.appendingPathComponent("jetski-standalone-oauth-token")
        let isoAntigravity = isoGemini.appendingPathComponent("antigravity")

        XCTAssertEqual(try? isoProjects.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        XCTAssertEqual(try? isoMcp.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        XCTAssertEqual(try? isoGeminiMd.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)
        XCTAssertEqual(
            URL(fileURLWithPath: try fm.destinationOfSymbolicLink(atPath: isoProjects.path)).standardizedFileURL,
            realProjects.standardizedFileURL
        )
        XCTAssertFalse(fm.fileExists(atPath: isoOauth.path))
        XCTAssertFalse(fm.fileExists(atPath: isoAntigravity.path))

        // Disabling sharing unlinks symlinks without harming source project files
        instance.shareAntigravityProjects = false
        try AppBundleGenerator.ensureProfileDirectories(for: instance, paths: paths, realHomeURL: mockRealHome)
        XCTAssertFalse(fm.fileExists(atPath: isoProjects.path))
        XCTAssertFalse(fm.fileExists(atPath: isoMcp.path))
        XCTAssertTrue(fm.fileExists(atPath: projFile.path))

        // Re-enable and verify recursive symlink cleanup inside profile deletion
        instance.shareAntigravityProjects = true
        try AppBundleGenerator.ensureProfileDirectories(for: instance, paths: paths, realHomeURL: mockRealHome)
        XCTAssertEqual(try? isoProjects.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink, true)

        let profileDir = instance.profileDirectoryURL(paths: paths)
        try AppBundleGenerator.removeProfileDirectorySafely(at: profileDir)
        XCTAssertFalse(fm.fileExists(atPath: profileDir.path))
        XCTAssertTrue(fm.fileExists(atPath: projFile.path))
        XCTAssertTrue(fm.fileExists(atPath: oauthTokenFile.path))
        XCTAssertTrue(fm.fileExists(atPath: statePbtxtFile.path))
    }

    func testAppInstanceDecodesLegacyJSONWithoutShareAntigravityProjects() throws {
        let legacyJSON = """
        {
          "badgeColor" : "blue",
          "badgeText" : "1",
          "createStandaloneApp" : true,
          "createdAt" : "2026-11-22T14:46:16Z",
          "engine" : "electron",
          "envVars" : [],
          "extraArgs" : "",
          "id" : "67C37489-6394-472C-96E4-B312A4A6318F",
          "isolateExtensions" : false,
          "isolateHomeDirectory" : false,
          "name" : "Antigravity - Account 1",
          "sourceAppName" : "Antigravity",
          "sourceAppPath" : "/Applications/Antigravity.app",
          "sourceBundleID" : "com.google.antigravity"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppInstance.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.name, "Antigravity - Account 1")
        XCTAssertEqual(decoded.shareAntigravityProjects, false)
    }
}
