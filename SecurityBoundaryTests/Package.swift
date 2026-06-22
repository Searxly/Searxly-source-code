// swift-tools-version:5.9
//
// Known-answer tests for the security-boundary logic (dApp approval previews + prompt-injection guard).
// mirror/ sources are symlinks to the real files in ../Searxly, so the tests can't drift.
//
import PackageDescription

let package = Package(
    name: "SecurityBoundaryTests",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Pinned to the same revision the app ships (app Package.resolved, tag 0.3.0).
        .package(url: "https://github.com/Myrhex-x/bulwark",
                 revision: "fbb30671826a77c2d4624d9934142e5892025e63"),
    ],
    targets: [
        .executableTarget(
            name: "SecurityBoundaryTests",
            dependencies: [.product(name: "Bulwark", package: "bulwark")],
            path: "Sources/SecurityBoundaryTests"
        ),
    ]
)
