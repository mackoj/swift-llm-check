import LLMCheck
import Testing

/// The built-in detectors: each finds what it names and none of its look-alikes.
@Suite struct DetectorTests {
  func scope(_ source: String) -> Scope { Scope(files: [file(source)]) }

  @Test func findsXCTestImports() {
    let found = scope(
      """
      import XCTest
      #if canImport(XCTest)
        import XCTest
      #endif
      import Testing
      // import XCTest
      """
    ).xcTestImports
    #expect(found.map(\.location.line) == [1, 3])
  }

  @Test func findsDisabledTraits() {
    let found = scope(
      """
      @Test(.disabled("flaky")) func a() {}
      @Suite(.serialized, .disabled(if: isCI)) struct B {}
      @Testing.Test(.disabled()) func c() {}
      @Test(.enabled(if: true)) func d() {}
      let state = State.disabled(reason)
      let other = .disabled(reason)
      flags.disabled()
      """
    ).disabledTests
    #expect(found.map(\.location.line) == [1, 2, 3])
  }

  @Test func findsUnexplainedKnownIssues() {
    let found = scope(
      """
      withKnownIssue { try f() }
      withKnownIssue(reason) { try f() }
      withKnownIssue("") { try f() }
      withKnownIssue(isIntermittent: true) { try f() }
      withKnownIssue("bug 12: sync drops the error") { try f() }
      withKnownIssue("bug \\(id)", isIntermittent: true) { try f() }
      """
    ).unexplainedKnownIssues
    #expect(found.map(\.location.line) == [1, 2, 3, 4])
  }

  @Test func findsUnexplainedExpectedFailures() {
    let found = scope(
      """
      XCTExpectFailure()
      XCTExpectFailure { try f() }
      XCTExpectFailure(strict: false)
      XCTExpectFailure("bug 12: sync drops the error")
      XCTExpectFailure("bug 12", options: options) { try f() }
      """
    ).unexplainedExpectedFailures
    #expect(found.map(\.location.line) == [1, 2, 3])
  }

  @Test func findsUncommentedUncheckedSendable() {
    let found = scope(
      """
      final class A: @unchecked Sendable {}

      /// A doc comment describes the type; it does not justify it.
      final class B: @unchecked Sendable {
        let x = 1
      }

      // A comment above the type, separated by a blank line, is about something else.

      final class C: @unchecked Sendable {
        // MARK: - Not a reason
        let x = 1
      }

      extension D: @unchecked Sendable {}
      """
    ).uncommentedUncheckedSendable
    #expect(found.map(\.location.line) == [1, 4, 10, 15])
  }

  @Test func commentedUncheckedSendablePasses() {
    let found = scope(
      """
      // Every access to `storage` holds `lock`.
      final class A: @unchecked Sendable {}

      /// The cache.
      // Every access to `storage` holds `lock`.
      @MainActor
      final class B: @unchecked Sendable {}

      final class C: @unchecked Sendable {  // Every access holds `lock`.
        let lock = NSLock()
      }

      final class D: @unchecked Sendable {
        // @unchecked: set once, before any caller sees it.

        let x = 1
      }

      extension E: @unchecked Sendable {}  // E is immutable.

      /* Immutable after init. */
      struct F: @unchecked Sendable {}
      """
    ).uncommentedUncheckedSendable
    #expect(found.isEmpty)
  }

  @Test func findsForcedAndOptionalTries() {
    let tries = scope(
      """
      let a = try! f()
      let b = try? f()
      let c = try f()
      let d = (try? f()) ?? 0
      // try! in a comment
      let e = "try! in a string"
      """)
    #expect(tries.forcedTries.map(\.location.line) == [1])
    #expect(tries.optionalTries.map(\.location.line) == [2, 4])
  }

  @Test func findsForcedCastsUnfolded() {
    let found = scope(
      """
      let a = value as! String
      let b = value as? String
      let c = value as String
      if (x as! Int) > 1 {}
      let d = [value as! Int, 2]
      // value as! String
      """
    ).forcedCasts
    #expect(found.map(\.location.line) == [1, 4, 5])
    #expect(found.map(\.node.trimmedDescription) == ["as!", "as!", "as!"])
  }

  @Test func findsForceUnwraps() {
    let found = scope(
      """
      let a = value!
      let b = value!.count
      let c = try! f()
      let d = x != y
      let e = !flag
      let f = value as! Int
      """
    ).forceUnwraps
    #expect(found.map(\.location.line) == [1, 2])
  }
}
