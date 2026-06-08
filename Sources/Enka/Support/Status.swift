import Foundation

func printStatus() {
    let fm = FileManager.default
    let plistPath = launchAgentPlistPath()
    let target = launchctlServiceTarget()
    let appPath = installedAppPath()
    let appExecutablePath = installedAppExecutablePath()
    let outputLogPath = standardOutputLogPath()
    let errorLogPath = standardErrorLogPath()
    let stateDir = stateDirectoryPath()

    print("LaunchAgent:  \(plistPath) (\(fm.fileExists(atPath: plistPath) ? "exists" : "missing"))")
    print("App:          \(appPath) (\(fm.fileExists(atPath: appPath) ? "exists" : "missing"))")
    print("App binary:   \(appExecutablePath) (\(fm.fileExists(atPath: appExecutablePath) ? "exists" : "missing"))")
    print("Binary:       \(installedBinaryPath()) (\(fm.fileExists(atPath: installedBinaryPath()) ? "exists" : "missing"))")
    print("Logs:         stdout=\(outputLogPath) (\(fm.fileExists(atPath: outputLogPath) ? "exists" : "missing")), stderr=\(errorLogPath) (\(fm.fileExists(atPath: errorLogPath) ? "exists" : "missing"))")
    print("State dir:    \(stateDir) (\(fm.fileExists(atPath: stateDir) ? "exists" : "missing"))")

    let accessibilityStatus = runAccessibilityStatusSubcommand(
        executablePath: appExecutablePath,
        appBundlePath: appPath,
        logToSetup: nil
    )

    switch accessibilityStatus {
    case .some(true):
        print("Accessibility: granted")
    case .some(false):
        print("Accessibility: missing")
        print("next action: open \(appPath)")
    case .none:
        if !fm.fileExists(atPath: appPath) {
            print("Accessibility: unavailable (app missing)")
            print("next action: run enka install")
        } else if !fm.fileExists(atPath: appExecutablePath) {
            print("Accessibility: unavailable (app executable missing)")
            print("next action: run enka install")
        } else {
            print("Accessibility: unavailable (could not verify)")
            print("next action: open \(appPath) and enable Accessibility")
        }
    }
    print("Check commands:")
    print("  launchctl print \(target)")

    if !fm.fileExists(atPath: plistPath) {
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
