import Testing

/// Records one Swift Testing issue per finding, at the finding's file, line and column, with the offending line and
/// the rule's full text. Findings the baseline accepts are skipped; baseline entries that match nothing fail as stale,
/// at the call site.
///
/// ```swift
/// @Test func noPrint() throws {
///   let calls = try Codebase().productionCode.calls(named: "print").filter { $0.node.receiver == nil }
///   expectNone(calls, rule: .noPrint, baseline: ["LegacyLogger.swift"])
/// }
/// ```
@discardableResult
public func expectNone(
  _ findings: [some Finding],
  rule: Rule,
  baseline: Baseline = [],
  sourceLocation: Testing.SourceLocation = #_sourceLocation
) -> CheckResult {
  let result = rule.check(findings, baseline: baseline)
  record(result, sourceLocation: sourceLocation)
  return result
}

/// Records an issue for each item that does not satisfy `predicate`, the same way as
/// ``expectNone(_:rule:baseline:sourceLocation:)``.
///
/// ```swift
/// expectAll(reducers.flatMap(\.structs).named("State"), rule: .stateIsObservable) { $0.hasAttribute("ObservableState") }
/// ```
@discardableResult
public func expectAll<Item: Finding>(
  _ items: [Item],
  rule: Rule,
  baseline: Baseline = [],
  sourceLocation: Testing.SourceLocation = #_sourceLocation,
  _ predicate: (Item) throws -> Bool
) rethrows -> CheckResult {
  try expectNone(items.filter { try !predicate($0) }, rule: rule, baseline: baseline, sourceLocation: sourceLocation)
}

/// Records the issues of a result made with ``Rule/check(_:baseline:)``.
public func record(_ result: CheckResult, sourceLocation: Testing.SourceLocation = #_sourceLocation) {
  for finding in result.violations {
    Issue.record(Comment(rawValue: message(for: finding, rule: result.rule)), sourceLocation: finding.sourceLocation)
  }
  for entry in result.staleEntries {
    Issue.record(Comment(rawValue: staleMessage(for: entry, rule: result.rule)), sourceLocation: sourceLocation)
  }
}

/// The text recorded for one violation: where, the offending line, then the rule.
public func message(for finding: any Finding, rule: Rule) -> String {
  "\(finding.location): \(finding.snippet)\n\n\(rule.formatted)"
}

/// The text recorded for a baseline entry that matches nothing.
func staleMessage(for entry: String, rule: Rule) -> String {
  """
  Stale baseline entry "\(entry)" for \(rule.id): nothing there breaks "\(rule.title)" any more. Remove the entry.
  """
}

extension Finding {
  /// The finding's place as a Swift Testing source location, so Xcode shows the issue on the offending line.
  public var sourceLocation: Testing.SourceLocation {
    let components = location.relativePath.split(separator: "/")
    let module = components.dropLast().last.map(String.init) ?? "Source"
    return Testing.SourceLocation(
      fileID: "\(module)/\(location.fileName)", filePath: location.filePath, line: max(location.line, 1),
      column: max(location.column, 1))
  }
}
