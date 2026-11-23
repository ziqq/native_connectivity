// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "native_connectivity",
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [.library(name: "native-connectivity", targets: ["native_connectivity"])],
    dependencies: [.package(name: "FlutterFramework", path: "../FlutterFramework")],
    targets: [
        .target(
            name: "native_connectivity",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
        )
    ]
)
