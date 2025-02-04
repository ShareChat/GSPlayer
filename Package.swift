// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GSPlayer",
    platforms: [.iOS(.v11)],
    products: [
        .library(
            name: "GSPlayer",
            targets: ["GSPlayer"]
        ),
    ],
    targets: [
        .target(
            name: "GSPlayer",
            path: "GSPlayer/Classes"
        ),
    ]
)
