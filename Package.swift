// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Refresher",
    platforms: [.iOS(.v16)],
    products: [.library(name: "Refresher", targets: ["Refresher"])],
    targets: [
        .target(name: "Refresher"),
        .testTarget(name: "RefresherTests", dependencies: ["Refresher"]),
    ],
    swiftLanguageModes: [.v5]
)
