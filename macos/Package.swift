// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MQTTExplorer",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/swift-server-community/mqtt-nio.git", from: "2.13.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
    ],
    targets: [
        .executableTarget(
            name: "MQTTExplorer",
            dependencies: [
                .product(name: "MQTTNIO", package: "mqtt-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            path: "Sources/MQTTExplorer"
        ),
        .testTarget(
            name: "TopicTreeTests",
            dependencies: ["MQTTExplorer"],
            path: "Tests/TopicTreeTests"
        ),
    ]
)
