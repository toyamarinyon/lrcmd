import Foundation
import Darwin

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
