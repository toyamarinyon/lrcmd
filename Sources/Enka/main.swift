@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import Darwin

enum EnkaError: Error, CustomStringConvertible {
    case invalidArguments
    case accessibilityPermissionRequired
    case eventTapCreationFailed
    case runLoopSourceCreationFailed

    var description: String {
        switch self {
        case .invalidArguments:
            return "invalid arguments"
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required. Enable it in System Settings > Privacy & Security > Accessibility."
        case .eventTapCreationFailed:
            return "Failed to create keyboard event tap. Check Accessibility permission."
        case .runLoopSourceCreationFailed:
            return "Failed to create run loop source for keyboard event tap."
        }
    }
}

enum CommandSide {
    case left
    case right
}

struct KeyState {
    var isPressed = false
    var sawOtherKey = false
}

final class LauncherState {
    private let leftKeyCode: CGKeyCode = 55
    private let rightKeyCode: CGKeyCode = 54
    private let leftTapKeyCode: CGKeyCode = 102
    private let rightTapKeyCode: CGKeyCode = 104

    private var leftState = KeyState()
    private var rightState = KeyState()

    func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .keyDown:
            if keyCode == leftKeyCode {
                leftState.isPressed = true
                leftState.sawOtherKey = false
            } else if keyCode == rightKeyCode {
                rightState.isPressed = true
                rightState.sawOtherKey = false
            } else {
                markOtherKeyPressed()
            }

        case .flagsChanged:
            if keyCode == leftKeyCode {
                if leftState.isPressed {
                    handleCommandRelease(.left)
                } else {
                    handleCommandPress(.left)
                }
            } else if keyCode == rightKeyCode {
                if rightState.isPressed {
                    handleCommandRelease(.right)
                } else {
                    handleCommandPress(.right)
                }
            }

        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleCommandPress(_ side: CommandSide) {
        switch side {
        case .left:
            let rightWasPressed = rightState.isPressed
            if rightWasPressed {
                rightState.sawOtherKey = true
            }
            leftState.isPressed = true
            leftState.sawOtherKey = rightWasPressed

        case .right:
            let leftWasPressed = leftState.isPressed
            if leftWasPressed {
                leftState.sawOtherKey = true
            }
            rightState.isPressed = true
            rightState.sawOtherKey = leftWasPressed
        }
    }

    private func markOtherKeyPressed() {
        if leftState.isPressed {
            leftState.sawOtherKey = true
        }
        if rightState.isPressed {
            rightState.sawOtherKey = true
        }
    }

    private func handleCommandRelease(_ side: CommandSide) {
        switch side {
        case .left:
            defer {
                leftState.isPressed = false
                leftState.sawOtherKey = false
            }
            guard leftState.isPressed, !leftState.sawOtherKey else {
                return
            }
            postTapKey(leftTapKeyCode)

        case .right:
            defer {
                rightState.isPressed = false
                rightState.sawOtherKey = false
            }
            guard rightState.isPressed, !rightState.sawOtherKey else {
                return
            }
            postTapKey(rightTapKeyCode)
        }
    }

