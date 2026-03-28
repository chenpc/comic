// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Comic",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Comic",
            path: "Sources/Comic"
        ),
        .testTarget(
            name: "ComicTests",
            dependencies: ["ComicLib"],
            path: "Tests/ComicTests"
        ),
        .target(
            name: "ComicLib",
            path: "Sources/ComicLib",
            linkerSettings: [.linkedFramework("SwiftUI")]
        ),
    ]
)
