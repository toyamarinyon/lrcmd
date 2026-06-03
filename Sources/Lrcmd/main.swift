@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

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
      \(progname)
      \(progname) --config /path/to/config.json
    """
}

func writeStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

func parseConfigPath(arguments: [String]) throws -> String {
    switch arguments.count {
    case 1:
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/lrcmd/config.json")
            .path

    case 3 where arguments[1] == "--config":
        return arguments[2]

    default:
        throw LrcmdError.invalidArguments
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

func run() throws {
    let arguments = CommandLine.arguments
    let progname = URL(fileURLWithPath: arguments.first ?? "lrcmd").lastPathComponent

    let configPath: String
    do {
        configPath = try parseConfigPath(arguments: arguments)
    } catch LrcmdError.invalidArguments {
        writeStderr(usage(progname: progname) + "\n")
        exit(64)
    }

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
    try run()
} catch let error as LrcmdError {
    writeStderr("lrcmd: \(error.description)\n")
    exit(1)
} catch {
    writeStderr("lrcmd: \(error.localizedDescription)\n")
    exit(1)
}
