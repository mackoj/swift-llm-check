import LLMCheck

extension Rule {
  static let sourcesImportTheirBudget = Rule(
    id: "sources-import-their-budget",
    title: "`Sources` imports only Foundation, Dispatch, SwiftSyntax, SwiftParser, Testing and XCTest.",
    category: .dependencies,
    rationale: """
      The only dependency is swift-syntax (README, "Requirements"), and only its parser and syntax tree (README, \
      "swift-syntax versions"): that is what lets the library accept every swift-syntax from 601 to below 700, and \
      never hold back an app whose macros need the newest one. Another swift-syntax module (SwiftSyntaxBuilder, \
      SwiftOperators, SwiftDiagnostics) or another package narrows the range or adds to every adopter's build.
      """,
    howToFix: """
      Write it with the parser and `SyntaxVisitor`, as the rest of `Sources` is. A new module is a decision for the \
      maintainer: add it to `Package.swift`, to `Detect.allowedImports` and to the README's "swift-syntax versions" \
      section in the same change, and check it on swift-syntax 601 (CI's pinned job).
      """,
    badExample: """
      import SwiftSyntaxBuilder
      let call = FunctionCallExprSyntax(callee: DeclReferenceExprSyntax(baseName: "print"))
      """,
    goodExample: """
      import SwiftParser
      let tree = Parser.parse(source: "print(x)")
      """
  )

  static let xcTestIsConditional = Rule(
    id: "xctest-is-conditional",
    title: "`Sources` imports XCTest only inside `#if canImport(XCTest)`.",
    category: .dependencies,
    rationale: """
      XCTest is not there everywhere LLMCheck builds: a Swift Testing-only target or a toolchain without it would \
      fail to compile the whole library for the sake of the XCTest assertions (README, "Assertions and \
      baselines"). `XCTestExpectations.swift` compiles them only where XCTest exists.
      """,
    howToFix: "Move the code and its import into the `#if canImport(XCTest)` block of `XCTestExpectations.swift`.",
    badExample: """
      import XCTest
      extension XCTestCase { public func expectNone(…) }
      """,
    goodExample: """
      #if canImport(XCTest)
        import XCTest
        extension XCTestCase { public func expectNone(…) }
      #endif
      """
  )

  static let swiftSyntaxIsNotReexported = Rule(
    id: "swiftsyntax-is-not-reexported",
    title: "`Sources` re-exports nothing: no `@_exported import`.",
    category: .dependencies,
    rationale: """
      0.2.0 stopped re-exporting SwiftSyntax (CHANGELOG, 0.2.0, "Breaking"): SwiftSyntax and Testing both declare \
      `SourceLocation`, so the re-export made every rule file that imports Testing write `Testing.SourceLocation`. \
      Re-exporting any module brings that clash, or one like it, back to every adopter.
      """,
    howToFix: """
      Import the module plainly. A rule file that names a node type imports SwiftSyntax itself (README, \
      "SwiftSyntax is not re-exported").
      """,
    badExample: "@_exported import SwiftSyntax",
    goodExample: "import SwiftSyntax"
  )

  static let publicTypesAreSendable = Rule(
    id: "public-types-are-sendable",
    title: "A public struct, enum or class is `Sendable`.",
    category: .concurrency,
    rationale: """
      Everything is `Sendable` (README, "Compared with Harmonize"): Swift Testing runs suites in parallel, and a \
      rule shares its `Codebase`, `Scope` and findings across them. A public type that is not `Sendable` makes \
      adopters write `@preconcurrency import LLMCheck`, as Harmonize's did; they cannot add the conformance \
      themselves.
      """,
    howToFix: """
      Declare `Sendable` on the type, or conform to a protocol that refines it (`Finding`, `Error`). A generic type \
      declares it in an extension, conditionally on its parameters.
      """,
    badExample: "public struct Report {",
    goodExample: "public struct Report: Sendable {"
  )

  static let uncheckedSendableExplainsItself = Rule(
    id: "unchecked-sendable-explains-itself",
    title: "An `@unchecked Sendable` conformance has a comment that proves it safe.",
    category: .concurrency,
    rationale: """
      `@unchecked Sendable` turns off the compiler's data-race check for the type. The comment is the only proof \
      left that it is safe to share, and the caches promise exactly that (README, "Speed and concurrency": \
      "Swift Testing's parallel suites are safe").
      """,
    howToFix: """
      Prefer a `Sendable` value type, or keep the state in `Locked`. If neither fits, write a `//` comment that \
      says what guards the mutable state: above the declaration, at the end of the line that opens its body, or on \
      the first line of the body, as `Declaration` and `Locked` do. A `///` doc comment describes the type to its \
      users and does not count.
      """,
    badExample: "final class Cache: @unchecked Sendable {",
    goodExample: """
      // Every access to `storage` holds `lock`.
      final class Cache: @unchecked Sendable {
      """
  )

