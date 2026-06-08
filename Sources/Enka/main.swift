import Foundation
import Darwin

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
    case let .install(noOpen, noStart, waitAccessibilitySeconds):
        runInstall(
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
