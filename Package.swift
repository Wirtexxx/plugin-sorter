// swift-tools-version:6.0
// Swift package for the tests only: the app itself is built by build.sh.
// PluginSorterCore is the UI-free part of App/ — parsers, inventory, checks and the script runner.
import PackageDescription

let package = Package(
    name: "PluginSorter",
    platforms: [.macOS(.v11)],
    targets: [
        .target(
            name: "PluginSorterCore",
            path: "App",
            sources: [
                "FLDatabase.swift",
                "PluginInventory.swift",
                "PluginChecker.swift",
                "Sorter.swift",
                "Shell.swift",
                "PluginFixes.swift",
                "FLFavorites.swift",
                "DiskUsage.swift",
                "FLCategories.swift",
                "CheckCache.swift",
                "PluginCatalog.swift",
                "FLStudio.swift",
                "ScrollGlide.swift",
                "CardPictures.swift",
                "Cleanup.swift",
                "Uninstall.swift",
                "CatalogExport.swift",
                "SupportDraft.swift",
                "KnownPlugins.swift",
                "UserLabels.swift",
                "LicenseVault.swift",
            ]
        ),
        .testTarget(
            name: "PluginSorterCoreTests",
            dependencies: ["PluginSorterCore"],
            path: "Tests/PluginSorterCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
