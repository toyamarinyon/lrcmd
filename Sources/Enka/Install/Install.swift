import Foundation
import Darwin

func printInstallSummary(plistPath: String) {
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

func runInstall(
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
    printInstallSummary(plistPath: plistPath)
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

        do {
            try runOpenEnkaApp(logToSetup: logToSetup)
        } catch {
            print("warning: failed to run open: \(error.localizedDescription)")
            print("Please run manually:")
            print("  open \(installedAppPath())")
            logToSetup("\(setupLogPrefix()) [setup] open command failed; cannot wait for permission")
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