    private func postTapKey(_ keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
            return
        }
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

func usage(progname: String) -> String {
    """
    Usage:
      \(progname) [run]
      \(progname) install [--no-open] [--no-start] [--wait-accessibility <seconds>]
      \(progname) status
      \(progname) uninstall
      \(progname) restart
      \(progname) stop
    """
}

func writeStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

private let isTTY = isatty(STDOUT_FILENO) == 1

nonisolated(unsafe) private let setupDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

func printStep(_ message: String) {
    if isTTY {
        print("→ \(message)", terminator: "")
        fflush(stdout)
    } else {
        print("→ \(message)")
    }
}

func printDone(_ message: String) {
    if isTTY {
        print("\r\u{001B}[K✓ \(message)")
    } else {
        print("✓ \(message)")
    }
}

func printAccessibilityWait() {
    print("→ Waiting for Accessibility permission")
    if isTTY {
        print("  Enka needs Accessibility to observe Command key taps.", terminator: "")
        fflush(stdout)
    } else {
        print("  Enka needs Accessibility to observe Command key taps.")
    }
}

func printAccessibilityDone(replacingWait: Bool) {
    if isTTY && replacingWait {
        print("\r\u{001B}[K\u{001B}[1A\r\u{001B}[K✓ Accessibility permission granted")
    } else {
        printDone("Accessibility permission granted")
    }
}

func finishAccessibilityWaitBeforeMessage(_ replacingWait: Bool) {
    if isTTY && replacingWait {
        print("")
    }
}

enum EnkaCommand {
    case run
    case status
    case accessibilityStatus(resultFile: String?)
    case setup(
        noOpen: Bool,
        noStart: Bool,
        waitAccessibilitySeconds: Int
    )
    case uninstall
    case restart
    case stop
}

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

func confirm(_ prompt: String, defaultYes: Bool = false) -> Bool {
    print(prompt, terminator: " ")
    guard let line = readLine() else {
        return defaultYes
    }
    let response = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if response.isEmpty {
        return defaultYes
    }
    switch response {
    case "y", "yes":
        return true
    case "n", "no":
        return false
    default:
        return false
    }
}

func ensureDirectory(atPath path: String) throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: path) {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
}

func printSetupSummary(plistPath: String) {
    print("Summary:")
    print("  left Command:  posts JIS Eisuu key (102)")
    print("  right Command: posts JIS Kana key (104)")
    print("  plist path:    \(plistPath)")
    print("  app path:      \(installedAppPath())")
    print("  enka binary:  \(installedBinaryPath())")
}

func runOpenEnkaApp(logToSetup: ((String) -> Void)? = nil) throws {
    logToSetup?("\(setupLogPrefix()) [setup] open command start: /usr/bin/open \(installedAppPath())")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [installedAppPath()]
    do {
        try process.run()
        process.waitUntilExit()
        logToSetup?("\(setupLogPrefix()) [setup] open command finished: status=\(process.terminationStatus)")
    } catch {
        logToSetup?("\(setupLogPrefix()) [setup] open command error: \(error.localizedDescription)")
        throw error
    }
}

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

func waitForAccessibilityPermissionViaAppExecutable(
    executablePath: String,
    appBundlePath: String,
    timeoutSeconds: Int,
    waitWasDisplayed: inout Bool,
    logToSetup: ((String) -> Void)? = nil
) -> Bool? {
    let target = max(0, timeoutSeconds)
    let initialPermission = runAccessibilityStatusSubcommand(
        executablePath: executablePath,
        appBundlePath: appBundlePath,
        logToSetup: logToSetup
    )
    if let initialPermission {
        logToSetup?("\(setupLogPrefix()) [setup] wait accessibility initial_status=\(initialPermission ? "granted" : "not_granted")")
        if initialPermission {
            return true
        }
    } else {
        logToSetup?("\(setupLogPrefix()) [setup] wait accessibility initial_status=unavailable")
        return nil
    }

    if target == 0 {
        logToSetup?("\(setupLogPrefix()) [setup] wait accessibility timeout_seconds=0: no_wait")
        return false
    }

    printAccessibilityWait()
    waitWasDisplayed = true

    for attempt in 1...target {
        sleep(1)
        guard let status = runAccessibilityStatusSubcommand(
            executablePath: executablePath,
            appBundlePath: appBundlePath,
            logToSetup: logToSetup
        ) else {
            logToSetup?("\(setupLogPrefix()) [setup] wait accessibility poll attempt=\(attempt) elapsed=\(attempt)s status=unavailable")
            return nil
        }
        logToSetup?("\(setupLogPrefix()) [setup] wait accessibility poll attempt=\(attempt) elapsed=\(attempt)s status=\(status ? "granted" : "not_granted")")
        if status {
            logToSetup?("\(setupLogPrefix()) [setup] wait accessibility granted detected attempt=\(attempt)")
            return true
        }
    }

    let finalPermission = runAccessibilityStatusSubcommand(
        executablePath: executablePath,
        appBundlePath: appBundlePath,
        logToSetup: logToSetup
    )
    if let finalPermission {
        logToSetup?(
            "\(setupLogPrefix()) [setup] wait accessibility timeout seconds=\(target) final_status=\(finalPermission ? "granted" : "not_granted")"
        )
    } else {
        logToSetup?("\(setupLogPrefix()) [setup] wait accessibility timeout seconds=\(target) final_status=unavailable")
    }
    return finalPermission
}

