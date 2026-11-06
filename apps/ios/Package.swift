// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NFCProbeCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "NFCProbeCore", targets: ["NFCProbeCore"])],
    targets: [
        .target(name: "NFCProbeCore", path: "Sources/NFCProbeCore"),
        .testTarget(name: "NFCProbeCoreTests", dependencies: ["NFCProbeCore"], path: "Tests")
    ]
)
