// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Needlbar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Needlbar", targets: ["Needlbar"]),
        .library(name: "NeedlbarCore", targets: ["NeedlbarCore"]),
        .library(name: "NeedlbarApp", targets: ["NeedlbarApp"]),
    ],
    targets: [
        .target(
            name: "CNeedlbar",
            path: "Sources/CNeedlbar",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags(
                    ["-L", "target/release", "-lneedlbar_bridge"],
                    .when(platforms: [.macOS])
                )
            ]
        ),
        .target(name: "NeedlbarCore", dependencies: ["CNeedlbar"]),
        .target(name: "NeedlbarApp", dependencies: ["NeedlbarCore"], path: "Sources/Needlbar"),
        .executableTarget(name: "Needlbar", dependencies: ["NeedlbarApp"], path: "Sources/NeedlbarMain"),
        .testTarget(name: "NeedlbarCoreTests", dependencies: ["NeedlbarCore"]),
        .testTarget(name: "NeedlbarTests", dependencies: ["NeedlbarApp"]),
    ]
)
