/// The findings a rule accepts for now, so it can land before every violation is fixed. Entries that no longer match
/// anything fail as stale, so a baseline only shrinks.
///
/// An entry is one of:
/// - a file name: `Sidebar.swift`
/// - a path from the root, or its end: `Sources/Sidebar/Sidebar.swift`
/// - a file and a declaration: `Sidebar.swift:SidebarFeature` or `Sidebar.swift:SidebarFeature.State`, which matches
///   findings in that declaration or anything nested in it.
public struct Baseline: Sendable, Hashable, ExpressibleByArrayLiteral {
  public let entries: [String]

  public init(_ entries: [String]) { self.entries = entries }
  public init(arrayLiteral entries: String...) { self.entries = entries }

  /// Whether `entry` covers `finding`.
  public static func entry(_ entry: String, matches finding: any Finding) -> Bool {
    let file: Substring
    let declaration: Substring?
    if let colon = entry.firstIndex(of: ":") {
      file = entry[..<colon]
      declaration = entry[entry.index(after: colon)...]
    } else {
      file = Substring(entry)
      declaration = nil
    }
    let location = finding.location
    let fileMatches =
      file.contains("/")
      ? location.relativePath == file || location.relativePath.hasSuffix("/" + file)
      : location.fileName == file
    guard fileMatches else { return false }
    guard let declaration else { return true }
    return finding.declarationNames.contains(String(declaration))
  }
}

/// What a rule found: the violations to fix, those the baseline accepts, and baseline entries that match nothing.
public struct CheckResult: Sendable {
  public let rule: Rule
  public let violations: [any Finding]
  public let baselined: [any Finding]
  public let staleEntries: [String]

  public var passed: Bool { violations.isEmpty && staleEntries.isEmpty }
}

extension Rule {
  /// Splits `findings` into violations and baselined findings, and lists the stale baseline entries. No issue is
  /// recorded; ``expectNone(_:rule:baseline:sourceLocation:)`` does that.
  public func check(_ findings: [any Finding], baseline: Baseline = []) -> CheckResult {
    var violations: [any Finding] = []
    var baselined: [any Finding] = []
    var used = Set<String>()
    for finding in findings {
      let entries = baseline.entries.filter { Baseline.entry($0, matches: finding) }
      if entries.isEmpty {
        violations.append(finding)
      } else {
        baselined.append(finding)
        used.formUnion(entries)
      }
    }
    var seen = Set<String>()
    let stale = baseline.entries.filter { !used.contains($0) && seen.insert($0).inserted }
    return CheckResult(rule: self, violations: violations, baselined: baselined, staleEntries: stale)
  }
}
