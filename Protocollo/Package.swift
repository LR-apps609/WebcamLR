// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WebcamLRProtocollo",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "WebcamLRProtocollo", targets: ["WebcamLRProtocollo"])
    ],
    targets: [
        .target(name: "WebcamLRProtocollo"),
        .testTarget(name: "WebcamLRProtocolloTests", dependencies: ["WebcamLRProtocollo"])
    ]
)
