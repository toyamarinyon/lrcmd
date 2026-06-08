@preconcurrency import ApplicationServices
import Foundation
import Darwin

func runAccessibilityStatusSubcommand(
    executablePath: String,
    appBundlePath: String,
    logToSetup: ((String) -> Void)? = nil
) -> Bool? {
    if FileManager.default.fileExists(atPath: appBundlePath) {
        let logPrefix = setupLogPrefix()
        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("enka_accessibility_status_\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-W", "-n", appBundlePath, "--args", "__accessibility-status", "--result-file", tempFile.path]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            logToSetup?("\(logPrefix) [setup] accessibility-status command start: /usr/bin/open -W -n \(appBundlePath) --args __accessibility-status --result-file \(tempFile.path)")
            try process.run()
            process.waitUntilExit()
            let stderrValue = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !stderrValue.isEmpty {
                logToSetup?("\(logPrefix) [setup] accessibility-status stderr: \(stderrValue)")
            }
            logToSetup?("\(logPrefix) [setup] accessibility-status command finished: exit=\(process.terminationStatus)")
            let rawValue = (try? String(contentsOf: tempFile))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            logToSetup?("\(logPrefix) [setup] accessibility-status result-file: \(tempFile.path), value=\(rawValue.isEmpty ? "(empty)" : rawValue)")
            switch rawValue {
            case "granted":
                logToSetup?("\(logPrefix) [setup] accessibility-status result: granted")
                return true
            case "not_granted":
                logToSetup?("\(logPrefix) [setup] accessibility-status result: not_granted")
                return false
            default:
                if process.terminationStatus == 0 {
                    logToSetup?("\(logPrefix) [setup] accessibility-status parsed unknown result from result file")
                } else {
                    logToSetup?("\(logPrefix) [setup] accessibility-status failed: status=\(process.terminationStatus), reason=result_file_invalid")
                }
                return nil
            }
        } catch {
            logToSetup?("\(logPrefix) [setup] accessibility-status command failed: \(error.localizedDescription)")
            // Fall back to direct executable check below if possible.
        }
    } else {
        logToSetup?(
            "\(setupLogPrefix()) [setup] accessibility-status skipped: \(appBundlePath), reason=app_not_found; falling back to executable check"
        )
    }

    let logPrefix = setupLogPrefix()
    let fm = FileManager.default
    if !fm.fileExists(atPath: executablePath) {
        logToSetup?("\(logPrefix) [setup] accessibility-status skipped: \(executablePath), reason=not_found")
        return nil
    }
    if !fm.isExecutableFile(atPath: executablePath) {
        logToSetup?("\(logPrefix) [setup] accessibility-status skipped: \(executablePath), reason=not_executable")
        return nil
    }

    do {
        let status = try runProcess(executablePath, ["__accessibility-status"])
        logToSetup?("\(logPrefix) [setup] accessibility-status executed: \(executablePath), exit=\(status)")
        if status == 0 {
            logToSetup?("\(logPrefix) [setup] accessibility-status result: granted")
            return true
        }
        if status == 1 {
            logToSetup?("\(logPrefix) [setup] accessibility-status result: not_granted")
            return false
        }
        logToSetup?("\(logPrefix) [setup] accessibility-status failed: status=\(status), reason=other")
        return nil
    } catch {
        logToSetup?("\(logPrefix) [setup] accessibility-status failed: \(error.localizedDescription)")
        return nil
    }
}

func checkAccessibilityPermission() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func checkAccessibilityPermissionWithPrompt(prompt: Bool) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

func executablePath() -> String {
    CommandLine.arguments.first ?? ""
}

func isAppBundleExecutable(path: String) -> Bool {
    let url = URL(fileURLWithPath: path)
    let macOSDir = url.deletingLastPathComponent()
    let contentsDir = macOSDir.deletingLastPathComponent()
    let appDir = contentsDir.deletingLastPathComponent()
    return macOSDir.lastPathComponent == "MacOS" &&
    contentsDir.lastPathComponent == "Contents" &&
    appDir.pathExtension == "app"
}

func shouldHandleDirectOpenInvocation() -> Bool {
    let args = Array(CommandLine.arguments.dropFirst())
    return isAppBundleExecutable(path: executablePath()) && args.allSatisfy { $0.hasPrefix("-psn_") }
}

func runningAppBundlePath() -> String {
    let url = URL(fileURLWithPath: executablePath())
    let appDir = url
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return appDir.path
}

func handleDirectOpen() {
    if checkAccessibilityPermissionWithPrompt(prompt: false) {
        print("Accessibility permission is already enabled for this app.")
        return
    }

    _ = checkAccessibilityPermissionWithPrompt(prompt: true)
    print("Accessibility permission is required.")
    print("Open System Settings > Privacy & Security > Accessibility, then enable:")
    print("  \(runningAppBundlePath())")
}
