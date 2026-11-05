import Foundation

/// How `excludes`, `Scope.in(_:)` and `Scope.excluding(_:)` match a path relative to the root. All three read a
/// pattern the same way, like a `.gitignore` line:
///
/// - A pattern with a slash matches from the root: `Packages/Foo` matches `Packages/Foo/Sources/A.swift`, never
///   `Other/Packages/Foo/A.swift`. A leading slash anchors a single name: `/Sources` is the top-level folder only.
/// - A pattern without a slash matches any one path component, a folder or the file name: `Generated` matches
///   `Sources/Generated/A.swift`, `A.swift` matches `Sources/A.swift`.
/// - `*` matches any run of characters inside one component: `*Tests`, `*.generated.swift`.
enum PathPattern {
  static func matches(_ pattern: String, _ relativePath: String) -> Bool {
    let trimmed = pattern.hasSuffix("/") ? String(pattern.dropLast()) : pattern
    let components = relativePath.split(separator: "/")
    if trimmed.contains("/") {
      let parts = trimmed.split(separator: "/")
      guard parts.count <= components.count else { return false }
      return zip(parts, components).allSatisfy { wildcard(String($0), String($1)) }
    }
    return components.contains { wildcard(trimmed, String($0)) }
  }

  /// `*` matches any characters; everything else matches itself.
  static func wildcard(_ pattern: String, _ text: String) -> Bool {
    guard pattern.contains("*") else { return pattern == text }
    let pieces = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
    var rest = Substring(text)
    for (index, piece) in pieces.enumerated() {
      if index == 0 {
        guard rest.hasPrefix(piece) else { return false }
        rest = rest.dropFirst(piece.count)
      } else if index == pieces.count - 1 {
        return piece.isEmpty || rest.hasSuffix(piece)
      } else if !piece.isEmpty {
        guard let range = rest.range(of: piece) else { return false }
        rest = rest[range.upperBound...]
      }
    }
    return rest.isEmpty
  }
}
