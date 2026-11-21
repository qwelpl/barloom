// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Barloom",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Barloom", path: "Sources/Barloom")
    ]
)
