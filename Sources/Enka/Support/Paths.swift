import Foundation
import Darwin

nonisolated(unsafe) private let setupDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

func envOverride(_ name: String) -> String? {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
        return nil
    }
    return value
}

func userHomeDirectory() -> String {
    FileManager.default.homeDirectoryForCurrentUser.path
}

func defaultInstallRoot() -> String {
    envOverride("ENKA_INSTALL_ROOT") ?? userHomeDirectory().appending("/Applications/enka")
}

func defaultLaunchAgentDirectory() -> String {
    envOverride("ENKA_LAUNCH_AGENT_DIR") ?? userHomeDirectory().appending("/Library/LaunchAgents")
}

func stateDirectoryPath() -> String {
    envOverride("ENKA_STATE_DIR") ?? userHomeDirectory().appending("/.local/state/enka")
}

func standardOutputLogPath() -> String {
    stateDirectoryPath().appending("/enka.log")
}

func standardErrorLogPath() -> String {
    stateDirectoryPath().appending("/enka.err.log")
}

func setupLogPath() -> String {
    stateDirectoryPath().appending("/setup.log")
}

func setupLogPrefix() -> String {
    setupDateFormatter.string(from: Date())
}

func writeSetupLog(_ path: String, _ message: String) {
    let data = (message + "\n").data(using: .utf8) ?? Data()
    do {
        if let handle = try? FileHandle(forUpdating: URL(fileURLWithPath: path)) {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            handle.closeFile()
            return
        }
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    } catch {
        // Best-effort setup logging.
    }
}

func installedAppPath() -> String {
    defaultInstallRoot().appending("/Enka.app")
}

func installedAppExecutablePath() -> String {
    installedAppPath().appending("/Contents/MacOS/Enka")
}

func installedAppInfoPlistPath() -> String {
    installedAppPath().appending("/Contents/Info.plist")
}

func installedBinaryPath() -> String {
    defaultInstallRoot().appending("/bin/enka")
}

func launchAgentPlistPath() -> String {
    defaultLaunchAgentDirectory().appending("/dev.ultrahope.enka.plist")
}

func launchctlLabel() -> String {
    "dev.ultrahope.enka"
}

func launchctlDomain() -> String {
    "gui/\(getuid())"
}

func launchctlServiceTarget() -> String {
    "\(launchctlDomain())/\(launchctlLabel())"
}

func launchAgentPlist() -> String {
    let programPath = installedAppExecutablePath()
    let logPath = standardOutputLogPath()
    let errPath = standardErrorLogPath()

    let plist: [String: Any] = [
        "Label": launchctlLabel(),
        "ProgramArguments": [programPath, "run"],
        "RunAtLoad": true,
        "KeepAlive": true,
        "StandardOutPath": logPath,
        "StandardErrorPath": errPath,
    ]

    do {
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        guard let content = String(data: data, encoding: .utf8) else {
            fatalError("failed to encode launch agent plist as UTF-8")
        }
        return content
    } catch {
        fatalError("failed to serialize launch agent plist: \(error.localizedDescription)")
    }
}

func ensureDirectory(atPath path: String) throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: path) {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
}
