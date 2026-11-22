import AppKit
import Foundation

/// Centralized directory paths used by MultiAI, injectable for isolated unit testing.
public struct MultiAIPaths: Sendable, Hashable {
    public let appSupportDirectory: URL
    public let standaloneAppsDirectory: URL

    public static let `default`: MultiAIPaths = {
        let fm = FileManager.default
        let appSupportBase = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        let appSupport = appSupportBase.appendingPathComponent("MultiAI", isDirectory: true)
        let standalone = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("MultiAI Apps", isDirectory: true)
        return MultiAIPaths(appSupportDirectory: appSupport, standaloneAppsDirectory: standalone)
    }()

    public init(appSupportDirectory: URL, standaloneAppsDirectory: URL) {
        self.appSupportDirectory = appSupportDirectory
        self.standaloneAppsDirectory = standaloneAppsDirectory
    }

    public var instancesFileURL: URL {
        appSupportDirectory.appendingPathComponent("instances.json", isDirectory: false)
    }

    public var profilesDirectoryURL: URL {
        appSupportDirectory.appendingPathComponent("Profiles", isDirectory: true)
    }
}

/// Strategy used to isolate profile data and run multiple instances concurrently.
public enum IsolationEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case vscodeIDE
    case electron
    case chromiumBrowserApp
    case nativeMacOS

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vscodeIDE:
            return "IDE Isolated"
        case .electron:
            return "Electron Isolated"
        case .chromiumBrowserApp:
            return "Browser App Mode"
        case .nativeMacOS:
            return "Native macOS"
        }
    }

    public var badgeShortLabel: String {
        switch self {
        case .vscodeIDE:
            return "IDE"
        case .electron:
            return "Electron"
        case .chromiumBrowserApp:
            return "Web App"
        case .nativeMacOS:
            return "Native"
        }
    }

    public var summaryDescription: String {
        switch self {
        case .vscodeIDE:
            return "Dùng --user-data-dir riêng (và tuỳ chọn --extensions-dir). Phù hợp cho Antigravity, Cursor, VS Code."
        case .electron:
            return "Dùng --user-data-dir riêng để tách toàn bộ phiên đăng nhập, cache và cookies. Phù hợp cho Claude Desktop."
        case .chromiumBrowserApp:
            return "Mở trang Web AI như một cửa sổ app độc lập với profile trình duyệt riêng biệt (--user-data-dir & --app)."
        case .nativeMacOS:
            return "Chạy instance riêng bằng open -n cùng biến môi trường XDG (có tuỳ chọn tách HOME). Một số app dùng macOS Keychain vẫn có thể dùng chung phiên đăng nhập."
        }
    }

    public var supportsTrueMultiAccount: Bool {
        self != .nativeMacOS
    }
}

/// Vibrant badge accent colors applied onto generated app icons and cards.
public enum BadgeColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue
    case purple
    case pink
    case red
    case orange
    case amber
    case green
    case teal

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.capitalized
    }

    public var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .blue:   return (0.04, 0.52, 1.00)
        case .purple: return (0.69, 0.32, 0.87)
        case .pink:   return (1.00, 0.22, 0.37)
        case .red:    return (1.00, 0.27, 0.23)
        case .orange: return (1.00, 0.58, 0.00)
        case .amber:  return (0.96, 0.72, 0.00)
        case .green:  return (0.19, 0.82, 0.35)
        case .teal:   return (0.19, 0.69, 0.78)
        }
    }

    public var nsColor: NSColor {
        let c = rgb
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1.0)
    }
}

/// Custom environment variable entry passed when launching an instance.
public struct EnvVarEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }
}

/// Arrangement layout for Accessibility-based window tiling.
public enum WindowTileLayout: String, CaseIterable, Identifiable, Sendable {
    case sideBySide
    case grid
    case stacked

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sideBySide: return "Side by Side"
        case .grid: return "Grid"
        case .stacked: return "Stacked"
        }
    }

    public var systemImage: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .grid: return "square.grid.2x2"
        case .stacked: return "rectangle.split.1x2"
        }
    }
}

/// Quick URL presets when configuring a Chromium Browser App instance.
public struct WebAppPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let url: String
    public let badgeHint: String
    public let suggestedColor: BadgeColor

    public static let defaults: [WebAppPreset] = [
        WebAppPreset(id: "gemini", title: "Gemini", url: "https://gemini.google.com", badgeHint: "G", suggestedColor: .blue),
        WebAppPreset(id: "chatgpt", title: "ChatGPT", url: "https://chatgpt.com", badgeHint: "GP", suggestedColor: .green),
        WebAppPreset(id: "claude", title: "Claude", url: "https://claude.ai", badgeHint: "CL", suggestedColor: .orange),
        WebAppPreset(id: "perplexity", title: "Perplexity", url: "https://www.perplexity.ai", badgeHint: "PX", suggestedColor: .teal),
        WebAppPreset(id: "grok", title: "Grok", url: "https://grok.com", badgeHint: "GK", suggestedColor: .purple)
    ]
}

