// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TaskWatch",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "TaskWatch",
            path: "Sources/TaskWatch"
        )
    ]
)
