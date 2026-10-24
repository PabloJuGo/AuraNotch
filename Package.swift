// swift-tools-version:6.0
import PackageDescription

// Un único manifiesto con targets en Packages/<Nombre>/Sources/<Nombre>.
func lib(_ name: String, _ deps: [String] = []) -> Target {
    .target(name: name, dependencies: deps.map { .byName(name: $0) }, path: "Packages/\(name)/Sources/\(name)")
}

let package = Package(
    name: "AuraNotch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AuraNotch", targets: ["AuraNotch"])],
    targets: [
        lib("AuraCore"),
        lib("AuraDesignSystem", ["AuraCore"]),
        lib("AuraNotchSurface", ["AuraCore", "AuraDesignSystem"]),
        lib("AuraShelf", ["AuraCore", "AuraDesignSystem"]),
        lib("AuraPreferences", ["AuraCore", "AuraDesignSystem"]),
        lib("AuraMedia", ["AuraCore", "AuraDesignSystem"]),
        lib("AuraWidgets", ["AuraCore", "AuraDesignSystem"]),
        lib("AuraCalendar", ["AuraCore", "AuraDesignSystem"]),
        lib("AuraClipboard", ["AuraCore", "AuraDesignSystem"]),
        lib("AuraAlerts", ["AuraCore", "AuraDesignSystem"]),
        lib("AuraHome", ["AuraCore", "AuraDesignSystem", "AuraMedia", "AuraWidgets", "AuraCalendar", "AuraShelf", "AuraPreferences", "AuraClipboard"]),
        .executableTarget(name: "AuraNotch",
                          dependencies: ["AuraCore", "AuraDesignSystem", "AuraNotchSurface", "AuraShelf", "AuraPreferences", "AuraMedia", "AuraWidgets", "AuraCalendar", "AuraHome", "AuraClipboard", "AuraAlerts"], path: "App"),
        // Suites compartidas por el runner (`swift run AuraSelfTests`) y por `swift test`. Ver ADR 0001 y 0004.
        .target(name: "AuraSuites",
                dependencies: ["AuraCore", "AuraDesignSystem", "AuraNotchSurface", "AuraShelf", "AuraPreferences", "AuraMedia", "AuraWidgets", "AuraCalendar", "AuraHome", "AuraClipboard", "AuraAlerts"], path: "Tests/Suites"),
        .executableTarget(name: "AuraSelfTests", dependencies: ["AuraCore", "AuraSuites"], path: "Tests/SelfTests"),
        .testTarget(name: "AuraTests", dependencies: ["AuraSelfTests", "AuraSuites"], path: "Tests/AuraTests"),
    ]
)
