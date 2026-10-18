// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShiftDrop",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ShiftDrop", targets: ["ShiftDrop"])],
    targets: [
        .executableTarget(name: "ShiftDrop"),
        .testTarget(name: "ShiftDropTests", dependencies: ["ShiftDrop"])
    ]
)
