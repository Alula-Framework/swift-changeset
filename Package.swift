// swift-tools-version: 6.0
// Swift Changeset — semantic validation, dirty tracking, and the neutral
// ValidatedChanges handoff a driver translates into its native write.
// Zero dependencies by design: any persistence layer can consume it.
import PackageDescription
import Foundation

let package = Package(
    name: "swift-changeset",
    platforms: [
        // Driven by Regex (ValidationRule.matches), not by any consumer.
        .macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)
    ],
    products: [
        // Module named "Changesets" (swift-collections → Collections
        // convention) so it never collides with the Changeset type itself.
        .library(name: "Changesets", targets: ["Changesets"])
    ],
    dependencies: [
        // Test-only, and it stays that way: SwiftPM resolves a dependency's
        // test-target dependencies for the root package only, so an adopter of
        // Changesets still resolves nothing. Property-based testing with
        // shrinking, for the laws dirty tracking has to obey across every
        // order of edits rather than the handful written by hand.
        .package(
            url: "https://github.com/x-sheep/swift-property-based.git",
            .upToNextMinor(from: "2.0.0"))
    ],
    targets: [
        .target(
            name: "Changesets",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ChangesetsTests",
            dependencies: [
                "Changesets",
                .product(name: "PropertyBased", package: "swift-property-based"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

// Documentation tooling only. Gated behind an environment variable so that
// consumers of this package resolve zero dependencies — building the DocC
// catalog is a maintainer task, not something an adopter pays for.
//
//     SWIFT_CHANGESET_BUILD_DOCS=1 swift package generate-documentation
if ProcessInfo.processInfo.environment["SWIFT_CHANGESET_BUILD_DOCS"] != nil {
    package.dependencies.append(
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.3.0")
    )
}