/// Represents a configured isolated account instance for a macOS desktop app.
public struct AppInstance: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var sourceAppPath: String
    public var sourceAppName: String
    public var sourceBundleID: String
    public var engine: IsolationEngine
    public var badgeText: String
    public var badgeColor: BadgeColor
    public var targetURL: String?
    public var isolateExtensions: Bool
    public var isolateHomeDirectory: Bool
    public var shareAntigravityProjects: Bool
    public var extraArgs: String
    public var envVars: [EnvVarEntry]
    public var createStandaloneApp: Bool
    public var standaloneAppPath: String?
    public var createdAt: Date
    public var lastLaunchedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, sourceAppPath, sourceAppName, sourceBundleID, engine
        case badgeText, badgeColor, targetURL
        case isolateExtensions, isolateHomeDirectory, shareAntigravityProjects
        case extraArgs, envVars, createStandaloneApp, standaloneAppPath
        case createdAt, lastLaunchedAt
    }

    public init(
        id: UUID = UUID(),
        name: String,
        sourceAppPath: String,
        sourceAppName: String,
        sourceBundleID: String,
        engine: IsolationEngine,
        badgeText: String,
        badgeColor: BadgeColor = .blue,
        targetURL: String? = nil,
        isolateExtensions: Bool = false,
        isolateHomeDirectory: Bool = false,
        shareAntigravityProjects: Bool = false,
        extraArgs: String = "",
        envVars: [EnvVarEntry] = [],
        createStandaloneApp: Bool = true,
        standaloneAppPath: String? = nil,
        createdAt: Date = Date(),
        lastLaunchedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.sourceAppPath = sourceAppPath
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.engine = engine
        self.badgeText = badgeText
        self.badgeColor = badgeColor
        self.targetURL = targetURL
        self.isolateExtensions = isolateExtensions
        self.isolateHomeDirectory = isolateHomeDirectory
        self.shareAntigravityProjects = shareAntigravityProjects
        self.extraArgs = extraArgs
        self.envVars = envVars
        self.createStandaloneApp = createStandaloneApp
        self.standaloneAppPath = standaloneAppPath
        self.createdAt = createdAt
        self.lastLaunchedAt = lastLaunchedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        sourceAppPath = try c.decode(String.self, forKey: .sourceAppPath)
        sourceAppName = try c.decode(String.self, forKey: .sourceAppName)
        sourceBundleID = try c.decode(String.self, forKey: .sourceBundleID)
        engine = try c.decode(IsolationEngine.self, forKey: .engine)
        badgeText = try c.decode(String.self, forKey: .badgeText)
        badgeColor = try c.decode(BadgeColor.self, forKey: .badgeColor)
        targetURL = try c.decodeIfPresent(String.self, forKey: .targetURL)
        isolateExtensions = try c.decodeIfPresent(Bool.self, forKey: .isolateExtensions) ?? false
        isolateHomeDirectory = try c.decodeIfPresent(Bool.self, forKey: .isolateHomeDirectory) ?? false
        shareAntigravityProjects = try c.decodeIfPresent(Bool.self, forKey: .shareAntigravityProjects) ?? false
        extraArgs = try c.decodeIfPresent(String.self, forKey: .extraArgs) ?? ""
        envVars = try c.decodeIfPresent([EnvVarEntry].self, forKey: .envVars) ?? []
        createStandaloneApp = try c.decodeIfPresent(Bool.self, forKey: .createStandaloneApp) ?? true
        standaloneAppPath = try c.decodeIfPresent(String.self, forKey: .standaloneAppPath)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lastLaunchedAt = try c.decodeIfPresent(Date.self, forKey: .lastLaunchedAt)
    }

    public func profileDirectoryURL(paths: MultiAIPaths = .default) -> URL {
        paths.profilesDirectoryURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public func userDataDirectoryURL(paths: MultiAIPaths = .default) -> URL {
        profileDirectoryURL(paths: paths).appendingPathComponent("user-data", isDirectory: true)
    }

    public func extensionsDirectoryURL(paths: MultiAIPaths = .default) -> URL {
        profileDirectoryURL(paths: paths).appendingPathComponent("extensions", isDirectory: true)
    }

    public func homeDirectoryURL(paths: MultiAIPaths = .default) -> URL {
        profileDirectoryURL(paths: paths).appendingPathComponent("home", isDirectory: true)
    }

    public func xdgDirectoryURL(paths: MultiAIPaths = .default) -> URL {
        profileDirectoryURL(paths: paths).appendingPathComponent("xdg", isDirectory: true)
    }

    public var sanitizedAppFileName: String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = name.components(separatedBy: forbidden).filter { !$0.isEmpty }
        let joined = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? "MultiAI-\(id.uuidString.prefix(6))" : joined
    }

    public func expectedStandaloneAppURL(paths: MultiAIPaths = .default) -> URL {
        paths.standaloneAppsDirectory.appendingPathComponent("\(sanitizedAppFileName).app", isDirectory: true)
    }

    public var normalizedBadgeText: String {
        let trimmed = badgeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(2)).uppercased()
    }

    public var targetURLHost: String? {
        guard let raw = targetURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)?.host ?? raw
    }
}
