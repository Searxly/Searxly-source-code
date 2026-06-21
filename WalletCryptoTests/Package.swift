// swift-tools-version:5.9
//
// Standalone known-answer tests for the Searxly wallet crypto core.
//
// The `crypto/` sources are SYMLINKS to the real files in ../Searxly/Wallet, so these tests always
// run against production code (they can never drift). Run with:  swift run  (from this directory).
//
import PackageDescription

let package = Package(
    name: "WalletCryptoTests",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", exact: "0.23.2"),
    ],
    targets: [
        .executableTarget(
            name: "WalletCryptoTests",
            dependencies: [
                .product(name: "P256K", package: "secp256k1.swift"),
                .product(name: "libsecp256k1", package: "secp256k1.swift"),
            ],
            path: "Sources/WalletCryptoTests"
        ),
    ]
)
