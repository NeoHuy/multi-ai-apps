import AppKit
import Foundation

/// Parsed process row from `/bin/ps -axo pid=,ppid=,args=`.
public struct ProcessInfoEntry: Equatable, Hashable, Sendable {
    public let pid: pid_t
    public let ppid: pid_t
    public let commandLine: String

    public init(pid: pid_t, ppid: pid_t, commandLine: String) {
        self.pid = pid
        self.ppid = ppid
        self.commandLine = commandLine
    }
}

/// Detects running isolated instances via command-line `--user-data-dir` matching and tracked native PIDs.
public enum ProcessTracker {
    /// Captures current running processes on macOS via `/bin/ps`.
    public static func snapshotRunningProcesses() -> [ProcessInfoEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,args="]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }
            return parsePSOutput(output)
        } catch {
            return []
        }
    }

    /// Parses output from `ps -axo pid=,ppid=,args=` into structured entries.
    public static func parsePSOutput(_ output: String) -> [ProcessInfoEntry] {
        var entries: [ProcessInfoEntry] = []
        entries.reserveCapacity(128)

        output.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }

            let scanner = Scanner(string: trimmed)
            scanner.charactersToBeSkipped = .whitespaces
            guard let pidValue = scanner.scanInt32(),
                  let ppidValue = scanner.scanInt32() else {
                return
            }

            let remainderIndex = scanner.currentIndex
            let commandLine = String(trimmed[remainderIndex...]).trimmingCharacters(in: .whitespaces)
            guard !commandLine.isEmpty else { return }

            entries.append(ProcessInfoEntry(pid: pidValue, ppid: ppidValue, commandLine: commandLine))
        }

        return entries
    }

    /// Resolves currently running root PIDs for each `AppInstance`.
    public static func findRunningPIDs(
        for instances: [AppInstance],
        entries: [ProcessInfoEntry],
        trackedNativePIDs: [UUID: pid_t] = [:],
        paths: MultiAIPaths = .default
    ) -> [UUID: pid_t] {
        var result: [UUID: pid_t] = [:]
        let entryByPID = Dictionary(uniqueKeysWithValues: entries.map { ($0.pid, $0) })

        for instance in instances {
            switch instance.engine {
            case .vscodeIDE, .electron, .chromiumBrowserApp:
                let userDataPath = instance.userDataDirectoryURL(paths: paths).path
                let candidates = entries.filter { entry in
                    guard entry.commandLine.contains(userDataPath) else { return false }
                    if entry.commandLine.contains("--type=") { return false }
                    if entry.commandLine.contains(".app/Contents/Frameworks/") { return false }
                    return true
                }

                if !candidates.isEmpty {
                    let candidatePIDs = Set(candidates.map(\.pid))
                    let roots = candidates.filter { !candidatePIDs.contains($0.ppid) }
                    let chosen = (roots.isEmpty ? candidates : roots)
                        .min(by: { $0.pid < $1.pid })
                    if let pid = chosen?.pid {
                        result[instance.id] = pid
                        continue
                    }
                }

                if let trackedPID = trackedNativePIDs[instance.id],
                   entryByPID[trackedPID] != nil {
                    result[instance.id] = trackedPID
                }

            case .nativeMacOS:
                if let trackedPID = trackedNativePIDs[instance.id],
                   entryByPID[trackedPID] != nil {
                    result[instance.id] = trackedPID
                }
            }
        }

        return result
    }
}
