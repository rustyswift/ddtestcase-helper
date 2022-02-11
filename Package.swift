// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DDTestCaseHelper",
    dependencies: [
        .package(name: "SwiftSyntax", url: "https://github.com/apple/swift-syntax.git", .exact("0.50500.0")),
    ],
    targets: [
        .target(name: "Core", dependencies: ["SwiftSyntax"]),
        .executableTarget(name: "DDTestcaseHelper", dependencies: ["Core"]),
    ]
)
