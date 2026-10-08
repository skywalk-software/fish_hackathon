// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Planetfall",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Planetfall", targets: ["Planetfall"]),
        .library(name: "PlanetfallEngine", targets: ["PlanetfallEngine"]),
    ],
    targets: [
        // Runs dfrotz and turns its text stream into game events. No UI code.
        .target(name: "PlanetfallEngine"),
        // The SwiftUI Mac app.
        .executableTarget(name: "Planetfall", dependencies: ["PlanetfallEngine"]),
        // Command-line tool for auditioning Fish Audio voices: swift run audition
        .executableTarget(name: "audition", dependencies: ["PlanetfallEngine"]),
        .testTarget(name: "PlanetfallEngineTests", dependencies: ["PlanetfallEngine"]),
    ]
)
