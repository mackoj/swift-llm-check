#if canImport(XCTest)
  import XCTest

  /// The assertions for XCTest, built on ``Rule/check(_:baseline:)``. They are methods, so inside an `XCTestCase` the
  /// same `expectNone` and `expectAll` calls as in Swift Testing record XCTest failures instead.
  ///
  /// ```swift
  /// final class LoggingRules: XCTestCase {
  ///   func testNoPrint() throws {
  ///     let calls = try Codebase().productionCode.calls(named: "print").filter { $0.node.receiver == nil }
  ///     expectNone(calls, rule: .noPrint, baseline: ["LegacyLogger.swift"])
  ///   }
  /// }
  /// ```
  extension XCTestCase {
    /// Records one XCTest failure per finding, at the finding's file and line, with the offending line and the rule's
    /// full text. Findings the baseline accepts are skipped; stale baseline entries fail at the call site.
    @discardableResult
    public func expectNone(
      _ findings: [some Finding],
      rule: Rule,
      baseline: Baseline = [],
      file: StaticString = #filePath,
      line: UInt = #line
    ) -> CheckResult {
      let result = rule.check(findings, baseline: baseline)
      record(result, file: file, line: line)
      return result
    }

    /// Records a failure for each item that does not satisfy `predicate`, the same way as
    /// ``expectNone(_:rule:baseline:file:line:)``.
    @discardableResult
    public func expectAll<Item: Finding>(
      _ items: [Item],
      rule: Rule,
      baseline: Baseline = [],
      file: StaticString = #filePath,
      line: UInt = #line,
      _ predicate: (Item) throws -> Bool
    ) rethrows -> CheckResult {
      try expectNone(items.filter { try !predicate($0) }, rule: rule, baseline: baseline, file: file, line: line)
    }

    /// Records the failures of a result made with ``Rule/check(_:baseline:)``.
    public func record(_ result: CheckResult, file: StaticString = #filePath, line: UInt = #line) {
      for finding in result.violations {
        // XCTFail takes a StaticString file, so a failure at a path known only at run time is an XCTIssue.
        let location = XCTSourceCodeLocation(
          filePath: finding.location.filePath, lineNumber: max(finding.location.line, 1))
        record(
          XCTIssue(
            type: .assertionFailure,
            compactDescription: message(for: finding, rule: result.rule),
            sourceCodeContext: XCTSourceCodeContext(location: location)
          )
        )
      }
      for entry in result.staleEntries {
        XCTFail(staleMessage(for: entry, rule: result.rule), file: file, line: line)
      }
    }
  }
#endif
