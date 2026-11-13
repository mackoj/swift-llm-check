import LLMCheck
import Testing

/// The rules, run on the repository. A failure prints the rule, why it exists and how to fix it.
@Suite("Architecture rules")
struct ArchitectureRules {
  static func sources() throws -> Scope { try llmCheck().productionCode.in("/Sources") }
  static func tests() throws -> Scope { try llmCheck().testCode.in("/Tests") }

  @Test func sourcesImportTheirBudget() throws {
    let sources = try Self.sources()
    #expect(sources.relativePaths.count > 10, "is .llm-check.yaml at the repository root?")
    expectNone(Detect.importsOutsideTheBudget(in: sources), rule: .sourcesImportTheirBudget)
  }

  @Test func xcTestIsConditional() throws {
    let sources = try Self.sources()
    #expect(!sources.imports(of: "XCTest").isEmpty, "the XCTest assertions moved: update the rule")
    expectNone(Detect.unconditionalXCTestImports(in: sources), rule: .xcTestIsConditional)
  }

  @Test func swiftSyntaxIsNotReexported() throws {
    expectNone(Detect.reexports(in: try Self.sources()), rule: .swiftSyntaxIsNotReexported)
  }

  @Test func publicTypesAreSendable() throws {
    let sources = try Self.sources()
    #expect(sources.structs.withModifier("public").count > 10)
    expectNone(Detect.nonSendablePublicTypes(in: sources), rule: .publicTypesAreSendable)
  }

  @Test func uncheckedSendableExplainsItself() throws {
    expectNone(Detect.uncommentedUncheckedSendable(in: try Self.sources()), rule: .uncheckedSendableExplainsItself)
  }

  @Test func locksStayInLocked() throws {
    let sources = try Self.sources()
    #expect(sources.in(Detect.lockedFile).relativePaths.count == 1, "Locked.swift moved: update the rule")
    expectNone(Detect.synchronizationOutsideLocked(in: sources), rule: .locksStayInLocked)
  }

  @Test func libraryPrintsNothing() throws {
    expectNone(Detect.printing(in: try Self.sources()), rule: .libraryPrintsNothing)
  }

  @Test func xcTestIsTestedAlone() throws {
    let tests = try Self.tests()
    #expect(tests.containing("import Testing").relativePaths.count > 5, "is .llm-check.yaml at the repository root?")
    expectNone(Detect.xcTestImports(in: tests), rule: .xcTestIsTestedAlone)
  }

  @Test func knownIssuesExplainThemselves() throws {
    let tests = try Self.tests()
    #expect(!tests.calls(named: "withKnownIssue").isEmpty)
    expectNone(Detect.unexplainedKnownIssues(in: tests), rule: .knownIssuesExplainThemselves)
  }
}

/// Keeps `docs/architecture-rules.md` in step with the rules. Regenerate with
/// `LLM_CHECK_RECORD=1 swift test --package-path Architecture`.
@Test func rulesDocumentIsUpToDate() throws {
  let catalog = RuleCatalog(allRules)
  #expect(catalog.duplicateIDs.isEmpty)
  try expectFile(
    "docs/architecture-rules.md", in: llmCheck(),
    matches: catalog.markdown(
      title: "Architecture rules",
      introduction: """
        swift-llm-check's own rules, enforced on this repository by the `Architecture/` package with the library \
        itself: `swift test --package-path Architecture`. Each rule cites the README or CHANGELOG promise it keeps. \
        Generated from the rules; do not edit by hand.
        """))
}