func waitForAccessibilityPermission(timeoutSeconds: Int) -> Bool {
    let target = max(0, timeoutSeconds)
    if checkAccessibilityPermission() {
        return true
    }

    if target == 0 {
        return false
    }

    for _ in 0..<target {
        if checkAccessibilityPermission() {
            return true
        }
        sleep(1)
    }

    return checkAccessibilityPermission()
}

func runSetup(
    noOpen: Bool,
    noStart: Bool,
    waitAccessibilitySeconds: Int
) {
    let plistPath = launchAgentPlistPath()
    let plistDir = (plistPath as NSString).deletingLastPathComponent
    let stateDir = stateDirectoryPath()
    let setupLog = setupLogPath()
    let logToSetup: (String) -> Void = { message in
        writeSetupLog(setupLog, message)
    }

    do {
        try ensureDirectory(atPath: stateDir)
    } catch {
        writeStderr("error: failed to create state directory at \(stateDir): \(error.localizedDescription)\n")
        print("Setup log: (unable to create state directory)")
    }
    logToSetup(
        "\(setupLogPrefix()) [setup] start plistPath=\(plistPath) appPath=\(installedAppPath()) appExecutablePath=\(installedAppExecutablePath()) noOpen=\(noOpen) noStart=\(noStart) waitAccessibilitySeconds=\(waitAccessibilitySeconds)"
    )

    let fm = FileManager.default
    let previousPlistExists = fm.fileExists(atPath: plistPath)

    do {
        try ensureDirectory(atPath: plistDir)
        try ensureDirectory(atPath: stateDir)
        let plistContent = launchAgentPlist()
        try plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
    } catch {
        writeStderr("error: failed to write launch agent plist at \(plistPath): \(error.localizedDescription)\n")
        exit(1)
    }
    logToSetup("\(setupLogPrefix()) [setup] wrote plist: \(plistPath)")
    printSetupSummary(plistPath: plistPath)
    print("Plist:  \(previousPlistExists ? "Updated" : "Created"): \(plistPath)")

    let appExecutablePath = installedAppExecutablePath()
    let appBundlePath = installedAppPath()
    let permissionGrantedByApp = runAccessibilityStatusSubcommand(
        executablePath: appExecutablePath,
        appBundlePath: appBundlePath,
        logToSetup: logToSetup
    )
    var permissionGranted = permissionGrantedByApp ?? false
    var proceedWithoutAppStatus = false
    var displayedAccessibilityWait = false

    if permissionGrantedByApp == nil {
        logToSetup("\(setupLogPrefix()) [setup] skipping start/restart: app status unavailable before open")
        print("Could not verify Accessibility status from app executable.")
        print("Please run:")
        print("  open \(installedAppPath())")
        print("Then enable Accessibility and run:")
        print("  enka restart")
        return
    }

    if !permissionGranted {
        if noOpen {
            print("Accessibility permission missing.")
            print("Manual open command: open \(installedAppPath())")
            print("Please grant Accessibility and then run:")
            print("  enka restart")
            logToSetup(
                "\(setupLogPrefix()) [setup] skipping start/restart: noOpen and app permission missing"
            )
            return
        }

        if !noOpen {
            do {
                try runOpenEnkaApp(logToSetup: logToSetup)
            } catch {
                print("warning: failed to run open: \(error.localizedDescription)")
                print("Please run manually:")
                print("  open \(installedAppPath())")
                logToSetup("\(setupLogPrefix()) [setup] open command failed; cannot wait for permission")
            }
        }

        if let appStatus = waitForAccessibilityPermissionViaAppExecutable(
            executablePath: appExecutablePath,
            appBundlePath: appBundlePath,
            timeoutSeconds: waitAccessibilitySeconds,
            waitWasDisplayed: &displayedAccessibilityWait,
            logToSetup: logToSetup
        ) {
            permissionGranted = appStatus
        } else {
            logToSetup("\(setupLogPrefix()) [setup] skipping start/restart: app status unavailable during wait")
            proceedWithoutAppStatus = true
        }
    }

    if proceedWithoutAppStatus {
        logToSetup("\(setupLogPrefix()) [setup] no start/restart due to app status unavailable")
        finishAccessibilityWaitBeforeMessage(displayedAccessibilityWait)
        print("Could not verify Accessibility status from app executable while waiting.")
        print("Please run:")
        print("  open \(installedAppPath())")
        print("Then enable Accessibility and run:")
        print("  enka restart")
        return
    }

    if !permissionGranted {
        logToSetup(
            "\(setupLogPrefix()) [setup] skipping start/restart: permission not granted within timeout=\(waitAccessibilitySeconds)"
        )
        finishAccessibilityWaitBeforeMessage(displayedAccessibilityWait)
        print("Accessibility permission was not granted within \(waitAccessibilitySeconds) seconds.")
        print("Please run:")
        print("  open \(installedAppPath())")
        print("Then enable Accessibility and run:")
        print("  enka restart")
        return
    }

    if noStart {
        logToSetup("\(setupLogPrefix()) [setup] no start/restart: --no-start was specified")
        printAccessibilityDone(replacingWait: displayedAccessibilityWait)
        print("Skipping launchctl because --no-start was specified.")
        print("Run:")
        print("  enka restart")
        return
    }

    printAccessibilityDone(replacingWait: displayedAccessibilityWait)
    logToSetup("\(setupLogPrefix()) [setup] proceeding to restart; launching launchctl restart sequence")
    runRestartCommands(plistPath: plistPath, logToSetup: logToSetup)
}

