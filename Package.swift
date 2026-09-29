// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Postgrace",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Postgrace", targets: ["Postgrace"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.9.0"),
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2")
    ],
    targets: [
        .executableTarget(
            name: "Postgrace",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "KeychainAccess", package: "KeychainAccess")
            ],
            path: "Sources/Postgrace"
        )
    ]
)
