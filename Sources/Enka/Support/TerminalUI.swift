import Foundation
import Darwin

func writeStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

private let isTTY = isatty(STDOUT_FILENO) == 1

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
