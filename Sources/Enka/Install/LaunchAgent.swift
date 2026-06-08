import Foundation
import Darwin

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
