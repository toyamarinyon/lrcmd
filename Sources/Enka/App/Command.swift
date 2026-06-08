import Foundation

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

enum EnkaCommand {
    case run
    case status
    case accessibilityStatus(resultFile: String?)
    case install(
        noOpen: Bool,
        noStart: Bool,
        waitAccessibilitySeconds: Int
    )
    case uninstall
    case restart
    case stop
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

        return .install(
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
