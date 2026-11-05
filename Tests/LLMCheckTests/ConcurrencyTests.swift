import Foundation
import Testing

@testable import LLMCheck

/// Swift Testing runs suites and tests in parallel. Harmonize 2.0.0-beta.2 deadlocks when two suites warm its parse
/// cache at once; these suites do exactly that, from many tasks, on a codebase none of the other suites read.
enum CacheStress {
  /// A fresh codebase of 40 files per process, so the first reads really parse.
  static let codebase: Codebase = {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("llm-check-stress-\(UUID().uuidString)")
    for index in 0..<40 {
      let url = root.appendingPathComponent("Sources/Module\(index % 4)/File\(index).swift")
      try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      let body = (0..<50).map { "  func f\($0)() { print(\($0)) }" }.joined(separator: "\n")
      try! "struct Type\(index) {\n\(body)\n}\n".write(to: url, atomically: true, encoding: .utf8)
    }
    return try! Codebase(root: root, configuration: Configuration())
  }()

  static func hammer() async -> [[ObjectIdentifier]] {
    await withTaskGroup(of: [ObjectIdentifier].self) { group in
      for task in 0..<64 {
        group.addTask {
          let scope =
            task.isMultiple(of: 2) ? codebase.allCode : codebase.productionCode.in("Sources/Module\(task % 4)")
          _ = scope.calls(named: "print").count
          return codebase.allCode.files.map(ObjectIdentifier.init)
        }
      }
      return await group.reduce(into: []) { $0.append($1) }
    }
  }
}

@Suite struct CacheStressA {
  @Test func everyTaskSharesOneParsePerFile() async {
    let results = await CacheStress.hammer()
    #expect(results.count == 64)
    #expect(Set(results).count == 1, "every task saw the same SourceFile instances")
    #expect(results[0].count == 40)
    #expect(ParseCache.parseCount(root: CacheStress.codebase.root) == 40)
  }
}

@Suite struct CacheStressB {
  @Test(arguments: 0..<8) func parallelSuitesDoNotDeadlock(_ index: Int) async {
    let results = await CacheStress.hammer()
    #expect(Set(results).count == 1)
    #expect(CacheStress.codebase.allCode.calls(named: "print").count == 40 * 50)
  }
}
