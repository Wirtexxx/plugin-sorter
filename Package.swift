// swift-tools-version:6.0
// Swift package for the tests only: the app itself is built by build.sh.
// PluginSorterCore is everything in App/ but the @main entry point, which the tests must never start.
import PackageDescription

let package = Package(
    name: "PluginSorter",
    platforms: [.macOS(.v11)],
    targets: [
        .target(
            name: "PluginSorterCore",
            path: "App",
            exclude: ["PluginSorterApp.swift"],
        ),
        .testTarget(
            name: "PluginSorterCoreTests",
            dependencies: ["PluginSorterCore"],
            path: "Tests/PluginSorterCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
