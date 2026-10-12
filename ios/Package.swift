// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "GrademaxxingNative",
  platforms: [.iOS(.v17), .macOS(.v14)],
  products: [
    .library(name: "GrademaxxingCore", targets: ["GrademaxxingCore"]),
    .executable(name: "GrademaxxingPreview", targets: ["GrademaxxingPreview"]),
    .executable(name: "GrademaxxingChecks", targets: ["GrademaxxingChecks"]),
  ],
  targets: [
    .target(name: "GrademaxxingCore"),
    .executableTarget(
      name: "GrademaxxingPreview",
      dependencies: ["GrademaxxingCore"],
      path: "App",
      exclude: ["Assets.xcassets", "Info.plist", "PrivacyInfo.xcprivacy"]
    ),
    // This executable test suite also runs on a Mac with only Command Line Tools,
    // which does not ship XCTest or Swift Testing. No network or Keychain test data.
    .executableTarget(
      name: "GrademaxxingChecks", dependencies: ["GrademaxxingCore"],
      path: "Tests/GrademaxxingCoreTests", resources: [.process("Fixtures")]),
  ]
)
