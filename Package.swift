// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MultiAI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MultiAICore",
            targets: ["MultiAICore"]
        ),
        .executable(
            name: "MultiAI",
            targets: ["MultiAI"]
        )
    ],
    targets: [
        .target(
            name: "MultiAICore",
            path: "Sources/MultiAICore"
        ),
        .executableTarget(
            name: "MultiAI",
            dependencies: ["MultiAICore"],
            path: "Sources/MultiAI"
        ),
        .testTarget(
            name: "MultiAITests",
            dependencies: ["MultiAICore"],
            path: "Tests/MultiAITests"
        )
    ]
)
