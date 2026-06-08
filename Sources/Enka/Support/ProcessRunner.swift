import Foundation

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
