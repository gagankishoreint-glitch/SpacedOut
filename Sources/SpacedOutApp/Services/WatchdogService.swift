import Darwin
import Foundation
import SpacedOutCore

@MainActor
final class WatchdogService {
    nonisolated static let agentLabel = "com.spacedout.app.watchdog"

    private enum AppliedMode: Equatable {
        case disarmed
        case armed(String)
    }

    private var lastAppliedMode: AppliedMode?

    var isSupportedInCurrentBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.executablePath != nil
    }

    private nonisolated static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SpacedOut", isDirectory: true)
    }

    private nonisolated static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(agentLabel).plist", isDirectory: false)
    }

    private nonisolated static var pidFileURL: URL { supportDir.appendingPathComponent(".running.pid") }
    private nonisolated static var quitBootMarkerURL: URL { supportDir.appendingPathComponent(".quit-boottime") }
    private nonisolated static var relaunchFlagURL: URL { supportDir.appendingPathComponent(".watchdog-relaunched") }

    func syncState(armed: Bool) {
        guard isSupportedInCurrentBundle, let execPath = Bundle.main.executablePath else { return }
        let desired: AppliedMode = armed ? .armed(execPath) : .disarmed
        guard lastAppliedMode != desired else { return }
        lastAppliedMode = desired

        let plistURL = Self.plistURL
        Task.detached(priority: .utility) {
            if armed {
                Self.installOrUpdateAgent(plistURL: plistURL, executablePath: execPath)
            } else {
                Self.uninstallAgent(plistURL: plistURL)
            }
        }
    }

    func markRunningInstance() {
        guard isSupportedInCurrentBundle else { return }
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        try? "\(getpid())".write(to: Self.pidFileURL, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: Self.quitBootMarkerURL)
    }

    func consumeWatchdogRelaunchFlag() -> Bool {
        guard FileManager.default.fileExists(atPath: Self.relaunchFlagURL.path) else { return false }
        try? FileManager.default.removeItem(at: Self.relaunchFlagURL)
        return true
    }

    func recordIntentionalQuitForCurrentBoot() {
        guard isSupportedInCurrentBundle else { return }
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        if let bootSec = Self.currentBootTimeSeconds() {
            try? "\(bootSec)".write(to: Self.quitBootMarkerURL, atomically: true, encoding: .utf8)
        }
    }

    func clearRunningInstanceIfOwned() {
        guard let raw = try? String(contentsOf: Self.pidFileURL, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid == getpid() else {
            return
        }
        try? FileManager.default.removeItem(at: Self.pidFileURL)
    }

    // Runs headless from main.swift when invoked by launchd while armed.
    nonisolated static func runHeadlessEnsureCheck() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }

        if isAnotherSpacedOutAlive() {
            return
        }

        if let bootSec = currentBootTimeSeconds(),
           let markerRaw = try? String(contentsOf: quitBootMarkerURL, encoding: .utf8),
           let markerSec = Int64(markerRaw.trimmingCharacters(in: .whitespacesAndNewlines)),
           markerSec == bootSec {
            return
        }

        guard let state = try? AtomicJSONStore().load() else { return }
        let hasPending = state.reminders.contains {
            $0.status == .active || $0.status == .paused || $0.status == .triggered
        }
        guard state.settings.accountabilityWatchdogEnabled && hasPending else {
            uninstallAgent(plistURL: plistURL)
            return
        }

        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? "1".write(to: relaunchFlagURL, atomically: true, encoding: .utf8)

        let openProc = Process()
        openProc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProc.arguments = ["-g", Bundle.main.bundleURL.path]
        openProc.standardOutput = FileHandle.nullDevice
        openProc.standardError = FileHandle.nullDevice
        try? openProc.run()
        openProc.waitUntilExit()
    }

    private nonisolated static func isAnotherSpacedOutAlive() -> Bool {
        guard let raw = try? String(contentsOf: pidFileURL, encoding: .utf8),
              let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0, pid != getpid() else {
            return false
        }
        guard kill(pid, 0) == 0 else { return false }

        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return false }
        let path = String(cString: buffer)
        return path.hasSuffix("/MacOS/SpacedOut")
    }

    private nonisolated static func currentBootTimeSeconds() -> Int64? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else {
            return nil
        }
        return Int64(tv.tv_sec)
    }

    private nonisolated static func installOrUpdateAgent(plistURL: URL, executablePath: String) {
        let dir = plistURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let desiredArgs = [executablePath, "--watchdog-ensure"]
        let domain = "gui/\(getuid())"

        if let existingData = try? Data(contentsOf: plistURL),
           let existingPlist = try? PropertyListSerialization.propertyList(from: existingData, format: nil) as? [String: Any],
           let existingArgs = existingPlist["ProgramArguments"] as? [String],
           existingArgs == desiredArgs,
           runLaunchctl(["print", "\(domain)/\(agentLabel)"]) == 0 {
            return
        }

        let payload: [String: Any] = [
            "Label": agentLabel,
            "ProgramArguments": desiredArgs,
            "RunAtLoad": true,
            "StartInterval": 10,
            "ProcessType": "Background"
        ]

        guard let data = try? PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0) else {
            return
        }
        try? data.write(to: plistURL, options: .atomic)

        runLaunchctl(["bootout", "\(domain)/\(agentLabel)"])
        runLaunchctl(["bootstrap", domain, plistURL.path])
    }

    private nonisolated static func uninstallAgent(plistURL: URL) {
        let domain = "gui/\(getuid())"
        if FileManager.default.fileExists(atPath: plistURL.path) {
            runLaunchctl(["bootout", "\(domain)/\(agentLabel)"])
            try? FileManager.default.removeItem(at: plistURL)
        }
    }

    @discardableResult
    private nonisolated static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
