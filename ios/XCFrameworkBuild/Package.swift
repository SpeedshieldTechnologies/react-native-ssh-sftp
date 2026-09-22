// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RNSSHClientDeps",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "RNSSHClientDeps", type: .static, targets: ["RNSSHClientDeps"])
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.12.0"),
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
