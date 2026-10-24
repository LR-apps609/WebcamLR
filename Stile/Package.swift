// swift-tools-version:5.9
import PackageDescription

// Grafica condivisa da iPhone e Mac: colori, caratteri e componenti della bozza grafica.
// Testi in italiano (lingua di partenza) con la traduzione inglese in Resources/Localizable.xcstrings (P22).
let package = Package(
    name: "Stile",
    defaultLocalization: "it",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "Stile", targets: ["Stile"])
    ],
    targets: [
        .target(name: "Stile", resources: [.copy("Caratteri"), .process("Resources")])
    ]
)
