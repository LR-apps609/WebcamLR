// swift-tools-version:5.9
import PackageDescription

// Grafica condivisa da iPhone e Mac: colori, caratteri e componenti della bozza grafica.
let package = Package(
    name: "Stile",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Stile", targets: ["Stile"])
    ],
    targets: [
        .target(name: "Stile", resources: [.copy("Caratteri")])
    ]
)
