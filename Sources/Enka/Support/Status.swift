import Foundation

func printStatus() {
    let fm = FileManager.default
    let target = launchctlServiceTarget()
    let accessible = checkAccessibilityPermission()
    let appPath = installedAppPath()
    let appExecutablePath = installedAppExecutablePath()
    let outputLogPath = standardOutputLogPath()
    let errorLogPath = standardErrorLogPath()
    let stateDir = stateDirectoryPath()

    print("LaunchAgent:  \(launchAgentPlistPath()) (\(fm.fileExists(atPath: launchAgentPlistPath()) ? "exists" : "missing"))")
    print("App:          \(appPath) (\(fm.fileExists(atPath: appPath) ? "exists" : "missing"))")
    print("App binary:   \(appExecutablePath) (\(fm.fileExists(atPath: appExecutablePath) ? "exists" : "missing"))")
    print("Binary:       \(installedBinaryPath()) (\(fm.fileExists(atPath: installedBinaryPath()) ? "exists" : "missing"))")
    print("Logs:         stdout=\(outputLogPath) (\(fm.fileExists(atPath: outputLogPath) ? "exists" : "missing")), stderr=\(errorLogPath) (\(fm.fileExists(atPath: errorLogPath) ? "exists" : "missing"))")
    print("State dir:    \(stateDir) (\(fm.fileExists(atPath: stateDir) ? "exists" : "missing"))")
    print("Accessibility:\(accessible ? " granted" : " missing")")
    if !accessible {
        print("next action: open \(installedAppPath())")
    }
    print("Check commands:")
    print("  launchctl print \(target)")

    if !fm.fileExists(atPath: launchAgentPlistPath()) {
        print("LaunchAgent plist missing; run the installer again.")
        return
    }

    do {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", target]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let status = process.terminationStatus
        _ = stderr.fileHandleForReading.readDataToEndOfFile()

        if status == 0 {
            let rawOutput = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let output = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if !output.isEmpty {
                print("launchctl: \(output)")
            } else {
                print("launchctl: loaded")
            }
        } else {
            print("launchctl: not loaded or unavailable (status \(status))")
        }
    } catch {
        print("launchctl: not loaded or unavailable (status 1)")
    }
}
