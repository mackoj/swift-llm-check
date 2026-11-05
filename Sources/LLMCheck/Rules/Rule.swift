/// A rule, written for whoever reads the failure: often an AI agent that has to fix it without asking.
///
/// ```swift
/// extension Rule {
///   static let noPrint = Rule(
///     id: "no-print",
///     title: "The app never calls print.",
///     category: .logging,
///     rationale: "print output is lost in a shipped app and cannot be private.",
///     howToFix: "Use a `Logger` and interpolate with `privacy: .private`.",
///     badExample: #"print("loaded \(url)")"#,
///     goodExample: #"logger.debug("loaded \(url, privacy: .private)")"#
///   )
/// }
/// ```
public struct Rule: Sendable, Hashable, Identifiable {
  /// A stable kebab-case identifier, used in catalogs and messages.
  public let id: String
  /// The rule as one sentence, stated as what the code does.
  public let title: String
  public let category: RuleCategory
  /// Why the rule exists, so the fix keeps its intent.
  public let rationale: String
  /// What to change.
  public let howToFix: String
  public let badExample: String?
  public let goodExample: String?

  public init(
    id: String, title: String, category: RuleCategory, rationale: String, howToFix: String,
    badExample: String? = nil, goodExample: String? = nil
  ) {
    self.id = id
    self.title = title
    self.category = category
    self.rationale = rationale
    self.howToFix = howToFix
    self.badExample = badExample
    self.goodExample = goodExample
  }

  /// The text printed with each violation.
  public var formatted: String {
    var lines = [
      "RULE: \(title) [\(id), \(category.name)]",
      "WHY: \(rationale)",
      "HOW TO FIX: \(howToFix)",
    ]
    if let badExample { lines.append("BAD:\n\(Self.indent(badExample))") }
    if let goodExample { lines.append("GOOD:\n\(Self.indent(goodExample))") }
    return lines.joined(separator: "\n")
  }

  private static func indent(_ code: String) -> String {
    code.split(separator: "\n", omittingEmptySubsequences: false).map { "    \($0)" }.joined(separator: "\n")
  }
}

/// A group of rules, with when to read them.
///
/// ```swift
/// extension RuleCategory {
///   static let logging = RuleCategory("logging", description: "Read before you log anything.")
/// }
/// ```
public struct RuleCategory: Sendable, Hashable {
  public let name: String
  public let description: String

  public init(_ name: String, description: String) {
    self.name = name
    self.description = description
  }
}
