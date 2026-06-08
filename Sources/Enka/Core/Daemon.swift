@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

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
