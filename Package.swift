// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "enka",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "enka", targets: ["Enka"]),
    ],
    targets: [
        .executableTarget(
            name: "Enka",
            path: "Sources/Enka"
        ),
    ]
)
