// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "lrcmd",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "lrcmd", targets: ["Lrcmd"]),
        .executable(name: "inctl", targets: ["Inctl"]),
    ],
    targets: [
        .executableTarget(
            name: "Lrcmd",
            path: "Sources/Lrcmd"
        ),
        .executableTarget(
            name: "Inctl",
            path: "Sources/Inctl"
        ),
    ]
)
