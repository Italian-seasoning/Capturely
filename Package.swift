// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Capturely",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Capturely", targets: ["Capturely"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "Capturely",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Capturely"
        ),
        .testTarget(
            name: "CapturelyTests",
            dependencies: ["Capturely"],
            path: "Tests/CapturelyTests"
        )
    ]
)
