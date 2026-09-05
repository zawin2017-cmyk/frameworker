// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Frameworker",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Frameworker",
            path: "Sources/Frameworker"
        ),
        .testTarget(
            name: "FrameworkerTests",
            dependencies: ["Frameworker"],
            path: "Tests/FrameworkerTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
