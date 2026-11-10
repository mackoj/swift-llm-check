import LLMCheck
import SwiftSyntax
import Testing

@Suite struct RuleTests {
  let scope = Scope(files: [
    file(
      """
      struct Feature {
        func a() { track() }
        func b() { track() }
      }
      """, path: "Sources/App/Feature.swift"),
    file("let x = track()", path: "Sources/Other/Other.swift"),
  ])

  @Test func formatsEverythingAnAgentNeeds() {
    #expect(
      Rule.sample.formatted == """
        RULE: Sample code does nothing wrong. [sample-rule, sample]
        WHY: Tests need a rule.
        HOW TO FIX: Do the right thing.
        BAD:
            wrong()
        GOOD:
            right()
        """)
  }

  @Test func baselineEntriesMatchFilesPathsAndDeclarations() {
    let calls = scope.calls(named: "track")
    #expect(Rule.sample.check(calls, baseline: ["Feature.swift"]).violations.count == 1)
    #expect(Rule.sample.check(calls, baseline: ["App/Feature.swift", "Sources/Other/Other.swift"]).passed)
    #expect(Rule.sample.check(calls, baseline: ["Feature.swift:Feature.a"]).violations.count == 2)
    #expect(Rule.sample.check(calls, baseline: ["Feature.swift:Feature", "Other.swift"]).passed)
    #expect(Rule.sample.check(calls, baseline: ["Other.swift:Feature"]).violations.count == 3)
  }

  @Test func baselineCoveringFindingsAcceptsExactlyThem() {
    let calls = scope.calls(named: "track")
    let baseline = Baseline(covering: calls)
    #expect(baseline.entries == ["Feature.swift:Feature.a", "Feature.swift:Feature.b", "Other.swift:x"])
    #expect(Rule.sample.check(calls, baseline: baseline).passed)

    let later = Scope(files: [
      file(
        """
        struct Feature {
          func a() { track() }
          func b() { track() }
          func c() { track() }
        }
        """, path: "Sources/App/Feature.swift"),
      file("let x = track()", path: "Sources/Other/Other.swift"),
    ])
    #expect(Rule.sample.check(later.calls(named: "track"), baseline: baseline).violations.map(\.location.line) == [4])
  }

  @Test func baselineRendersAsASwiftArrayLiteral() {
    #expect(Baseline(["A.swift:A", "B.swift"]).swiftArrayLiteral == "[\n  \"A.swift:A\",\n  \"B.swift\",\n]")
    #expect(Baseline([]).swiftArrayLiteral == "[]")
    #expect(Baseline(covering: [] as [any Finding]).entries.isEmpty)
  }

  @Test func reportsStaleEntriesOnce() {
    let result = Rule.sample.check(
      scope.calls(named: "track"), baseline: ["Feature.swift", "Other.swift", "Gone.swift", "Gone.swift"])
    #expect(result.violations.isEmpty)
    #expect(result.baselined.count == 3)
    #expect(result.staleEntries == ["Gone.swift"])
    #expect(!result.passed)
  }

  @Test func recordsOneIssuePerViolationAtItsLine() {
    let calls = scope.calls(named: "track")
    withKnownIssue {
      expectNone(calls, rule: .sample, baseline: ["Other.swift"])
    } matching: { issue in
      guard let location = issue.sourceLocation, let comment = issue.comments.first?.rawValue else { return false }
      return location.fileName == "Feature.swift" && [2, 3].contains(location.line) && location.column == 14
        && comment.hasPrefix("Sources/App/Feature.swift:\(location.line):14: func ")
        && comment.contains(Rule.sample.formatted)
    }
  }

  @Test func recordsStaleEntriesAtTheCallSite() {
    withKnownIssue {
      expectNone(scope.calls(named: "track"), rule: .sample, baseline: ["Feature.swift", "Other.swift", "Gone.swift"])
    } matching: { issue in
      issue.sourceLocation?.fileName == "RuleTests.swift"
        && issue.comments.first?.rawValue.contains(#"Stale baseline entry "Gone.swift" for sample-rule"#) == true
    }
  }

  @Test func passesSilently() {
    expectNone(scope.calls(named: "missing"), rule: .sample)
    let result = expectAll(scope.functions, rule: .sample) { $0.name.count == 1 }
    #expect(result.passed)
  }

  @Test func expectAllReportsTheItemsThatFail() {
    withKnownIssue {
      expectAll(scope.functions, rule: .sample) { $0.name == "a" }
    } matching: { issue in
      issue.sourceLocation?.line == 3
    }
  }
}

@Suite struct CatalogTests {
  static let other = Rule(
    id: "other", title: "Other.", category: RuleCategory("second", description: "Second category."),
    rationale: "Because.", howToFix: "Fix it.")

  @Test func rendersMarkdownByCategory() {
    let markdown = RuleCatalog([.sample, Self.other]).markdown(title: "Rules", introduction: "Read these.")
    #expect(
      markdown == """
        # Rules

        Read these.

        ## sample

        Rules for the tests.

        ### Sample code does nothing wrong.

        `sample-rule`: Tests need a rule.

        **How to fix:** Do the right thing.

        Bad:

        ```swift
        wrong()
        ```

        Good:

        ```swift
        right()
        ```

        ## second

        Second category.

        ### Other.

        `other`: Because.

        **How to fix:** Fix it.

        """)
  }

  @Test func findsDuplicateIDs() {
    #expect(RuleCatalog([.sample, Self.other, .sample]).duplicateIDs == ["sample-rule"])
    #expect(RuleCatalog([.sample, Self.other]).categories.map(\.name) == ["sample", "second"])
  }

  @Test func expectFileFailsWhenTheFileDiffers() throws {
    let codebase = try Fixture.codebase()
    try expectFile(
      ".llm-check.yaml", in: codebase,
      matches: try String(contentsOf: codebase.root.appendingPathComponent(".llm-check.yaml"), encoding: .utf8))
    try withKnownIssue {
      try expectFile("RULES.md", in: codebase, matches: "# Rules")
    } matching: { issue in
      issue.comments.first?.rawValue.contains("RULES.md is missing") == true
    }
  }
}
