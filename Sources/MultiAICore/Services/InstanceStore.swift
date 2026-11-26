import AppKit
import Foundation
import Observation

/// Central state store managing configured AI account instances, standalone `.app` bundles, and live process tracking.
@MainActor
@Observable
public final class InstanceStore {
    public private(set) var instances: [AppInstance] = []
    public private(set) var installedApps: [InstalledApp] = []
    public private(set) var runningPIDs: [UUID: pid_t] = [:]
    public var lastErrorMessage: String?
    public var statusBannerMessage: String?
    public var needsAccessibilityBanner: Bool = false

    public let paths: MultiAIPaths

    @ObservationIgnored private var trackedNativePIDs: [UUID: pid_t] = [:]
    @ObservationIgnored nonisolated(unsafe) private var monitorTask: Task<Void, Never>?

    public init(paths: MultiAIPaths = .default, startMonitoring: Bool = true) {
        self.paths = paths
        loadInstances()
        upgradeOutdatedIsolatedHomeInstances()
        rescanInstalledApps()
        if startMonitoring {
            beginMonitoring()
        }
    }

    deinit {
        monitorTask?.cancel()
    }

    // MARK: - Queries

    public func isRunning(_ instance: AppInstance) -> Bool {
        runningPIDs[instance.id] != nil
    }

    public func pid(for instance: AppInstance) -> pid_t? {
        runningPIDs[instance.id]
    }

    public var runningInstances: [AppInstance] {
        instances.filter { runningPIDs[$0.id] != nil }
    }

    public func suggestedNextName(for app: InstalledApp) -> String {
        let existingCount = instances.filter { $0.sourceAppPath == app.path }.count
        if existingCount == 0 {
            return "\(app.name) - Account 1"
        }
        return "\(app.name) - Account \(existingCount + 1)"
    }

    public func suggestedNextBadge(for app: InstalledApp) -> String {
        let existingCount = instances.filter { $0.sourceAppPath == app.path }.count
        return "\(existingCount + 1)"
    }

    public func suggestedNextColor(for app: InstalledApp) -> BadgeColor {
        let existingCount = instances.filter { $0.sourceAppPath == app.path }.count
        let palette = BadgeColor.allCases
        return palette[existingCount % palette.count]
    }

    // MARK: - Discovery & Persistence

    public func rescanInstalledApps() {
        installedApps = AppDiscoveryService.scanInstalledApps(paths: paths)
    }

