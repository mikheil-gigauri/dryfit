// swift-tools-version: 6.2
import PackageDescription

/// The dryfit menu bar app (ADR 0010, ADR 0013): a pure client of the daemon's API.
let package = Package(
  name: "DryfitMenuBar",
  platforms: [.macOS(.v26)],
  products: [
    .executable(name: "Dryfit", targets: ["Dryfit"])
  ],
  dependencies: [
    // Updates the installed app from the appcast each release publishes (ADR 0010, amendment).
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
  ],
  targets: [
    /// API models, the HTTP and event-stream client, and finding and starting the daemon. No UI.
    .target(name: "DryfitAPI"),
    /// The view model and views.
    .target(
      name: "DryfitMenu",
      dependencies: ["DryfitAPI"],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    /// The app itself: scenes, the daemon connection and Sparkle. Only this target links Sparkle.
    .executableTarget(
      name: "Dryfit",
      dependencies: ["DryfitMenu", .product(name: "Sparkle", package: "Sparkle")],
      swiftSettings: [.defaultIsolation(MainActor.self)],
      // bundle.sh puts Sparkle.framework in Dryfit.app/Contents/Frameworks.
      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
    ),
    .testTarget(name: "DryfitAPITests", dependencies: ["DryfitAPI"]),
    .testTarget(name: "DryfitMenuTests", dependencies: ["DryfitMenu"]),
  ]
)
