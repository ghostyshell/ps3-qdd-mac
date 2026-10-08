// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Command Line Tools ship Testing.framework but do not tell the Swift driver to load
// its macro plugin, so `swift test` fails with "plugin for module 'TestingMacros' not
// found". Pointing the driver at the plugin by hand fixes it. Under a full Xcode install
// the plugin lives elsewhere and is wired up automatically, so only add the flag when the
// Command Line Tools copy is actually there.
let cltTestingPlugin =
    "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let testSwiftSettings: [SwiftSetting] =
    FileManager.default.fileExists(atPath: cltTestingPlugin)
    ? [.unsafeFlags(["-load-plugin-library", cltTestingPlugin])]
    : []

let package = Package(
    name: "PS3QDD",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: no UI, no window server, so the tests can run headless.
        .target(name: "PS3QDDCore"),
        .executableTarget(name: "PS3QDD", dependencies: ["PS3QDDCore"]),
        .testTarget(
            name: "PS3QDDCoreTests",
            dependencies: ["PS3QDDCore"],
            swiftSettings: testSwiftSettings
        ),
    ]
)