  static let locksStayInLocked = Rule(
    id: "locks-stay-in-locked",
    title: "Only `Support/Locked.swift` uses a lock, a semaphore or a dispatch queue.",
    category: .concurrency,
    rationale: """
      The caches never wait on one another (README, "Speed and concurrency"): one lock guards a table, a per-file \
      `Once` is held only while that file is parsed, and nothing that computes a value takes another lock. That \
      holds because every lock is a `Locked` or a `Once` and every fan-out is `concurrentMap`. A lock or a queue \
      elsewhere can be taken inside one of them and deadlock parallel suites, as Harmonize did.
      """,
    howToFix: """
      Keep shared state in `Locked`, compute once with `Once`, and run work on every core with `concurrentMap`. A \
      new primitive goes in `Support/Locked.swift`, with a comment on why it cannot wait on the others. `Mutex` \
      needs macOS 15; the library supports macOS 14.
      """,
    badExample: """
      private let lock = NSLock()
      private var trees: [String: SourceFileSyntax] = [:]
      """,
    goodExample: "private let trees = Locked<[String: SourceFileSyntax]>([:])"
  )

  static let libraryPrintsNothing = Rule(
    id: "library-prints-nothing",
    title: "`Sources` never prints: no `print`, `debugPrint` or `dump`.",
    category: .reporting,
    rationale: """
      A violation is reported as a test issue at its file and line, with the rule's full text (README, top): that \
      is where Xcode, `swift test` and an agent look. Text printed by a library run inside a test is interleaved \
      with every parallel suite's output, attached to no test, and lost in Xcode's test navigator.
      """,
    howToFix: """
      Record an issue (`Issue.record` with a `sourceLocation`, or `XCTFail` in the XCTest assertions), or return \
      the text for the caller to use, like `Baseline.swiftArrayLiteral`.
      """,
    badExample: #"print("stale baseline entry \(entry)")"#,
    goodExample: "Issue.record(Comment(rawValue: staleMessage(for: entry, rule: rule)), sourceLocation: sourceLocation)"
  )

  static let xcTestIsTestedAlone = Rule(
    id: "xctest-is-tested-alone",
    title: "Tests use Swift Testing; only `XCTestExpectationsTests.swift` imports XCTest.",
    category: .testing,
    rationale: """
      The library is built for Swift Testing first (README, top: rules are "written as Swift Testing tests"), and \
      its own tests are written the way its users write rules. XCTest is imported in one file, to test the XCTest \
      assertions in an `XCTestCase`, the only place they run.
      """,
    howToFix: "Write an `@Suite` of `@Test` functions with `#expect` and `#require`, and `import Testing`.",
    badExample: """
      import XCTest
      final class ScopeTests: XCTestCase { func testExcluding() { XCTAssertEqual(…) } }
      """,
    goodExample: """
      import Testing
      @Suite struct ScopeTests { @Test func excluding() { #expect(…) } }
      """
  )

  static let knownIssuesExplainThemselves = Rule(
    id: "known-issues-explain-themselves",
    title: "`withKnownIssue` names its issue, or pins the issue it expects with `matching:`.",
    category: .testing,
    rationale: """
      A known issue hides a failing expectation. The library's tests use it on purpose, to check that \
      `expectNone`, `expectAll` and `expectFile` record the right issue; there, `matching:` says which issue, and \
      the test fails if another one is recorded. A bare `withKnownIssue { }` accepts any failure, so the next reader \
      cannot tell a check of the recorded issue from a bug nobody understood.
      """,
    howToFix: """
      To check what is recorded, add `matching:` with the file, line or text the issue must have. To silence a \
      bug, pass the reason first, with the GitHub issue that tracks it.
      """,
    badExample: """
      withKnownIssue { expectNone(calls, rule: .sample) }
      """,
    goodExample: """
      withKnownIssue {
        expectNone(calls, rule: .sample)
      } matching: { issue in
        issue.sourceLocation?.line == 3
      }
      """
  )
}

/// Every rule, in the order `docs/architecture-rules.md` lists them.
let allRules: [Rule] = [
  .sourcesImportTheirBudget, .xcTestIsConditional, .swiftSyntaxIsNotReexported, .publicTypesAreSendable,
  .uncheckedSendableExplainsItself, .locksStayInLocked, .libraryPrintsNothing, .xcTestIsTestedAlone,
  .knownIssuesExplainThemselves,
]
