import Benchmark
import Foundation
import LLMCheck
import SwiftSyntax

/// The code the benchmarks read: swift-syntax's own `Sources`, which this package depends on, so it is always checked
/// out. Over 300 files and 6 MB of real Swift, from small protocols to generated files of 30,000 lines.
enum Corpus {
  /// `Benchmarks/.build/checkouts/swift-syntax`.
  static let root: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent(".build/checkouts/swift-syntax")

  /// Every Swift file under `Sources`, relative to ``root`` and sorted, with its text.
  static let files: [(path: String, source: String)] = {
    let sources = root.appendingPathComponent("Sources")
    let enumerator = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
    var files: [(String, String)] = []
    for case let url as URL in enumerator where url.pathExtension == "swift" {
      let path = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
      files.append((path, try! String(contentsOf: url, encoding: .utf8)))
    }
    precondition(files.count > 200, "swift-syntax is not checked out under \(root.path)")
    return files.sorted { $0.0 < $1.0 }
  }()

  /// The files, parsed now: a scope no query has read yet, as a rule finds it the first time.
  static func freshScope() -> Scope {
    Scope(files: files.map { SourceFile(path: $0.path, source: $0.source) })
  }

  /// A codebase this process has never read: the corpus behind a new symbolic link, since the caches are keyed by
  /// root path.
  static func freshCodebase() -> Codebase {
    let link = FileManager.default.temporaryDirectory.appendingPathComponent("llm-check-bench-\(UUID().uuidString)")
    try! FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
    return try! Codebase(root: link, configuration: Configuration(excludes: ["Tests", "CodeGeneration", "Examples"]))
  }
}

/// A query timed on a scope that is parsed beforehand, outside the measurement: the first query on each file walks
/// its tree, as each rule does once per process.
func measureOnFreshScope(_ benchmark: Benchmark, _ query: (Scope) -> some Any) {
  for _ in benchmark.scaledIterations {
    let scope = Corpus.freshScope()
    benchmark.startMeasurement()
    blackHole(query(scope))
    benchmark.stopMeasurement()
  }
}

let benchmarks: @Sendable () -> Void = {
  Benchmark.defaultConfiguration = .init(
    metrics: [.wallClock, .cpuTotal, .mallocCountTotal, .peakMemoryResident, .retainCount],
    timeUnits: .milliseconds,
    units: [.mallocCountTotal: .count, .retainCount: .count],
    maxDuration: .seconds(5),
    maxIterations: 20
  )
  _ = Corpus.files

  // MARK: Parsing

  Benchmark(
    "Parse, swift-syntax",
    configuration: .init(metrics: Benchmark.defaultConfiguration.metrics + [.peakMemoryResidentDelta])
  ) { _ in
    blackHole(Corpus.files.map { SourceFile(path: $0.path, source: $0.source) })
  }

  Benchmark("Snippet of every 100th line, swift-syntax") { benchmark in
    let files = Corpus.files.map { SourceFile(path: $0.path, source: $0.source) }
    benchmark.startMeasurement()
    for file in files {
      for line in stride(from: 1, to: file.source.utf8.count / 40, by: 100) { blackHole(file.line(line)) }
    }
  }

  // MARK: Queries, first run on each file

  Benchmark("Declarations, swift-syntax") { benchmark in
    measureOnFreshScope(benchmark) { $0.declarations.count }
  }

  Benchmark("Structs with an attribute, swift-syntax") { benchmark in
    measureOnFreshScope(benchmark) { $0.structs.withAttribute("_spi").count + $0.enums.count + $0.classes.count }
  }

  Benchmark("Nodes of a type, swift-syntax") { benchmark in
    measureOnFreshScope(benchmark) { $0.nodes(of: ForceUnwrapExprSyntax.self).count }
  }

  Benchmark("Calls named, swift-syntax") { benchmark in
    measureOnFreshScope(benchmark) { $0.calls(named: "precondition", "fatalError", "print").count }
  }

  Benchmark("References, swift-syntax") { benchmark in
    measureOnFreshScope(benchmark) { $0.references(to: "TokenSyntax", "SyntaxArena", "FileManager").count }
  }

  Benchmark("Imports, swift-syntax") { benchmark in
    measureOnFreshScope(benchmark) { $0.imports(of: "Foundation", "SwiftSyntax").count }
  }

  Benchmark("Attached comments of every function, swift-syntax") { benchmark in
    measureOnFreshScope(benchmark) { $0.functions.reduce(0) { $0 + $1.syntax.attachedComments.count } }
  }

  // MARK: Queries, cached

  Benchmark("Calls named, cached, swift-syntax") { benchmark in
    let scope = Corpus.freshScope()
    blackHole(scope.calls(named: "precondition"))
    benchmark.startMeasurement()
    for _ in benchmark.scaledIterations { blackHole(scope.calls(named: "precondition", "fatalError", "print")) }
  }

  Benchmark("Containing, swift-syntax") { benchmark in
    let scope = Corpus.freshScope()
    benchmark.startMeasurement()
    for _ in benchmark.scaledIterations { blackHole(scope.containing("@Reducer", "fatalError(").relativePaths) }
  }

  // MARK: A codebase, as a test run sees it

  Benchmark("Codebase, list files, cold") { benchmark in
    for _ in benchmark.scaledIterations {
      let codebase = Corpus.freshCodebase()
      benchmark.startMeasurement()
      blackHole(codebase.allCode.relativePaths)
      benchmark.stopMeasurement()
    }
  }

  // Five rules like the README's, on a codebase no rule has read: listing, text filtering, parsing what the filters
  // let through, and the queries.
  Benchmark("Five rules, cold codebase") { benchmark in
    for _ in benchmark.scaledIterations {
      let codebase = Corpus.freshCodebase()
      benchmark.startMeasurement()
      let sources = codebase.productionCode.in("/Sources")
      let rule = Rule(
        id: "bench", title: "Bench.", category: RuleCategory("bench", description: "Bench."), rationale: "Bench.",
        howToFix: "Bench.")
      blackHole(rule.check(sources.calls(named: "print").filter { $0.node.receiver == nil }))
      blackHole(rule.check(sources.imports(of: "Foundation")))
      blackHole(rule.check(sources.references(to: "FileManager", "URLSession")))
      blackHole(rule.check(sources.containing("@unchecked").nodes(of: AttributeSyntax.self)))
      blackHole(rule.check(sources.structs.withModifier("public").filter { !$0.inherits(from: "Sendable") }))
      benchmark.stopMeasurement()
    }
  }
}
