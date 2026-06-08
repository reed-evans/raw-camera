// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CameraCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CameraCore", targets: ["CameraCore"])
    ],
    targets: [
        .target(
            name: "CameraCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "CameraCoreTests",
            dependencies: ["CameraCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
