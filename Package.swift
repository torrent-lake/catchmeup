// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "AllTimeRecorded",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "AllTimeRecorded", targets: ["AllTimeRecorded"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "AllTimeRecorded"
        ),
        .testTarget(
            name: "AllTimeRecordedTests",
            dependencies: [
                "AllTimeRecorded",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
