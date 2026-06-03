@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import Darwin

struct Config: Decodable {
    struct Command: Decodable {
        let command: String
        let arguments: [String]

        private enum CodingKeys: String, CodingKey {
            case command
            case arguments
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            command = try container.decode(String.self, forKey: .command)
            arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        }
    }

    let leftCommand: Command
    let rightCommand: Command
}

enum LrcmdError: Error, CustomStringConvertible {
    case invalidArguments
    case accessibilityPermissionRequired
    case configReadFailed(String, Error)
    case configDecodeFailed(String, Error)
    case eventTapCreationFailed
    case runLoopSourceCreationFailed

    var description: String {
        switch self {
        case .invalidArguments:
            return "invalid arguments"
        case .accessibilityPermissionRequired:
            return "Accessibility permission is required. Enable it in System Settings > Privacy & Security > Accessibility."
        case let .configReadFailed(path, error):
            return "Failed to read config at '\(path)': \(error.localizedDescription)"
        case let .configDecodeFailed(path, error):
            return "Invalid config at '\(path)': \(error.localizedDescription)"
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

    private var leftState = KeyState()
    private var rightState = KeyState()
    var config: Config?

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
            guard leftState.isPressed, !leftState.sawOtherKey, let command = config?.leftCommand else {
                return
            }
            launch(command)

        case .right:
            defer {
                rightState.isPressed = false
                rightState.sawOtherKey = false
            }
            guard rightState.isPressed, !rightState.sawOtherKey, let command = config?.rightCommand else {
                return
            }
            launch(command)
        }
    }

    private func launch(_ command: Config.Command) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.command)
        process.arguments = command.arguments

        do {
            try process.run()
        } catch {
            writeStderr("lrcmd: failed to launch '\(command.command)': \(error.localizedDescription)\n")
        }
    }
}

func usage(progname: String) -> String {
    """
    Usage:
      \(progname) [run] [--config /path/to/config.json]
      \(progname) status [--dry-run]
      \(progname) doctor
      \(progname) setup [--yes] [--replace] [--dry-run] [--no-open] [--no-start] [--wait-accessibility <seconds>]
      \(progname) uninstall [--yes] [--dry-run]
      \(progname) restart [--dry-run]
      \(progname) stop [--dry-run]
    """
}

func writeStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

enum LrcmdCommand {
    case run(configPath: String)
    case status(dryRun: Bool)
    case doctor
    case accessibilityStatus(resultFile: String?)
    case setup(
        autoApprove: Bool,
        replaceExistingConfig: Bool,
        dryRun: Bool,
        noOpen: Bool,
        noStart: Bool,
        waitAccessibilitySeconds: Int
    )
    case uninstall(autoApprove: Bool, dryRun: Bool)
    case restart(dryRun: Bool)
    case stop(dryRun: Bool)
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
    envOverride("LRCMD_INSTALL_ROOT") ?? userHomeDirectory().appending("/Applications/lrcmd")
}

func defaultConfigDirectory() -> String {
    envOverride("LRCMD_CONFIG_DIR") ?? userHomeDirectory().appending("/.config/lrcmd")
}

func defaultLaunchAgentDirectory() -> String {
    envOverride("LRCMD_LAUNCH_AGENT_DIR") ?? userHomeDirectory().appending("/Library/LaunchAgents")
}

func stateDirectoryPath() -> String {
    userHomeDirectory().appending("/.local/state/lrcmd")
}

func standardOutputLogPath() -> String {
    stateDirectoryPath().appending("/lrcmd.log")
}

func standardErrorLogPath() -> String {
    stateDirectoryPath().appending("/lrcmd.err.log")
}

func setupLogPath() -> String {
    stateDirectoryPath().appending("/setup.log")
}

func setupLogPrefix() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: Date())
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

func defaultConfigPath() -> String {
    defaultConfigDirectory().appending("/config.json")
}

func installedAppPath() -> String {
    defaultInstallRoot().appending("/Lrcmd.app")
}

func installedAppExecutablePath() -> String {
    installedAppPath().appending("/Contents/MacOS/Lrcmd")
}

func installedAppInfoPlistPath() -> String {
    installedAppPath().appending("/Contents/Info.plist")
}

func installedBinaryPath() -> String {
    defaultInstallRoot().appending("/bin/lrcmd")
}

func bundledInctlPath() -> String {
    defaultInstallRoot().appending("/bin/inctl")
}

func launchAgentPlistPath() -> String {
    defaultLaunchAgentDirectory().appending("/dev.ultrahope.lrcmd.plist")
}

func launchctlLabel() -> String {
    "dev.ultrahope.lrcmd"
}

func launchctlDomain() -> String {
    "gui/\(getuid())"
}

func launchctlServiceTarget() -> String {
    "\(launchctlDomain())/\(launchctlLabel())"
}

