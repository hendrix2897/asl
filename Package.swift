// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "asl",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "asl",
            targets: ["ASL"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "ASL",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources"
        )
    ]
)
