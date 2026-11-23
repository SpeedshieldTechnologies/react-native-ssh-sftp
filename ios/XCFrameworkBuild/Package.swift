// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RNSSHClientDeps",
    platforms: [
        // Bumped from .v17: the Citadel/NIOTransportServices bridge needs SE-0417 task executor
        // preference (`withTaskExecutorPreference`), which requires the iOS 18 Concurrency
        // runtime - see the comment on EventLoopTaskExecutor in RNSSHClientDeps.swift.
        // `.v18` needs PackageDescription 6.0 (this package pins swift-tools-version 5.9 for
        // other reasons), so spell it as a version string instead.
        .iOS("18.0"),
    ],
    products: [
        .library(name: "RNSSHClientDeps", type: .static, targets: ["RNSSHClientDeps"])
    ],
    dependencies: [
        // Our fork: 0.12.1 plus SSHClientSettings.loginTimeout (upstream fixes it at 10 s, too short for cameras
        // whose dropbear spends 10 s on a reverse DNS lookup before its version line).
        .package(url: "https://github.com/SpeedshieldTechnologies/Citadel.git", exact: "0.12.1-speedshield.1"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4" ..< "0.4.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.12.3"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.11.0"),
    ],
    targets: [
        .target(
            name: "RNSSHClientDeps",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
            ],
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution", "-emit-module-interface"])
            ]
        )
    ]
)
