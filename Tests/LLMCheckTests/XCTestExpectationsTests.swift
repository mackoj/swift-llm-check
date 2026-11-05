import LLMCheck
import XCTest

/// The XCTest assertions, checked by capturing the issues they record instead of failing.
final class XCTestExpectationsTests: XCTestCase {
  private var captured: [XCTIssue] = []
  private var capturing = false

  override func record(_ issue: XCTIssue) {
    if capturing { captured.append(issue) } else { super.record(issue) }
  }

  private func capture(_ body: () -> Void) -> [XCTIssue] {
    captured = []
    capturing = true
    body()
    capturing = false
    return captured
  }

  private let scope = Scope(files: [
    file("struct Feature {\n  func a() { track() }\n  func b() { track() }\n}", path: "Sources/App/Feature.swift"),
    file("let x = track()", path: "Sources/Other/Other.swift"),
  ])

  func testExpectNoneFailsAtEachViolationsFileAndLine() {
    let issues = capture { expectNone(scope.calls(named: "track"), rule: .sample, baseline: ["Other.swift"]) }
    XCTAssertEqual(
      issues.map(\.sourceCodeContext.location?.fileURL.lastPathComponent), ["Feature.swift", "Feature.swift"])
    XCTAssertEqual(issues.map(\.sourceCodeContext.location?.lineNumber), [2, 3])
    XCTAssertEqual(issues.map(\.type), [.assertionFailure, .assertionFailure])
    XCTAssertTrue(issues[0].compactDescription.hasPrefix("Sources/App/Feature.swift:2:14: func a() { track() }"))
    XCTAssertTrue(issues[0].compactDescription.contains(Rule.sample.formatted))
  }

  func testStaleEntriesFailAtTheCallSite() {
    let line = #line + 2
    let issues = capture {
      expectNone(scope.calls(named: "track"), rule: .sample, baseline: ["Feature.swift", "Other.swift", "Gone.swift"])
    }
    XCTAssertEqual(issues.count, 1)
    XCTAssertEqual(issues.first?.sourceCodeContext.location?.fileURL.lastPathComponent, "XCTestExpectationsTests.swift")
    XCTAssertEqual(issues.first?.sourceCodeContext.location?.lineNumber, line)
    XCTAssertTrue(
      issues.first?.compactDescription.contains(#"Stale baseline entry "Gone.swift" for sample-rule"#) == true)
  }

  func testExpectAllFailsForTheItemsThatFail() {
    var result: CheckResult?
    let issues = capture { result = expectAll(scope.functions, rule: .sample) { $0.name == "a" } }
    XCTAssertEqual(issues.map(\.sourceCodeContext.location?.lineNumber), [3])
    XCTAssertEqual(result?.violations.count, 1)
  }

  func testPassesSilently() {
    XCTAssertTrue(capture { expectNone(scope.calls(named: "missing"), rule: .sample) }.isEmpty)
    XCTAssertTrue(expectAll(scope.functions, rule: .sample) { $0.name.count == 1 }.passed)
  }
}