func parseArguments(_ arguments: [String]) throws -> EnkaCommand {
    let args = Array(arguments.dropFirst())

    if args.isEmpty {
        return .run
    }

    guard let command = args.first else { throw EnkaError.invalidArguments }

    if command == "run" {
        if args.count == 1 {
            return .run
        }
        throw EnkaError.invalidArguments
    }

    switch command {
    case "install":
        var noOpen = false
        var noStart = false
        var waitAccessibilitySeconds = 120
        var didSetWaitAccessibility = false

        var index = 1
        while index < args.count {
            let flag = args[index]
            switch flag {
            case "--no-open":
                if noOpen {
                    throw EnkaError.invalidArguments
                }
                noOpen = true
            case "--no-start":
                if noStart {
                    throw EnkaError.invalidArguments
                }
                noStart = true
            case "--wait-accessibility":
                if didSetWaitAccessibility {
                    throw EnkaError.invalidArguments
                }
                if index + 1 >= args.count {
                    throw EnkaError.invalidArguments
                }
                guard let value = Int(args[index + 1]), value >= 0 else {
                    throw EnkaError.invalidArguments
                }
                waitAccessibilitySeconds = value
                didSetWaitAccessibility = true
                index += 1
            default:
                throw EnkaError.invalidArguments
            }
            index += 1
        }

        return .setup(
            noOpen: noOpen,
            noStart: noStart,
            waitAccessibilitySeconds: waitAccessibilitySeconds
        )
    case "__accessibility-status":
        if args.count == 1 {
            return .accessibilityStatus(resultFile: nil)
        }
        guard args.count == 3 else {
            throw EnkaError.invalidArguments
        }
        guard args[1] == "--result-file" else {
            throw EnkaError.invalidArguments
        }
        return .accessibilityStatus(resultFile: args[2])
    case "uninstall":
        guard args.count == 1 else { throw EnkaError.invalidArguments }
        return .uninstall
    case "status":
        guard args.count == 1 else { throw EnkaError.invalidArguments }
        return .status
    case "restart":
        guard args.count == 1 else { throw EnkaError.invalidArguments }
        return .restart
    case "stop":
        guard args.count == 1 else { throw EnkaError.invalidArguments }
        return .stop
    default:
        throw EnkaError.invalidArguments
    }
}

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

