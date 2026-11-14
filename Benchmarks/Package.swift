// swift-tools-version: 6.1
import PackageDescription

/// Where the Swift Testing runtime is. LLMCheck links Testing for `expectNone`, and only a test runner puts it on the
/// search path, so the benchmark executable is told where it is: in the active swift.org toolchain (first in `PATH`
/// under swiftly) and in Xcode's macOS platform (under `xcrun`).
let testingRuntimePaths: [String] = {
  let path = Context.environment["PATH"] ?? ""
  let toolchain = path.split(separator: ":").first { $0.hasSuffix(".xctoolchain/usr/bin") }
  let developer = Context.environment["DEVELOPER_DIR"] ?? "/Applications/Xcode.app/Contents/Developer"
  return (toolchain.map { ["\($0)/../lib/swift/macosx/testing"] } ?? []) + [
    "\(developer)/Platforms/MacOSX.platform/Developer/Library/Frameworks",
    "\(developer)/Platforms/MacOSX.platform/Developer/usr/lib",
  ]
}()

// swift-llm-check's benchmarks, on ordo-one/benchmark (https://www.swift.org/blog/benchmarks/). A separate
// package, so the library never depends on it. It builds against the working copy (`..`), so a change
// is measured before it is merged. Run from the repository root: `swift package --package-path Benchmarks benchmark`.
let package = Package(
  name: "Benchmarks",
  platforms: [.macOS(.v15)],
  dependencies: [
    .package(name: "swift-llm-check", path: ".."),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.0"..<"700.0.0"),
    .package(url: "https://github.com/ordo-one/benchmark.git", from: "1.38.0"),
  ],
  targets: [
    .executableTarget(
      name: "LLMCheckBenchmarks",
      dependencies: [
        .product(name: "Benchmark", package: "benchmark"),
        .product(name: "LLMCheck", package: "swift-llm-check"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
      ],
      path: "Benchmarks/LLMCheckBenchmarks",
      linkerSettings: [.unsafeFlags(testingRuntimePaths.flatMap { ["-Xlinker", "-rpath", "-Xlinker", $0] })],
      plugins: [
        .plugin(name: "BenchmarkPlugin", package: "benchmark")
      ]
    ),
    // Reads two `benchmark --format markdown` outputs and prints each benchmark's p50 before and after.
    .executableTarget(name: "p50", path: "Tools/P50"),
    // Reads an exported Time Profiler table and prints the hottest functions (scripts/profile.sh).
    .executableTarget(name: "hotspots", path: "Tools/Hotspots"),
  ]
)