func escapeXML(_ value: String) -> String {
    value
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

func launchAgentPlist(configPath: String) -> String {
    let programPath = installedAppExecutablePath()
    let logPath = standardOutputLogPath()
    let errPath = standardErrorLogPath()

    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>\(escapeXML("dev.ultrahope.lrcmd"))</string>
      <key>ProgramArguments</key>
      <array>
        <string>\(escapeXML(programPath))</string>
        <string>run</string>
        <string>--config</string>
        <string>\(escapeXML(configPath))</string>
      </array>
      <key>RunAtLoad</key>
      <true/>
      <key>KeepAlive</key>
      <true/>
      <key>StandardOutPath</key>
      <string>\(escapeXML(logPath))</string>
      <key>StandardErrorPath</key>
      <string>\(escapeXML(errPath))</string>
    </dict>
    </plist>
    """
}

func escapeJSON(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
}

struct InputSource {
    let id: String
    let name: String
}

func quotedPath(_ path: String) -> String {
    return "\"\(path)\""
}

func runInctlList(_ inctlPath: String) -> [InputSource]? {
    let fm = FileManager.default
    guard fm.fileExists(atPath: inctlPath) else {
        return nil
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: inctlPath)
    process.arguments = ["list"]

    let stdout = Pipe()
    process.standardOutput = stdout
    let stderr = Pipe()
    process.standardError = stderr

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        writeStderr("warning: failed to run inctl list: \(error.localizedDescription)\n")
        return nil
    }

    if process.terminationStatus != 0 {
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        let stderrOutput = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stderrOutput.isEmpty {
            writeStderr("warning: inctl list failed: \(stderrOutput)\n")
        } else {
            writeStderr("warning: inctl list exited with status \(process.terminationStatus)\n")
        }
        return nil
    }

    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
        return nil
    }

    let lines = output
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    var sources: [InputSource] = []
    for line in lines {
        let parts = line.split(separator: "\t", maxSplits: 1)
        guard parts.count == 2 else {
            continue
        }
        let id = String(parts[0])
        let name = String(parts[1])
        sources.append(InputSource(id: id, name: name))
    }

    return sources
}

func inputSourceName(for id: String, in sources: [InputSource]) -> String {
    for source in sources where source.id == id {
        return source.name
    }
    return "(not listed)"
}

func selectedInputSourceId(preferred: String, fallback: String, available: [InputSource]?) -> String {
    guard let available else {
        return preferred
    }
    if available.contains(where: { $0.id == preferred }) {
        return preferred
    }
    if available.contains(where: { $0.id == fallback }) {
        return fallback
    }
    return preferred
}

func defaultInputSourceIndex(
    available sources: [InputSource],
    preferred: String,
    fallback: String
) -> Int {
    if let idx = sources.firstIndex(where: { $0.id == preferred }) {
        return idx + 1
    }
    if let idx = sources.firstIndex(where: { $0.id == fallback }) {
        return idx + 1
    }
    return 1
}

func readChoice(prompt: String, defaultValue: Int, maxValue: Int) -> Int {
    while true {
        print(prompt, terminator: " ")
        guard let line = readLine() else {
            return defaultValue
        }

        let response = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if response.isEmpty {
            return defaultValue
        }

        guard let choice = Int(response), choice >= 1, choice <= maxValue else {
            print("warning: invalid choice: \(response). Enter a number between 1 and \(maxValue).")
            continue
        }
        return choice
    }
}

func chooseInputSource(
    prompt: String,
    sources: [InputSource],
    defaultIndex: Int
) -> InputSource {
    let choice = readChoice(prompt: prompt, defaultValue: defaultIndex, maxValue: sources.count)
    return sources[choice - 1]
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

func configurationJSON(inctlPath: String, leftSourceId: String, rightSourceId: String) -> String {
    return """
    {
      "leftCommand": {
        "command": "\(escapeJSON(inctlPath))",
        "arguments": ["select", "\(escapeJSON(leftSourceId))"]
      },
      "rightCommand": {
        "command": "\(escapeJSON(inctlPath))",
        "arguments": ["select", "\(escapeJSON(rightSourceId))"]
      }
    }
    """
}

func printSetupSummary(
    leftSourceId: String,
    rightSourceId: String,
    leftSourceName: String,
    rightSourceName: String,
    configPath: String,
    plistPath: String,
    inctlPath: String
) {
    print("Summary:")
    print("  left Command:  \(leftSourceId)/\(leftSourceName)")
    print("  right Command: \(rightSourceId)/\(rightSourceName)")
    print("  config path:   \(configPath)")
    print("  plist path:    \(plistPath)")
    print("  app path:      \(installedAppPath())")
    print("  lrcmd binary:  \(installedBinaryPath())")
    print("  inctl binary:  \(inctlPath)")
}

func runOpenLrcmdApp(logToSetup: ((String) -> Void)? = nil) throws {
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
            .appendingPathComponent("lrcmd_accessibility_status_\(UUID().uuidString).txt")
        defer {
            try? FileManager.default.removeItem(at: tempFile)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-W", "-n", appBundlePath, "--args", "__accessibility-status", "--result-file", tempFile.path]

        do {
            logToSetup?("\(logPrefix) [setup] accessibility-status command start: /usr/bin/open -W -n \(appBundlePath) --args __accessibility-status --result-file \(tempFile.path)")
            try process.run()
            process.waitUntilExit()
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

    if target > 0 {
        print("Waiting for Accessibility permission...")
    }

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
    autoApprove: Bool,
    replaceExistingConfig: Bool,
    dryRun: Bool,
    noOpen: Bool,
    noStart: Bool,
    waitAccessibilitySeconds: Int
) {
    let configPath = defaultConfigPath()
    let plistPath = launchAgentPlistPath()
    let inctlPath = bundledInctlPath()
    let configDir = defaultConfigDirectory()
    let plistDir = (plistPath as NSString).deletingLastPathComponent
    let stateDir = stateDirectoryPath()
    let setupLog = setupLogPath()
    let logToSetup: (String) -> Void = { message in
        writeSetupLog(setupLog, message)
    }

    if dryRun {
        print("Setup log: (dry-run; not written)")
    } else {
        do {
            try ensureDirectory(atPath: stateDir)
            print("Setup log: \(setupLog)")
        } catch {
            writeStderr("error: failed to create state directory at \(stateDir): \(error.localizedDescription)\n")
            print("Setup log: (unable to create state directory)")
        }
        logToSetup(
            "\(setupLogPrefix()) [setup] start configPath=\(configPath) plistPath=\(plistPath) appPath=\(installedAppPath()) appExecutablePath=\(installedAppExecutablePath()) dryRun=\(dryRun) noOpen=\(noOpen) noStart=\(noStart) waitAccessibilitySeconds=\(waitAccessibilitySeconds)"
        )
    }

    var availableSources: [InputSource]? = nil
    if FileManager.default.fileExists(atPath: inctlPath) {
        if let sources = runInctlList(inctlPath) {
            availableSources = sources
        } else {
            print("warning: could not list input sources from \(quotedPath(inctlPath)); using defaults.")
        }
    } else {
        print("warning: inctl binary not found at \(quotedPath(inctlPath)); using default source IDs.")
    }

    let preferredLeft = "com.apple.keylayout.ABC"
    let fallbackLeft = "com.apple.keylayout.US"
    let preferredRight = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"

    let leftSourceId: String
    let rightSourceId: String

    if autoApprove {
        leftSourceId = selectedInputSourceId(preferred: preferredLeft, fallback: fallbackLeft, available: availableSources)
        rightSourceId = preferredRight
    } else if let sources = availableSources, !sources.isEmpty {
        print("Available input sources:")
        for (index, source) in sources.enumerated() {
            print("  \(index + 1). \(source.id)    \(source.name)")
        }

        let leftDefault = defaultInputSourceIndex(
            available: sources,
            preferred: preferredLeft,
            fallback: fallbackLeft
        )
        let rightDefault = defaultInputSourceIndex(
            available: sources,
            preferred: preferredRight,
            fallback: preferredRight
        )

        let selectedLeftSource = chooseInputSource(
            prompt: "Choose left Command input source [default \(leftDefault)]:",
            sources: sources,
            defaultIndex: leftDefault
        )
        let selectedRightSource = chooseInputSource(
            prompt: "Choose right Command input source [default \(rightDefault)]:",
            sources: sources,
            defaultIndex: rightDefault
        )

        leftSourceId = selectedLeftSource.id
        rightSourceId = selectedRightSource.id
    } else {
        leftSourceId = selectedInputSourceId(preferred: preferredLeft, fallback: fallbackLeft, available: availableSources)
        rightSourceId = preferredRight
    }

    let leftSourceName = inputSourceName(for: leftSourceId, in: availableSources ?? [])
    let rightSourceName = inputSourceName(for: rightSourceId, in: availableSources ?? [])
    printSetupSummary(
        leftSourceId: leftSourceId,
        rightSourceId: rightSourceId,
        leftSourceName: leftSourceName,
        rightSourceName: rightSourceName,
        configPath: configPath,
        plistPath: plistPath,
        inctlPath: inctlPath
    )

    let fm = FileManager.default
    var doWritePlist = false
    var doWriteConfigFile = false
    let previousPlistExists = fm.fileExists(atPath: plistPath)
    var configResult = "Kept"
    var plistResult = "Kept"

    if dryRun {
        print("Running setup in dry-run mode. No files will be written.")
    }

    if fm.fileExists(atPath: configPath) {
        print("Config exists: \(configPath)")
        if replaceExistingConfig {
            if autoApprove {
                print("Replacing existing config: \(configPath)")
                doWriteConfigFile = true
                doWritePlist = true
                configResult = "Updated"
            } else if confirm("Replace existing config and update LaunchAgent plist? [y/N]") {
                print("Replacing existing config: \(configPath)")
                doWriteConfigFile = true
                doWritePlist = true
                configResult = "Updated"
            } else {
                print("No changes were made.")
                return
            }
        } else if autoApprove {
            print("Config already exists. Keeping existing config (not replaced without --replace).")
            configResult = "Kept"
            doWritePlist = true
        } else if confirm("Keep existing config and update LaunchAgent plist? [Y/n]", defaultYes: true) {
            configResult = "Kept"
            doWritePlist = true
        } else {
            print("No changes were made.")
            return
        }
    } else {
        if autoApprove || confirm("Create config and LaunchAgent plist? [y/N]") {
            doWriteConfigFile = true
            doWritePlist = true
            configResult = "Created"
        } else {
            print("No changes were made.")
            return
        }
    }

    if doWriteConfigFile {
        if dryRun {
            print("Planned file write: \(configPath)")
        } else {
            do {
                try ensureDirectory(atPath: configDir)
                try ensureDirectory(atPath: plistDir)
                try ensureDirectory(atPath: stateDir)
                try doWriteConfig(at: configPath, leftSourceId: leftSourceId, rightSourceId: rightSourceId, inctlPath: inctlPath)
            } catch {
                writeStderr("error: failed to write config at \(configPath): \(error.localizedDescription)\n")
                exit(1)
            }
            logToSetup("\(setupLogPrefix()) [setup] wrote config: \(configPath)")
        }
    }

    if doWritePlist {
        if dryRun {
            print("Planned file write: \(plistPath)")
            print("  new LaunchAgent plist content")
            plistResult = previousPlistExists ? "Updated (would overwrite)" : "Created"
        } else {
            do {
                if !doWriteConfigFile {
                    try ensureDirectory(atPath: plistDir)
                    try ensureDirectory(atPath: stateDir)
                }
                let plistContent = launchAgentPlist(configPath: configPath)
                try plistContent.write(toFile: plistPath, atomically: true, encoding: .utf8)
                plistResult = previousPlistExists ? "Updated (overwritten)" : "Created"
            } catch {
                writeStderr("error: failed to write launch agent plist at \(plistPath): \(error.localizedDescription)\n")
                exit(1)
            }
            logToSetup("\(setupLogPrefix()) [setup] wrote plist: \(plistPath)")
        }
    }

    let didChange = doWriteConfigFile || doWritePlist
    if !didChange {
        print("No changes were made.")
        return
    }

    print("Config: \(configResult): \(configPath)")
    print("Plist:  \(plistResult): \(plistPath)")

    if dryRun {
        print("No files will be written, no apps opened, no launchctl commands run.")
        print("Planned open: \(noOpen ? "(skipped) manual command shown below" : installedAppPath())")
        print("Planned wait for Accessibility: \(waitAccessibilitySeconds) seconds")
        print("Planned launchctl restart: \(noStart ? "skip" : "run")")

        var nextRunCommands: [String] = []
        if !noOpen {
            nextRunCommands.append("open \(installedAppPath())")
        }
        if !noStart {
            nextRunCommands.append("lrcmd restart")
        }
        if !nextRunCommands.isEmpty {
            print("Next (actual run):")
            for command in nextRunCommands {
                print("  \(command)")
            }
        } else {
            print("Next (actual run): none in dry-run.")
        }
        return
    }

    let shouldOpen = doWritePlist || doWriteConfigFile
    let appExecutablePath = installedAppExecutablePath()
    let appBundlePath = installedAppPath()
    let permissionGrantedByApp = shouldOpen ? runAccessibilityStatusSubcommand(
        executablePath: appExecutablePath,
        appBundlePath: appBundlePath,
        logToSetup: dryRun ? nil : logToSetup
    ) : true
    var permissionGranted = permissionGrantedByApp ?? false
    var proceedWithoutAppStatus = false

    if shouldOpen && permissionGrantedByApp == nil {
        if !dryRun {
            logToSetup("\(setupLogPrefix()) [setup] skipping start/restart: app status unavailable before open")
        }
        print("Could not verify Accessibility status from app executable.")
        print("Please run:")
        print("  open \(installedAppPath())")
        print("Then enable Accessibility and run:")
        print("  lrcmd restart")
        return
    }

    if shouldOpen && !permissionGranted {
        if noOpen {
            print("Accessibility permission missing.")
            print("Manual open command: open \(installedAppPath())")
            print("Please grant Accessibility and then run:")
            print("  lrcmd restart")
            if !dryRun {
                logToSetup(
                    "\(setupLogPrefix()) [setup] skipping start/restart: noOpen and app permission missing"
                )
            }
            return
        }

        if !noOpen {
            print("Opening \(installedAppPath()) ...")
            do {
                try runOpenLrcmdApp(logToSetup: dryRun ? nil : logToSetup)
            } catch {
                print("warning: failed to run open: \(error.localizedDescription)")
                print("Please run manually:")
                print("  open \(installedAppPath())")
                if !dryRun {
                    logToSetup("\(setupLogPrefix()) [setup] open command failed; cannot wait for permission")
                }
            }
        }

        if let appStatus = waitForAccessibilityPermissionViaAppExecutable(
            executablePath: appExecutablePath,
            appBundlePath: appBundlePath,
            timeoutSeconds: waitAccessibilitySeconds,
            logToSetup: dryRun ? nil : logToSetup
        ) {
            permissionGranted = appStatus
        } else {
            if !dryRun {
                logToSetup("\(setupLogPrefix()) [setup] skipping start/restart: app status unavailable during wait")
            }
            proceedWithoutAppStatus = true
        }
    }

    if proceedWithoutAppStatus {
        if !dryRun {
            logToSetup("\(setupLogPrefix()) [setup] no start/restart due to app status unavailable")
        }
        print("Could not verify Accessibility status from app executable while waiting.")
        print("Please run:")
        print("  open \(installedAppPath())")
        print("Then enable Accessibility and run:")
        print("  lrcmd restart")
        return
    }

    if !permissionGranted {
        if !dryRun {
            logToSetup(
                "\(setupLogPrefix()) [setup] skipping start/restart: permission not granted within timeout=\(waitAccessibilitySeconds)"
            )
        }
        print("Accessibility permission was not granted within \(waitAccessibilitySeconds) seconds.")
        print("Please run:")
        print("  open \(installedAppPath())")
        print("Then enable Accessibility and run:")
        print("  lrcmd restart")
        return
    }

    if noStart {
        if !dryRun {
            logToSetup("\(setupLogPrefix()) [setup] no start/restart: --no-start was specified")
        }
        print("Permission granted.")
        print("Skipping launchctl because --no-start was specified.")
        print("Run:")
        print("  lrcmd restart")
        return
    }

    print("Accessibility permission granted.")
    if !dryRun {
        logToSetup("\(setupLogPrefix()) [setup] proceeding to restart; launching launchctl restart sequence")
    }
    runRestartCommands(plistPath: plistPath, dryRun: dryRun)
}

func doWriteConfig(
    at path: String,
    leftSourceId: String,
    rightSourceId: String,
    inctlPath: String
) throws {
    let json = configurationJSON(inctlPath: inctlPath, leftSourceId: leftSourceId, rightSourceId: rightSourceId)
    try json.write(toFile: path, atomically: true, encoding: .utf8)
}

func parseArguments(_ arguments: [String]) throws -> LrcmdCommand {
    let args = Array(arguments.dropFirst())

    if args.isEmpty {
        return .run(configPath: defaultConfigPath())
    }

    if args.first == "--config" {
        guard args.count == 2 else { throw LrcmdError.invalidArguments }
        return .run(configPath: args[1])
    }

    guard let command = args.first else { throw LrcmdError.invalidArguments }

    if command == "run" {
        if args.count == 1 {
            return .run(configPath: defaultConfigPath())
        }
        if args.count == 3 && args[1] == "--config" {
            return .run(configPath: args[2])
        }
        throw LrcmdError.invalidArguments
    }

    switch command {
    case "setup":
        var autoApprove = false
        var replaceExistingConfig = false
        var dryRun = false
        var noOpen = false
        var noStart = false
        var waitAccessibilitySeconds = 120
        var didSetWaitAccessibility = false

        var index = 1
        while index < args.count {
            let flag = args[index]
            switch flag {
            case "--yes":
                if autoApprove {
                    throw LrcmdError.invalidArguments
                }
                autoApprove = true
            case "--replace":
                if replaceExistingConfig {
                    throw LrcmdError.invalidArguments
                }
                replaceExistingConfig = true
            case "--dry-run":
                if dryRun {
                    throw LrcmdError.invalidArguments
                }
                dryRun = true
            case "--no-open":
                if noOpen {
                    throw LrcmdError.invalidArguments
                }
                noOpen = true
            case "--no-start":
                if noStart {
                    throw LrcmdError.invalidArguments
                }
                noStart = true
            case "--wait-accessibility":
                if didSetWaitAccessibility {
                    throw LrcmdError.invalidArguments
                }
                if index + 1 >= args.count {
                    throw LrcmdError.invalidArguments
                }
                guard let value = Int(args[index + 1]), value >= 0 else {
                    throw LrcmdError.invalidArguments
                }
                waitAccessibilitySeconds = value
                didSetWaitAccessibility = true
                index += 1
            default:
                throw LrcmdError.invalidArguments
            }
            index += 1
        }

        return .setup(
            autoApprove: autoApprove,
            replaceExistingConfig: replaceExistingConfig,
            dryRun: dryRun,
            noOpen: noOpen,
            noStart: noStart,
            waitAccessibilitySeconds: waitAccessibilitySeconds
        )
    case "__accessibility-status":
        if args.count == 1 {
            return .accessibilityStatus(resultFile: nil)
        }
        guard args.count == 3 else {
            throw LrcmdError.invalidArguments
        }
        guard args[1] == "--result-file" else {
            throw LrcmdError.invalidArguments
        }
        return .accessibilityStatus(resultFile: args[2])
    case "uninstall":
        if args.count == 1 {
            return .uninstall(autoApprove: false, dryRun: false)
        }

        if args.count > 3 {
            throw LrcmdError.invalidArguments
        }

        var autoApprove = false
        var dryRun = false
        for flag in args.dropFirst() {
            switch flag {
            case "--yes":
                autoApprove = true
            case "--dry-run":
                dryRun = true
            default:
                throw LrcmdError.invalidArguments
            }
        }
        return .uninstall(autoApprove: autoApprove, dryRun: dryRun)
    case "status":
        if args.count == 1 {
            return .status(dryRun: false)
        }
        if args.count == 2 && args[1] == "--dry-run" {
            return .status(dryRun: true)
        }
        throw LrcmdError.invalidArguments
    case "doctor":
        guard args.count == 1 else { throw LrcmdError.invalidArguments }
        return .doctor
    case "restart":
        if args.count == 1 {
            return .restart(dryRun: false)
        }
        if args.count == 2 && args[1] == "--dry-run" {
            return .restart(dryRun: true)
        }
        throw LrcmdError.invalidArguments
    case "stop":
        if args.count == 1 {
            return .stop(dryRun: false)
        }
        if args.count == 2 && args[1] == "--dry-run" {
            return .stop(dryRun: true)
        }
        throw LrcmdError.invalidArguments
    default:
        throw LrcmdError.invalidArguments
    }
}

func checkConfigJSON(at path: String) -> String {
    do {
        _ = try loadConfig(path: path)
        return "ok"
    } catch let error as LrcmdError {
        return "invalid: \(error.description)"
    } catch {
        return "invalid: \(error.localizedDescription)"
    }
}

func printStatus(configPath: String, dryRun: Bool) {
    let fm = FileManager.default
    let target = launchctlServiceTarget()
    let accessible = checkAccessibilityPermission()
    let inctlPath = bundledInctlPath()
    let appPath = installedAppPath()
    let appExecutablePath = installedAppExecutablePath()
    let outputLogPath = standardOutputLogPath()
    let errorLogPath = standardErrorLogPath()
    let stateDir = stateDirectoryPath()

    print("Config:       \(configPath) (\(fm.fileExists(atPath: configPath) ? "exists" : "missing"))")
    print("LaunchAgent:  \(launchAgentPlistPath()) (\(fm.fileExists(atPath: launchAgentPlistPath()) ? "exists" : "missing"))")
    print("App:          \(appPath) (\(fm.fileExists(atPath: appPath) ? "exists" : "missing"))")
    print("App binary:   \(appExecutablePath) (\(fm.fileExists(atPath: appExecutablePath) ? "exists" : "missing"))")
    print("Binary:       \(installedBinaryPath()) (\(fm.fileExists(atPath: installedBinaryPath()) ? "exists" : "missing"))")
    print("Inctl:        \(inctlPath) (\(fm.fileExists(atPath: inctlPath) ? "exists" : "missing"))")
    print("Logs:         stdout=\(outputLogPath) (\(fm.fileExists(atPath: outputLogPath) ? "exists" : "missing")), stderr=\(errorLogPath) (\(fm.fileExists(atPath: errorLogPath) ? "exists" : "missing"))")
    print("State dir:    \(stateDir) (\(fm.fileExists(atPath: stateDir) ? "exists" : "missing"))")
    print("Accessibility:\(accessible ? " granted" : " missing")")
    if !accessible {
        print("next action: open \(installedAppPath())")
    }
    print("Check commands:")
    print("  launchctl print \(target)")
    if dryRun {
        print("No launchctl commands were run.")
        return
    }

    if !fm.fileExists(atPath: launchAgentPlistPath()) {
        print("LaunchAgent plist missing; run lrcmd setup first.")
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

func isInctlCommand(_ commandPath: String) -> Bool {
    URL(fileURLWithPath: commandPath).lastPathComponent == "inctl"
}

func hasSelectIdArguments(_ command: Config.Command) -> Bool {
    command.arguments.count == 2 &&
    command.arguments[0] == "select" &&
    !command.arguments[1].isEmpty
}

func printDoctor(configPath: String) {
    let fm = FileManager.default
    let plistPath = launchAgentPlistPath()
    let inctlPath = bundledInctlPath()
    let appPath = installedAppPath()
    let appExecutablePath = installedAppExecutablePath()
    let appInfoPlistPath = installedAppInfoPlistPath()
    let stateDir = stateDirectoryPath()
    let stdoutLogPath = standardOutputLogPath()
    let stderrLogPath = standardErrorLogPath()
    let setupLog = setupLogPath()
    var config: Config?

    print("status")
    printStatus(configPath: configPath, dryRun: true)

    if !fm.fileExists(atPath: configPath) {
        print("next action: lrcmd setup")
        print("config decode: missing")
    } else {
        let result = checkConfigJSON(at: configPath)
        print("config decode: \(result)")
        if result == "ok" {
            do {
                config = try loadConfig(path: configPath)
            } catch {
                // Should not happen because checkConfigJSON already decoded it.
            }
        } else {
            print("next action: fix JSON syntax at \(configPath)")
        }
    }

    if let config {
        let leftCommandPath = config.leftCommand.command
        let rightCommandPath = config.rightCommand.command
        print("left command executable: \(leftCommandPath) (\(fm.fileExists(atPath: leftCommandPath) ? "exists" : "missing"))")
        print("right command executable: \(rightCommandPath) (\(fm.fileExists(atPath: rightCommandPath) ? "exists" : "missing"))")

        if isInctlCommand(leftCommandPath) && !hasSelectIdArguments(config.leftCommand) {
            print("warning: left command arguments should be: select <id>")
        }
        if isInctlCommand(rightCommandPath) && !hasSelectIdArguments(config.rightCommand) {
            print("warning: right command arguments should be: select <id>")
        }
    }

    if fm.fileExists(atPath: plistPath) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: plistPath))
            var format = PropertyListSerialization.PropertyListFormat.xml
            _ = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
            if format == .xml {
                print("plist decode: ok")
            } else {
                print("plist decode: invalid (not XML)")
            }
        } catch {
            print("plist decode: invalid")
        }
    } else {
        print("launchctl plist missing: next action: lrcmd setup")
    }

    if !fm.fileExists(atPath: appPath) {
        print("app bundle missing: \(appPath)")
    }
    if !fm.fileExists(atPath: appExecutablePath) {
        print("app executable missing: \(appExecutablePath)")
    } else if !FileManager.default.isExecutableFile(atPath: appExecutablePath) {
        print("app executable not executable: \(appExecutablePath)")
    }
    if !fm.fileExists(atPath: appInfoPlistPath) {
        print("app Info.plist missing: \(appInfoPlistPath)")
    }

    if !fm.fileExists(atPath: installedBinaryPath()) {
        print("binary missing")
        print("next action: lrcmd setup")
    }

    if !fm.fileExists(atPath: stateDir) {
        print("info: state directory is missing (\(stateDir)); typically created after setup or service run")
    }
    if !fm.fileExists(atPath: stdoutLogPath) {
        print("info: stdout log missing (\(stdoutLogPath)); typically created after setup or service run")
    }
    if !fm.fileExists(atPath: stderrLogPath) {
        print("info: stderr log missing (\(stderrLogPath)); typically created after setup or service run")
    }
    if !fm.fileExists(atPath: setupLog) {
        print("info: setup log missing (\(setupLog)); typically created by setup (non-dry-run)")
    }

    if !fm.fileExists(atPath: inctlPath) {
        print("warning: inctl missing: \(inctlPath)")
    }

    if !checkAccessibilityPermission() {
        print("accessibility: missing")
        print("next action: open \(installedAppPath())")
        print("and enable it in System Settings > Privacy & Security > Accessibility")
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

func runLaunchctl(args: [String], dryRun: Bool, context: String) -> Int32 {
    print("launchctl \(args.joined(separator: " "))")
    if dryRun {
        return 0
    }

    do {
        let status = try runProcess("/bin/launchctl", args)
        if status == 0 {
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

func runRestartCommands(plistPath: String, dryRun: Bool) {
    let uid = getuid()
    let bootoutArgs = ["bootout", "gui/\(uid)", plistPath]
    let bootstrapArgs = ["bootstrap", "gui/\(uid)", plistPath]
    let kickstartArgs = ["kickstart", "-k", "gui/\(uid)/dev.ultrahope.lrcmd"]

    print("UID: \(uid)")
    print("Planned commands:")
    print("launchctl \(bootoutArgs.joined(separator: " "))")
    print("launchctl \(bootstrapArgs.joined(separator: " "))")
    print("launchctl \(kickstartArgs.joined(separator: " "))")

    if dryRun {
        print("No launchctl commands were run.")
        return
    }

    if runLaunchctl(args: bootoutArgs, dryRun: false, context: "bootout") != 0 {
        print("warning: launchctl bootout failed, continuing restart.")
    }
    if runLaunchctl(args: bootstrapArgs, dryRun: false, context: "bootstrap") != 0 {
        writeStderr("error: launchctl bootstrap failed.\n")
        exit(1)
    }
    if runLaunchctl(args: kickstartArgs, dryRun: false, context: "kickstart") != 0 {
        writeStderr("error: launchctl kickstart failed.\n")
        exit(1)
    }
}

func runStopCommands(plistPath: String, dryRun: Bool) {
    let uid = getuid()
    let args = ["bootout", "gui/\(uid)", plistPath]

    print("UID: \(uid)")
    print("Planned command:")
    print("launchctl \(args.joined(separator: " "))")

    if dryRun {
        print("No launchctl commands were run.")
        return
    }

    if runLaunchctl(args: args, dryRun: false, context: "bootout") != 0 {
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

    guard (normalized as NSString).pathComponents.last == "lrcmd" else {
        return false
    }

    return true
}

func runUninstall(autoApprove: Bool, dryRun: Bool) {
    let fm = FileManager.default
    let uid = getuid()
    let plistPath = launchAgentPlistPath()
    let configPath = defaultConfigPath()
    let installRoot = defaultInstallRoot()
    let hasPlist = fm.fileExists(atPath: plistPath)

    print("UID: \(uid)")
    print("Planned command:")
    print("launchctl bootout gui/\(uid) \(plistPath)")
    if !hasPlist {
        print("Skipping launchctl because plist is missing.")
    }
    print("Targets:")
    print("  LaunchAgent plist: \(plistPath)")
    print("  Config file:      \(configPath)")
    print("  Installed bins:   \(installRoot)")

    if autoApprove {
        print("--yes keeps config and installed binaries; remove them interactively if needed.")
    }

    if hasPlist && !dryRun {
        if runLaunchctl(args: ["bootout", "gui/\(uid)", plistPath], dryRun: false, context: "bootout") != 0 {
            print("warning: launchctl bootout failed, continuing uninstall.")
        }
    }

    var plistResult = fm.fileExists(atPath: plistPath) ? "Kept" : "Missing"
    var configResult = fm.fileExists(atPath: configPath) ? "Kept" : "Missing"
    var binariesResult = fm.fileExists(atPath: installRoot) ? "Kept" : "Missing"

    let removePlist = autoApprove ? true : confirm("Remove LaunchAgent plist? [y/N]")
    if removePlist {
        if fm.fileExists(atPath: plistPath) {
            do {
                if dryRun {
                    plistResult = "Would remove"
                } else {
                    try fm.removeItem(atPath: plistPath)
                    plistResult = "Removed"
                }
            } catch {
                writeStderr("error: failed to remove plist at \(plistPath): \(error.localizedDescription)\n")
                exit(1)
            }
        } else {
            plistResult = "Missing"
            print("Missing: \(plistPath)")
        }
    } else {
        plistResult = "Kept"
    }

    if autoApprove {
        configResult = fm.fileExists(atPath: configPath) ? "Kept" : "Missing"
    } else if confirm("Remove config file? [y/N]") {
        if fm.fileExists(atPath: configPath) {
            do {
                if dryRun {
                    configResult = "Would remove"
                } else {
                    try fm.removeItem(atPath: configPath)
                    configResult = "Removed"
                }
            } catch {
                writeStderr("error: failed to remove config at \(configPath): \(error.localizedDescription)\n")
                exit(1)
            }
        } else {
            configResult = "Missing"
            print("Missing: \(configPath)")
        }
    }

    if autoApprove {
        binariesResult = fm.fileExists(atPath: installRoot) ? "Kept" : "Missing"
    } else if confirm("Remove installed binaries? [y/N]") {
        if fm.fileExists(atPath: installRoot) {
            if isSafeInstallRootPath(installRoot) {
                do {
                    if dryRun {
                        binariesResult = "Would remove"
                    } else {
                        try fm.removeItem(atPath: installRoot)
                        binariesResult = "Removed"
                    }
                } catch {
                    writeStderr("error: failed to remove installed binaries at \(installRoot): \(error.localizedDescription)\n")
                    exit(1)
                }
            } else {
                binariesResult = "Kept"
                print("Not removing: \(installRoot) (path is too broad or unsafe)")
            }
        } else {
            binariesResult = "Missing"
            print("Missing: \(installRoot)")
        }
    }

    print("LaunchAgent plist: \(plistResult)")
    print("Config file:      \(configResult)")
    print("Installed bins:   \(binariesResult)")
    if dryRun {
        print("No launchctl commands were run.")
    }
}

func loadConfig(path: String) throws -> Config {
    let url = URL(fileURLWithPath: path)

    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    } catch let error as DecodingError {
        throw LrcmdError.configDecodeFailed(path, error)
    } catch {
        throw LrcmdError.configReadFailed(path, error)
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
        throw LrcmdError.eventTapCreationFailed
    }

    return eventTap
}

func runDaemon(configPath: String) throws {
    let state = LauncherState()
    state.config = try loadConfig(path: configPath)

    guard checkAccessibilityPermission() else {
        throw LrcmdError.accessibilityPermissionRequired
    }

    let eventTap = try createEventTap(state: state)

    guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
        throw LrcmdError.runLoopSourceCreationFailed
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
    case let .run(configPath):
        try runDaemon(configPath: configPath)
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
                writeStderr("lrcmd: failed to write accessibility status result to \(resultFile): \(error.localizedDescription)\n")
                exit(1)
            }
        }
        exit(isGranted ? 0 : 1)
    case let .setup(autoApprove, replaceExistingConfig, dryRun, noOpen, noStart, waitAccessibilitySeconds):
        runSetup(
            autoApprove: autoApprove,
            replaceExistingConfig: replaceExistingConfig,
            dryRun: dryRun,
            noOpen: noOpen,
            noStart: noStart,
            waitAccessibilitySeconds: waitAccessibilitySeconds
        )
    case let .uninstall(autoApprove, dryRun):
        runUninstall(autoApprove: autoApprove, dryRun: dryRun)
    case let .status(dryRun):
        printStatus(configPath: defaultConfigPath(), dryRun: dryRun)
    case .doctor:
        printDoctor(configPath: defaultConfigPath())
    case let .restart(dryRun):
        let plist = launchAgentPlistPath()
        if !dryRun && !FileManager.default.fileExists(atPath: plist) {
            writeStderr("error: LaunchAgent plist missing: \(plist). Run lrcmd setup first.\n")
            exit(1)
        }
        runRestartCommands(plistPath: plist, dryRun: dryRun)
    case let .stop(dryRun):
        let plist = launchAgentPlistPath()
        if !dryRun && !FileManager.default.fileExists(atPath: plist) {
            writeStderr("error: LaunchAgent plist missing: \(plist). Run lrcmd setup first.\n")
            exit(1)
        }
        runStopCommands(plistPath: plist, dryRun: dryRun)
    }
} catch let error as LrcmdError {
    if case .invalidArguments = error {
        let progname = URL(fileURLWithPath: CommandLine.arguments.first ?? "lrcmd").lastPathComponent
        writeStderr(usage(progname: progname) + "\n")
        writeStderr("lrcmd: \(error.description)\n")
        exit(64)
    }
    writeStderr("lrcmd: \(error.description)\n")
    exit(1)
} catch {
    writeStderr("lrcmd: \(error.localizedDescription)\n")
    exit(1)
}
