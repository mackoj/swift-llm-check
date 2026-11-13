// swift-tools-version: 6.0
import PackageDescription

// swift-llm-check's own rules, written with swift-llm-check: the library checks itself. Test-only, so the library's
// manifest never references it. It depends on the working copy (`..`), so a change to the library is checked by the
// rules it changes. Run from the repository root: `swift test --package-path Architecture`.
let package = Package(
  name: "Architecture",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(name: "swift-llm-check", path: ".."),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.0"..<"700.0.0"),
  ],
  targets: [
    .testTarget(
      name: "ArchitectureTests",
      dependencies: [
        .product(name: "LLMCheck", package: "swift-llm-check"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ]
    )
  ]
)
