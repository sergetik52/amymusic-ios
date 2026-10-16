// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AmyMusicIOS26",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "AmyMusicCore",
            targets: ["AmyMusicCore"]
        )
    ],
    targets: [
        .target(
            name: "AmyMusicCore",
            path: "AmyMusic",
            exclude: ["Info.plist", "AmyMusicApp.swift"]
        )
    ]
)
