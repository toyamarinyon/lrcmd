import Carbon
import Foundation

struct InputSource {
    let source: TISInputSource
    let id: String
    let name: String
}

enum InctlError: Error {
    case unavailableProperty
    case currentSourceUnavailable
}

func usage(progname: String) -> String {
    """
    Usage:
      \(progname) list
      \(progname) current
      \(progname) select <inputSourceID>
    """
}

func writeStderr(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
}

func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
    guard let rawValue = TISGetInputSourceProperty(source, key) else {
        return nil
    }

    let unmanaged = Unmanaged<CFTypeRef>.fromOpaque(rawValue)
    let value = unmanaged.takeUnretainedValue()
    return value as? String
}

func availableInputSources() throws -> [InputSource] {
    let sourceList = TISCreateInputSourceList(nil, false).takeRetainedValue()
    let sources = sourceList as! [TISInputSource]

    return try sources.map { source in
        guard
            let id = stringProperty(source, key: kTISPropertyInputSourceID),
            let name = stringProperty(source, key: kTISPropertyLocalizedName)
        else {
            throw InctlError.unavailableProperty
        }

        return InputSource(source: source, id: id, name: name)
    }
}

func currentInputSource() throws -> InputSource {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
        throw InctlError.currentSourceUnavailable
    }

    guard
        let id = stringProperty(source, key: kTISPropertyInputSourceID),
        let name = stringProperty(source, key: kTISPropertyLocalizedName)
    else {
        throw InctlError.unavailableProperty
    }

    return InputSource(source: source, id: id, name: name)
}

func printSource(_ inputSource: InputSource) {
    print("\(inputSource.id)\t\(inputSource.name)")
}

func run() throws -> Int32 {
    let args = CommandLine.arguments
    let progname = URL(fileURLWithPath: args.first ?? "inctl").lastPathComponent

    guard args.count >= 2 else {
        writeStderr(usage(progname: progname) + "\n")
        return 64
    }

    switch args[1] {
    case "list":
        guard args.count == 2 else {
            writeStderr(usage(progname: progname) + "\n")
            return 64
        }

        for source in try availableInputSources() {
            printSource(source)
        }
        return 0

    case "current":
        guard args.count == 2 else {
            writeStderr(usage(progname: progname) + "\n")
            return 64
        }

        printSource(try currentInputSource())
        return 0

    case "select":
        guard args.count == 3 else {
            writeStderr(usage(progname: progname) + "\n")
            return 64
        }

        let requestedID = args[2]
        guard let selected = try availableInputSources().first(where: { $0.id == requestedID }) else {
            writeStderr("inctl: unknown input source ID '\(requestedID)'\n")
            return 1
        }

        let status = TISSelectInputSource(selected.source)
        guard status == noErr else {
            writeStderr("inctl: failed to select '\(requestedID)' (OSStatus \(status))\n")
            return 1
        }

        return 0

    default:
        writeStderr(usage(progname: progname) + "\n")
        return 64
    }
}

do {
    exit(try run())
} catch {
    writeStderr("inctl: \(error)\n")
    exit(1)
}
