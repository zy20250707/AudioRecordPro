// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AudioRecordKit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "AudioRecordKit",
            targets: ["AudioRecordKit"]
        )
    ],
    targets: [
        .target(
            name: "AudioRecordKit",
            path: "Sources",
            sources: ["Core", "API", "Utils", "CAPI"],
            publicHeadersPath: "CAPI",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("ScreenCaptureKit")
            ]
        ),
        .testTarget(
            name: "AudioRecordKitTests",
            dependencies: ["AudioRecordKit"],
            path: "Tests"
        )
    ]
)

