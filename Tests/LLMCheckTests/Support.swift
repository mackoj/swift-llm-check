import Foundation
import LLMCheck

/// The sample codebase in `Fixtures/SampleApp`.
enum Fixture {
  static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/SampleApp")

  static func codebase() throws -> Codebase {
    try Codebase(filePath: root.appendingPathComponent("Sources/App/Feature.swift").path)
  }
}

/// An in-memory file.
func file(_ source: String, path: String = "Sources/Test.swift") -> SourceFile {
  SourceFile(path: path, source: source)
}

extension RuleCategory {
  static let sample = RuleCategory("sample", description: "Rules for the tests.")
}

extension Rule {
  static let sample = Rule(
    id: "sample-rule",
    title: "Sample code does nothing wrong.",
    category: .sample,
    rationale: "Tests need a rule.",
    howToFix: "Do the right thing.",
    badExample: "wrong()",
    goodExample: "right()"
  )
}