    public func loadInstances() {
        let url = paths.instancesFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            instances = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            instances = try decoder.decode([AppInstance].self, from: data)
        } catch {
            lastErrorMessage = "Không thể đọc danh sách tài khoản: \(error.localizedDescription)"
            instances = []
        }
    }

    public func saveInstances() throws {
        try FileManager.default.createDirectory(at: paths.appSupportDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(instances)
        try data.write(to: paths.instancesFileURL, options: [.atomic])
    }

    // MARK: - CRUD

    public func addInstance(_ instance: AppInstance) throws {
        var mutable = instance
        try AppBundleGenerator.ensureProfileDirectories(for: mutable, paths: paths)

        if mutable.createStandaloneApp {
            let bundleURL = try AppBundleGenerator.createOrUpdateStandaloneApp(for: mutable, paths: paths)
            mutable.standaloneAppPath = bundleURL.path
        } else {
            mutable.standaloneAppPath = nil
        }

        instances.append(mutable)
        try saveInstances()
        statusBannerMessage = "Đã tạo tài khoản \"\(mutable.name)\"."
    }

    public func updateInstance(_ instance: AppInstance) throws {
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else {
            return
        }

        let previous = instances[index]
        var updated = instance
        updated.standaloneAppPath = previous.standaloneAppPath

        try AppBundleGenerator.ensureProfileDirectories(for: updated, paths: paths)

        if updated.createStandaloneApp {
            let bundleURL = try AppBundleGenerator.createOrUpdateStandaloneApp(for: updated, paths: paths)
            updated.standaloneAppPath = bundleURL.path
        } else {
            if let oldPath = previous.standaloneAppPath {
                try? AppBundleGenerator.removeStandaloneApp(at: oldPath, paths: paths)
            }
            updated.standaloneAppPath = nil
        }

        instances[index] = updated
        try saveInstances()
        statusBannerMessage = "Đã cập nhật \"\(updated.name)\"."
    }

    public func rebuildStandaloneApp(for instance: AppInstance) {
        do {
            var updated = instance
            updated.createStandaloneApp = true
            let url = try AppBundleGenerator.createOrUpdateStandaloneApp(for: updated, paths: paths)
            updated.standaloneAppPath = url.path
            if let idx = instances.firstIndex(where: { $0.id == instance.id }) {
                instances[idx] = updated
                try saveInstances()
            }
            statusBannerMessage = "Đã tạo lại app độc lập cho \"\(updated.name)\"."
        } catch {
            lastErrorMessage = "Không thể tạo lại .app: \(error.localizedDescription)"
        }
    }

    public func duplicateInstance(_ instance: AppInstance) throws {
        let baseName = instance.name
        var candidateName = "\(baseName) Copy"
        var counter = 2
        while instances.contains(where: { $0.name == candidateName }) {
            candidateName = "\(baseName) Copy \(counter)"
            counter += 1
        }

        let duplicated = AppInstance(
            id: UUID(),
            name: candidateName,
            sourceAppPath: instance.sourceAppPath,
            sourceAppName: instance.sourceAppName,
            sourceBundleID: instance.sourceBundleID,
            engine: instance.engine,
            badgeText: String(counter),
            badgeColor: BadgeColor.allCases[(instances.count + 1) % BadgeColor.allCases.count],
            targetURL: instance.targetURL,
            isolateExtensions: instance.isolateExtensions,
            isolateHomeDirectory: instance.isolateHomeDirectory,
            shareAntigravityProjects: instance.shareAntigravityProjects,
            extraArgs: instance.extraArgs,
            envVars: instance.envVars,
            createStandaloneApp: instance.createStandaloneApp,
            standaloneAppPath: nil,
            createdAt: Date(),
            lastLaunchedAt: nil
        )

        try addInstance(duplicated)
    }

    public func deleteInstance(_ instance: AppInstance, deleteProfileData: Bool) throws {
        if isRunning(instance) {
            stop(instance, force: false)
        }

        if let standalonePath = instance.standaloneAppPath {
            try? AppBundleGenerator.removeStandaloneApp(at: standalonePath, paths: paths)
        } else {
            try? AppBundleGenerator.removeStandaloneApp(
                at: instance.expectedStandaloneAppURL(paths: paths).path,
                paths: paths
            )
        }

        if deleteProfileData {
            let profileURL = instance.profileDirectoryURL(paths: paths)
            try AppBundleGenerator.removeProfileDirectorySafely(at: profileURL)
        }

        trackedNativePIDs.removeValue(forKey: instance.id)
        runningPIDs.removeValue(forKey: instance.id)
        instances.removeAll { $0.id == instance.id }
        try saveInstances()
        statusBannerMessage = "Đã xoá \"\(instance.name)\"."
    }

    // MARK: - Process Lifecycle

    public func launch(_ instance: AppInstance) {
        if isRunning(instance) {
            focus(instance)
            return
        }

        guard FileManager.default.fileExists(atPath: instance.sourceAppPath) else {
            lastErrorMessage = "Không tìm thấy ứng dụng gốc tại \(instance.sourceAppPath)."
            return
        }

        Task {
            do {
                try AppBundleGenerator.ensureProfileDirectories(for: instance, paths: paths)
                if AppBundleGenerator.needsLauncherUpgrade(for: instance, paths: paths) {
                    _ = try? AppBundleGenerator.createOrUpdateStandaloneApp(for: instance, paths: paths)
                }
                let spec = AppBundleGenerator.buildLaunchSpec(for: instance, paths: paths)

                let config = NSWorkspace.OpenConfiguration()
                config.createsNewApplicationInstance = true
                config.activates = true
                config.arguments = spec.arguments
                config.environment = spec.environment

                let appURL = URL(fileURLWithPath: spec.sourceAppPath, isDirectory: true)
                let runningApp = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)

                trackedNativePIDs[instance.id] = runningApp.processIdentifier
                runningPIDs[instance.id] = runningApp.processIdentifier

                if let idx = instances.firstIndex(where: { $0.id == instance.id }) {
                    instances[idx].lastLaunchedAt = Date()
                    try? saveInstances()
                }

                try? await Task.sleep(for: .milliseconds(700))
                await refreshRunningStates()
            } catch {
                lastErrorMessage = "Không thể mở \"\(instance.name)\": \(error.localizedDescription)"
            }
        }
    }

    public func focus(_ instance: AppInstance) {
        guard let pid = runningPIDs[instance.id],
              let runningApp = NSRunningApplication(processIdentifier: pid) else {
            launch(instance)
            return
        }
        runningApp.activate(options: [.activateAllWindows])
    }

    public func stop(_ instance: AppInstance, force: Bool = false) {
        guard let pid = runningPIDs[instance.id],
              let runningApp = NSRunningApplication(processIdentifier: pid) else {
            trackedNativePIDs.removeValue(forKey: instance.id)
            runningPIDs.removeValue(forKey: instance.id)
            return
        }

        if force {
            runningApp.forceTerminate()
        } else {
            runningApp.terminate()
        }

        trackedNativePIDs.removeValue(forKey: instance.id)
        runningPIDs.removeValue(forKey: instance.id)

        Task {
            try? await Task.sleep(for: .milliseconds(800))
            await refreshRunningStates()
        }
    }

    public func launchAll(_ targets: [AppInstance]) {
        for target in targets where !isRunning(target) {
            launch(target)
        }
    }

    public func stopAll(_ targets: [AppInstance]) {
        for target in targets where isRunning(target) {
            stop(target, force: false)
        }
    }

    // MARK: - Window Tiling

    public func tileRunning(for targets: [AppInstance]? = nil, layout: WindowTileLayout) {
        let pool = targets ?? instances
        let pids = pool.compactMap { runningPIDs[$0.id] }
        guard !pids.isEmpty else {
            lastErrorMessage = "Chưa có tài khoản nào đang chạy để chia cửa sổ."
            return
        }

        let result = WindowTiler.tileWindows(pids: pids, layout: layout)
        switch result {
        case .success(let count):
            needsAccessibilityBanner = false
            statusBannerMessage = "Đã sắp xếp \(count) cửa sổ (\(layout.displayName))."
        case .needsAccessibilityPermission:
            needsAccessibilityBanner = true
            lastErrorMessage = "MultiAI cần quyền Accessibility để sắp xếp cửa sổ các app đang chạy."
        case .noWindowsFound:
            lastErrorMessage = "Không tìm thấy cửa sổ hiển thị nào để sắp xếp."
        }
    }

    public func launchAndTile(_ targets: [AppInstance], layout: WindowTileLayout) {
        guard !targets.isEmpty else { return }

        let stopped = targets.filter { !isRunning($0) }
        if stopped.isEmpty {
            tileRunning(for: targets, layout: layout)
            return
        }

        launchAll(stopped)
        statusBannerMessage = "Đang khởi chạy \(stopped.count) tài khoản để chia cửa sổ..."

        Task {
            try? await Task.sleep(for: .seconds(2.3))
            await refreshRunningStates()
            tileRunning(for: targets, layout: layout)
        }
    }

    // MARK: - Finder Integration

    public func revealStandaloneApp(_ instance: AppInstance) {
        let path = instance.standaloneAppPath ?? instance.expectedStandaloneAppURL(paths: paths).path
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            lastErrorMessage = "Chưa có file .app cho \"\(instance.name)\". Hãy bấm Tạo lại .app."
        }
    }

    public func revealProfileFolder(_ instance: AppInstance) {
        let url = instance.profileDirectoryURL(paths: paths)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func openStandaloneAppsFolder() {
        let dir = paths.standaloneAppsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Process Monitoring

    public func refreshRunningStates() async {
        let currentInstances = instances
        let nativePIDs = trackedNativePIDs
        let pathsCopy = paths

        let updatedPIDs = await Task.detached(priority: .utility) {
            let entries = ProcessTracker.snapshotRunningProcesses()
            return ProcessTracker.findRunningPIDs(
                for: currentInstances,
                entries: entries,
                trackedNativePIDs: nativePIDs,
                paths: pathsCopy
            )
        }.value

        runningPIDs = updatedPIDs

        // Prune dead native tracked PIDs
        let aliveSet = Set(updatedPIDs.values)
        trackedNativePIDs = trackedNativePIDs.filter { aliveSet.contains($0.value) }
    }

    private func upgradeOutdatedIsolatedHomeInstances() {
        for instance in instances where instance.isolateHomeDirectory {
            guard AppBundleGenerator.needsLauncherUpgrade(for: instance, paths: paths) else {
                continue
            }
            _ = try? AppBundleGenerator.createOrUpdateStandaloneApp(for: instance, paths: paths)
        }
    }

    private func beginMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshRunningStates()
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
    }
}
