import LLMCheck

/// The swift-llm-check repository, rooted where `.llm-check.yaml` is. Its file list and every parsed file are shared
/// by all suites, which Swift Testing runs in parallel.
func llmCheck() throws -> Codebase { try Codebase() }

extension RuleCategory {
  static let dependencies = RuleCategory(
    "dependencies",
    description: "What the library imports and exports. Read before you add an `import` to `Sources`."
  )
  static let concurrency = RuleCategory(
    "concurrency",
    description: "Sendable types and the lock discipline. Read before you add a public type, a lock or a queue."
  )
  static let reporting = RuleCategory(
    "reporting",
    description: "How the library talks to its user. Read before you write output."
  )
  static let testing = RuleCategory(
    "testing",
    description: "The library's own tests. Read before you add a test or mark a known issue."
  )
}
