// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DBOtterDependencies",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "DBOtterDependencies", targets: ["DBOtterDependencies"])
    ],
    dependencies: [
        .package(url: "https://github.com/simonbs/Runestone.git", from: "0.5.2"),
        .package(url: "https://github.com/simonbs/TreeSitterLanguages.git", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "DBOtterDependencies",
            dependencies: [
                .product(name: "Runestone", package: "Runestone"),
                .product(name: "TreeSitterLanguagesRunestone", package: "TreeSitterLanguages")
            ]
        )
    ]
)