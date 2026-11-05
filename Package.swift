// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "swift-llm-check",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "LLMCheck", targets: ["LLMCheck"])
  ],
  dependencies: [
    // See "swift-syntax versions" in README.md for why the range is this wide.
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.0"..<"700.0.0")
  ],
  targets: [
    .target(
      name: "LLMCheck",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "LLMCheckTests",
      dependencies: ["LLMCheck", .product(name: "SwiftSyntax", package: "swift-syntax")],
      exclude: ["Fixtures"]
    ),
  ]
)
