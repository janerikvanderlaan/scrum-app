// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "desktop-coach",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure rules and wording: no AppKit, no Accessibility API, fully unit tested.
        .target(name: "CoachCore"),
        // The menu bar app that reads the focused field and shows hints.
        .executableTarget(name: "DesktopCoach", dependencies: ["CoachCore"]),
        // Diagnostic logger: shows which focus, value, click and key events an app really reports.
        .executableTarget(name: "CoachProbe", dependencies: ["CoachCore"]),
        .testTarget(name: "CoachCoreTests", dependencies: ["CoachCore"]),
    ]
)
