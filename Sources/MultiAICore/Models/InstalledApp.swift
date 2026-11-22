import Foundation

/// Metadata describing an installed macOS desktop app discovered in `/Applications` or `~/Applications`.
public struct InstalledApp: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let bundleIdentifier: String
    public let executableName: String
    public let detectedEngine: IsolationEngine
    public let usesKeychainIsolationCaveat: Bool
    public let recommendsIsolatedHome: Bool
    public let isPriorityAIApp: Bool

    public init(
        name: String,
        path: String,
        bundleIdentifier: String,
        executableName: String,
        detectedEngine: IsolationEngine,
        usesKeychainIsolationCaveat: Bool,
        recommendsIsolatedHome: Bool = false,
        isPriorityAIApp: Bool
    ) {
        self.id = path
        self.name = name
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.executableName = executableName
        self.detectedEngine = detectedEngine
        self.usesKeychainIsolationCaveat = usesKeychainIsolationCaveat
        self.recommendsIsolatedHome = recommendsIsolatedHome
        self.isPriorityAIApp = isPriorityAIApp
    }

    public var isBrowser: Bool {
        detectedEngine == .chromiumBrowserApp
    }
}
