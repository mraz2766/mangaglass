// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MangaGlass",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MangaGlass", targets: ["MangaGlass"])
    ],
    targets: [
        .executableTarget(
            name: "MangaGlass",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