func runProcess(_ executable: String, _ args: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = args
    let stdout = Pipe()
    process.standardOutput = stdout
    let stderr = Pipe()
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func runLaunchctl(args: [String], context: String, quiet: Bool = false) -> Int32 {
    if !quiet {
        print("launchctl \(args.joined(separator: " "))")
    }

    do {
        let status = try runProcess("/bin/launchctl", args)
        if quiet {
            return status
        } else if status == 0 {
            print("succeeded: \(context)")
        } else {
            print("warning: \(context) failed with status \(status)")
        }
        return status
    } catch {
        writeStderr("error: failed to run launchctl \(args.joined(separator: " ")): \(error.localizedDescription)\n")
        return 1
    }
}

func runRestartCommands(plistPath: String, logToSetup: ((String) -> Void)? = nil) {
    let uid = getuid()
    let bootoutArgs = ["bootout", "gui/\(uid)", plistPath]
    let bootstrapArgs = ["bootstrap", "gui/\(uid)", plistPath]
    let kickstartArgs = ["kickstart", "-k", launchctlServiceTarget()]

    logToSetup?("\(setupLogPrefix()) [setup] launchctl bootout: launchctl \(bootoutArgs.joined(separator: " "))")
    logToSetup?("\(setupLogPrefix()) [setup] launchctl bootstrap: launchctl \(bootstrapArgs.joined(separator: " "))")
    logToSetup?("\(setupLogPrefix()) [setup] launchctl kickstart: launchctl \(kickstartArgs.joined(separator: " "))")
    printStep("Registering LaunchAgent")

    let bootoutStatus = runLaunchctl(args: bootoutArgs, context: "bootout", quiet: true)
    if bootoutStatus != 0 {
        logToSetup?("\(setupLogPrefix()) [setup] launchctl bootout failed status=\(bootoutStatus); continuing restart")
    }
    let bootstrapStatus = runLaunchctl(args: bootstrapArgs, context: "bootstrap", quiet: true)
    if bootstrapStatus != 0 {
        logToSetup?("\(setupLogPrefix()) [setup] launchctl bootstrap failed status=\(bootstrapStatus)")
        writeStderr("error: launchctl bootstrap failed.\n")
        exit(1)
    }
    let kickstartStatus = runLaunchctl(args: kickstartArgs, context: "kickstart", quiet: true)
    if kickstartStatus != 0 {
        logToSetup?("\(setupLogPrefix()) [setup] launchctl kickstart failed status=\(kickstartStatus)")
        writeStderr("error: launchctl kickstart failed.\n")
        exit(1)
    }
    printDone("LaunchAgent registered")
}

func runStopCommands(plistPath: String) {
    let uid = getuid()
    let args = ["bootout", "gui/\(uid)", plistPath]

    print("UID: \(uid)")
    print("launchctl \(args.joined(separator: " "))")

    if runLaunchctl(args: args, context: "bootout") != 0 {
        writeStderr("error: launchctl bootout failed.\n")
        exit(1)
    }
}

func isSafeInstallRootPath(_ path: String) -> Bool {
    let normalized = NSString(string: path).standardizingPath
    if normalized.isEmpty {
        return false
    }

    let home = userHomeDirectory()
    let prohibited: Set<String> = ["/", home, home.appending("/Applications")]
    if prohibited.contains(normalized) {
        return false
    }

    guard (normalized as NSString).pathComponents.last == "enka" else {
        return false
    }

    return true
}

func runUninstall() {
    let fm = FileManager.default
    let uid = getuid()
    let plistPath = launchAgentPlistPath()
    let installRoot = defaultInstallRoot()
    let hasPlist = fm.fileExists(atPath: plistPath)

    let shouldUninstall = confirm("Uninstall Enka and remove installed files? [y/N]")
    if !shouldUninstall {
        print("Uninstall cancelled.")
        return
    }

    if hasPlist {
        printStep("Stopping LaunchAgent")
        let status = runLaunchctl(args: ["bootout", "gui/\(uid)", plistPath], context: "bootout", quiet: true)
        if status == 0 {
            printDone("LaunchAgent stopped")
        } else {
            printDone("LaunchAgent was not running")
        }
    }

    if fm.fileExists(atPath: plistPath) {
        do {
            printStep("Removing LaunchAgent plist")
            try fm.removeItem(atPath: plistPath)
            printDone("Removed LaunchAgent plist")
        } catch {
            writeStderr("error: failed to remove plist at \(plistPath): \(error.localizedDescription)\n")
            exit(1)
        }
    }

    if fm.fileExists(atPath: installRoot) {
        if isSafeInstallRootPath(installRoot) {
            do {
                printStep("Removing installed files")
                try fm.removeItem(atPath: installRoot)
                printDone("Removed installed files")
            } catch {
                writeStderr("error: failed to remove installed binaries at \(installRoot): \(error.localizedDescription)\n")
                exit(1)
            }
        } else {
            print("Install root was kept because the path is too broad or unsafe:")
            print("  \(installRoot)")
        }
    }

    print("")
    print("✓ Uninstall complete")
    print("  Accessibility permission is managed by macOS and may remain listed.")
    print("  To remove it manually, open Accessibility settings, select Enka,")
    print("  then click the minus button below the app list.")
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

func createEventTap(state: LauncherState) throws -> CFMachPort {
    let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

    let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let launcherState = Unmanaged<LauncherState>.fromOpaque(userInfo).takeUnretainedValue()
        return launcherState.handle(event: event, type: type)
    }

    guard let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(mask),
        callback: callback,
        userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(state).toOpaque())
    ) else {
        throw EnkaError.eventTapCreationFailed
    }

    return eventTap
}

