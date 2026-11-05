import Foundation

/// What a codebase reads, from the marker file at its root (`.llm-check.yaml`).
///
/// ```yaml
/// # Folders or files never read: a name matches any path component, a path with a slash matches from the root.
/// excludes:
///   - build
///   - Packages/Legacy
/// # A path component that ends with one of these marks test code (default: Tests).
/// testSuffixes:
///   - Tests
/// # A path component named one of these marks test code (default: Fixtures).
/// testFolders:
///   - Fixtures
/// ```
public struct Configuration: Sendable, Hashable {
  /// The marker file that `Codebase` looks for to find the root.
  public static let markerFileName = ".llm-check.yaml"

  /// Path patterns never read. See ``PathPattern``.
  public var excludes: [String]
  /// A directory whose name ends with one of these holds test code.
  public var testSuffixes: [String]
  /// A directory with one of these names holds test code.
  public var testFolders: [String]

  public init(excludes: [String] = [], testSuffixes: [String] = ["Tests"], testFolders: [String] = ["Fixtures"]) {
    self.excludes = excludes
    self.testSuffixes = testSuffixes
    self.testFolders = testFolders
  }

  /// Reads the small YAML subset the marker file uses: top-level keys with block (`- item`) or flow (`[a, b]`) lists.
  public init(yaml: String) throws {
    self.init()
    var lists: [String: [String]] = [:]
    var key: String?
    for (number, rawLine) in yaml.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
      let line = Self.stripComment(String(rawLine))
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty { continue }
      if trimmed.hasPrefix("- ") || trimmed == "-" {
        guard let key else { throw ConfigurationError(line: number + 1, message: "a list item outside a key") }
        lists[key, default: []].append(Self.unquote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
        continue
      }
      guard let colon = trimmed.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else {
        throw ConfigurationError(line: number + 1, message: "expected `key:` or `- item`")
      }
      let name = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
      let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      key = name
      lists[name] = []
      if value.hasPrefix("[") && value.hasSuffix("]") {
        lists[name] = value.dropFirst().dropLast().split(separator: ",")
          .map { Self.unquote($0.trimmingCharacters(in: .whitespaces)) }
          .filter { !$0.isEmpty }
      } else if !value.isEmpty {
        throw ConfigurationError(line: number + 1, message: "`\(name)` must be a list")
      }
    }
    for name in lists.keys where !["excludes", "testSuffixes", "testFolders"].contains(name) {
      throw ConfigurationError(line: nil, message: "unknown key `\(name)`")
    }
    if let excludes = lists["excludes"] { self.excludes = excludes }
    if let testSuffixes = lists["testSuffixes"] { self.testSuffixes = testSuffixes }
    if let testFolders = lists["testFolders"] { self.testFolders = testFolders }
  }

  /// Whether a file, given relative to the root, is test code.
  public func isTestCode(_ relativePath: String) -> Bool {
    let directories = relativePath.split(separator: "/").dropLast()
    return directories.contains { component in
      testFolders.contains(String(component)) || testSuffixes.contains { component.hasSuffix($0) }
    }
  }

  private static func stripComment(_ line: String) -> String {
    guard let hash = line.firstIndex(of: "#") else { return line }
    if hash == line.startIndex || line[line.index(before: hash)] == " " { return String(line[..<hash]) }
    return line
  }

  private static func unquote(_ value: String) -> String {
    for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
      return String(value.dropFirst().dropLast())
    }
    return value
  }
}

/// The marker file could not be read.
public struct ConfigurationError: Error, CustomStringConvertible {
  public let line: Int?
  public let message: String

  public var description: String {
    "\(Configuration.markerFileName)\(line.map { ":\($0)" } ?? ""): \(message)"
  }
}
