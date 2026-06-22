// swift-tools-version:5.9
//
// Standalone known-answer tests for Searxly's SECURITY BOUNDARY — the pure decision/display logic
// that stands between an untrusted website and the user:
//
//   • TypedDataPreview / TxPreview  — what the dApp approval sheet shows for an EIP-712 signature or
//                                     an eth_sendTransaction. A bug here can make a drain look benign.
//   • PageContentGuard              — prompt-injection sanitization for "summarize this page".
//
// The `mirror/` sources are SYMLINKS to the real files in ../Searxly, so these tests always run
// against production code and can never drift. Run with:  swift run  (from this directory),
// or via ../scripts/run-security-boundary-tests.sh.
//
import PackageDescription

let package = Package(
    name: "SecurityBoundaryTests",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Pinned to the EXACT revision the app ships (see the app's Package.resolved — tag 0.3.0),
        // so the injection tests exercise the same Bulwark the user runs. A revision pin also avoids
        // the version→revision fingerprint conflict when a tag is later re-pointed upstream.
        .package(url: "https://github.com/Myrhex-x/bulwark",
                 revision: "fbb30671826a77c2d4624d9934142e5892025e63"),
    ],
    targets: [
        .executableTarget(
            name: "SecurityBoundaryTests",
            dependencies: [
                .product(name: "Bulwark", package: "bulwark"),
            ],
            path: "Sources/SecurityBoundaryTests"
        ),
    ]
)
