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
        .target(name: "NeedlbarCore", dependencies: ["CNeedlbar", "NeedlbarWidgetSupport"]),
        .target(name: "NeedlbarApp", dependencies: ["NeedlbarCore", "CNeedlbar"], path: "Sources/Needlbar"),
        .target(name: "NeedlbarWidgetSupport"),
        .executableTarget(name: "Needlbar", dependencies: ["NeedlbarApp"], path: "Sources/NeedlbarMain"),
        .testTarget(name: "NeedlbarCoreTests", dependencies: ["NeedlbarCore", "NeedlbarWidgetSupport"]),
        .testTarget(name: "NeedlbarTests", dependencies: ["NeedlbarApp"]),
        .testTarget(name: "NeedlbarWidgetSupportTests", dependencies: ["NeedlbarWidgetSupport"]),
    ]
)