func runDaemon() throws {
    let state = LauncherState()

    guard checkAccessibilityPermission() else {
        throw EnkaError.accessibilityPermissionRequired
    }

    let eventTap = try createEventTap(state: state)

    guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
        throw EnkaError.runLoopSourceCreationFailed
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    CFRunLoopRun()
}

do {
    let arguments = CommandLine.arguments
    if shouldHandleDirectOpenInvocation() {
        handleDirectOpen()
        exit(0)
    }

    let command = try parseArguments(arguments)

    switch command {
    case .run:
        try runDaemon()
    case let .accessibilityStatus(resultFile):
        let isGranted = checkAccessibilityPermission()
        if let resultFile {
            do {
                try (isGranted ? "granted" : "not_granted").write(
                    toFile: resultFile,
                    atomically: true,
                    encoding: .utf8
                )
            } catch {
                writeStderr("enka: failed to write accessibility status result to \(resultFile): \(error.localizedDescription)\n")
                exit(1)
            }
        }
        exit(isGranted ? 0 : 1)
    case let .setup(noOpen, noStart, waitAccessibilitySeconds):
        runSetup(
            noOpen: noOpen,
            noStart: noStart,
            waitAccessibilitySeconds: waitAccessibilitySeconds
        )
    case .uninstall:
        runUninstall()
    case .status:
        printStatus()
    case .restart:
        let plist = launchAgentPlistPath()
        if !FileManager.default.fileExists(atPath: plist) {
            writeStderr("error: LaunchAgent plist missing: \(plist). Run the installer again.\n")
            exit(1)
        }
        runRestartCommands(plistPath: plist)
    case .stop:
        let plist = launchAgentPlistPath()
        if !FileManager.default.fileExists(atPath: plist) {
            writeStderr("error: LaunchAgent plist missing: \(plist). Run the installer again.\n")
            exit(1)
        }
        runStopCommands(plistPath: plist)
    }
} catch let error as EnkaError {
    if case .invalidArguments = error {
        let progname = URL(fileURLWithPath: CommandLine.arguments.first ?? "enka").lastPathComponent
        writeStderr(usage(progname: progname) + "\n")
        writeStderr("enka: \(error.description)\n")
        exit(64)
    }
    writeStderr("enka: \(error.description)\n")
    exit(1)
} catch {
    writeStderr("enka: \(error.localizedDescription)\n")
    exit(1)
}
