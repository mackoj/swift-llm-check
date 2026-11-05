import Foundation
import Testing

/// A list of rules rendered as Markdown, for an `AGENTS.md` section or a `SKILL.md`, so agents read the rules before
/// they break them.
///
/// ```swift
/// @Test func catalogIsUpToDate() throws {
///   let catalog = RuleCatalog([.noPrint, .stateIsObservable])
///   try expectFile("docs/architecture-rules.md", in: Codebase(), matches: catalog.markdown())
/// }
/// ```
public struct RuleCatalog: Sendable {
  public let rules: [Rule]

  public init(_ rules: [Rule]) { self.rules = rules }

  /// The categories, in the order their first rule appears.
  public var categories: [RuleCategory] {
    var seen = Set<RuleCategory>()
    return rules.map(\.category).filter { seen.insert($0).inserted }
  }

  /// Rule ids used more than once.
  public var duplicateIDs: [String] {
    Dictionary(grouping: rules, by: \.id).filter { $0.value.count > 1 }.keys.sorted()
  }

  /// One section per category, one entry per rule, with its rationale, fix and examples.
  public func markdown(title: String = "Architecture rules", introduction: String? = nil) -> String {
    var lines = ["# \(title)", ""]
    if let introduction { lines += [introduction, ""] }
    for category in categories {
      lines += ["## \(category.name)", "", category.description, ""]
      for rule in rules where rule.category == category {
        lines += [
          "### \(rule.title)", "", "`\(rule.id)`: \(rule.rationale)", "", "**How to fix:** \(rule.howToFix)", "",
        ]
        if let bad = rule.badExample { lines += ["Bad:", "", "```swift", bad, "```", ""] }
        if let good = rule.goodExample { lines += ["Good:", "", "```swift", good, "```", ""] }
      }
    }
    return lines.joined(separator: "\n")
  }
}

/// Fails unless the file at `relativePath` holds `content`. Run with `LLM_CHECK_RECORD=1` to write it instead.
public func expectFile(
  _ relativePath: String,
  in codebase: Codebase,
  matches content: String,
  sourceLocation: Testing.SourceLocation = #_sourceLocation
) throws {
  let url = codebase.root.appendingPathComponent(relativePath)
  if ProcessInfo.processInfo.environment["LLM_CHECK_RECORD"] == "1" {
    try content.write(to: url, atomically: true, encoding: .utf8)
    return
  }
  let current = try? String(contentsOf: url, encoding: .utf8)
  if current != content {
    Issue.record(
      Comment(
        rawValue: """
          \(relativePath) is \(current == nil ? "missing" : "out of date"). Regenerate it with \
          `LLM_CHECK_RECORD=1 swift test --filter <this test>`, then commit it.
          """),
      sourceLocation: sourceLocation
    )
  }
}
