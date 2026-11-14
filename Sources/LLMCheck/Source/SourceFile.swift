import Foundation
import SwiftParser
import SwiftSyntax

/// One parsed Swift file: its text, its syntax tree and its declarations.
///
/// Files read from a ``Codebase`` come from a process-wide cache, so each is parsed once. Files made from a string
/// (`SourceFile(path:source:)`) are for tests of rules.
public final class SourceFile: Sendable {
  /// The file's path on disk, or the name given to an in-memory file.
  public let path: String
  /// The path relative to the codebase root, which scopes, baselines and messages use.
  public let relativePath: String
  public let source: String
  public let syntax: SourceFileSyntax

  /// Where each line starts: locations and snippets read it instead of a `SourceLocationConverter`, which keeps
  /// another copy of the text, and an array of lines, which kept a third.
  private let lineStarts: [Int]
  private let declarationsOnce = Once<[Declaration]>()
  private let nodeIndex = Locked<[ObjectIdentifier: [Syntax]]>([:])

  /// Parses `source`. `relativePath` defaults to `path`.
  public init(path: String, relativePath: String? = nil, source: String) {
    self.path = path
    self.relativePath = relativePath ?? path
    self.source = source
    let tree = Parser.parse(source: source)
    self.syntax = tree
    self.lineStarts = Self.lineStarts(of: source)
  }

  /// `Sidebar.swift` in `Sources/Sidebar/Sidebar.swift`.
  public var fileName: String { (relativePath as NSString).lastPathComponent }

  /// The folders and the file name of ``relativePath``.
  public var pathComponents: [String] { relativePath.split(separator: "/").map(String.init) }

  /// The Swift package target the file belongs to: the folder under the last `Sources`, `Tests` or `Plugins` folder
  /// of ``relativePath``. `Kit` for `Packages/Kit/Sources/Kit/Cache/Cache.swift`, `AppTests` for
  /// `Tests/AppTests/A.swift`; nil for `Sources/main.swift` or a path with none of those folders.
  public var module: String? {
    let folders = pathComponents.dropLast()
    guard let index = folders.lastIndex(where: { ["Sources", "Tests", "Plugins"].contains($0) }),
      index + 1 < folders.endIndex
    else { return nil }
    return folders[index + 1]
  }

  /// The top-level declarations. Their ``Declaration/children`` hold the nested ones.
  public var declarations: [Declaration] {
    declarationsOnce.value { DeclarationBuilder.declarations(in: self) }
  }

  /// Every node of a type, anywhere in the file, in source order: inside closures, `await`, `try`, `return`, `switch`
  /// and `#if`. The search runs once per file and node type.
  public func nodes<Node: SyntaxProtocol>(of type: Node.Type) -> [Node] {
    indexNodes([NodeQuery(Node.self)])
    let found = nodeIndex.withLock { $0[ObjectIdentifier(Node.self)] } ?? []
    return found.map { $0.cast(Node.self) }
  }

  /// Searches the file once for every type in `queries` not searched yet, so a query that needs several node types,
  /// like `references(to:)`, walks the tree once.
  func indexNodes(_ queries: [NodeQuery]) {
    let missing = nodeIndex.withLock { index in queries.filter { index[$0.id] == nil } }
    guard !missing.isEmpty else { return }
    let collector = NodeCollector(missing)
    collector.walk(syntax)
    nodeIndex.withLock { index in
      for (query, found) in zip(missing, collector.found) { index[query.id] = found }
    }
  }

  /// Where a node starts, after its leading trivia.
  public func location(of node: some SyntaxProtocol) -> Location {
    location(at: node.positionAfterSkippingLeadingTrivia)
  }

  /// The line and column of a position, both from 1, the column in UTF-8 bytes: what `SourceLocationConverter` gives
  /// as the physical location.
  func location(at position: AbsolutePosition) -> Location {
    let offset = position.utf8Offset
    // The last line that starts at or before `offset`.
    var low = 0
    var high = lineStarts.count
    while high - low > 1 {
      let middle = (low + high) / 2
      if lineStarts[middle] <= offset { low = middle } else { high = middle }
    }
    return Location(filePath: path, relativePath: relativePath, line: low + 1, column: offset - lineStarts[low] + 1)
  }

  /// A node's text as written, without its leading and trailing trivia: `trimmedDescription`, read from ``source``.
  /// `trimmedDescription` builds a trimmed copy of the node first, which cost more than half of building
  /// declarations. `node` must come from this file's tree.
  func text(of node: some SyntaxProtocol) -> String {
    let utf8 = source.utf8
    let start = utf8.index(utf8.startIndex, offsetBy: node.positionAfterSkippingLeadingTrivia.utf8Offset)
    let end = utf8.index(utf8.startIndex, offsetBy: node.endPositionBeforeTrailingTrivia.utf8Offset)
    return String(source[start..<end])
  }

  /// The trimmed text of a 1-based line.
  public func line(_ number: Int) -> String {
    guard number >= 1, number <= lineStarts.count else { return "" }
    let utf8 = source.utf8
    let start = utf8.index(utf8.startIndex, offsetBy: lineStarts[number - 1])
    let end = number < lineStarts.count ? utf8.index(utf8.startIndex, offsetBy: lineStarts[number]) : utf8.endIndex
    var text = Substring(source[start..<end])
    while let last = text.last, last.isLineBreak { text.removeLast() }
    return text.trimmingCharacters(in: .whitespaces)
  }

  /// The UTF-8 offset where each line starts, after `\n`, `\r` or `\r\n`: the line breaks Swift's parser counts.
  private static func lineStarts(of source: String) -> [Int] {
    var starts = [0]
    var previousWasCarriageReturn = false
    for (offset, byte) in source.utf8.enumerated() {
      switch byte {
      case UInt8(ascii: "\n"):
        if previousWasCarriageReturn { starts[starts.count - 1] = offset + 1 } else { starts.append(offset + 1) }
        previousWasCarriageReturn = false
      case UInt8(ascii: "\r"):
        starts.append(offset + 1)
        previousWasCarriageReturn = true
      default:
        previousWasCarriageReturn = false
      }
    }
    return starts
  }
}

/// Two files are equal when they are the same parsed file. A codebase parses each path once per process, so its files
/// compare like their paths; in-memory files made separately differ even with the same path and text.
extension SourceFile: Hashable {
  public static func == (lhs: SourceFile, rhs: SourceFile) -> Bool { lhs === rhs }
  public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// A node type to search for.
struct NodeQuery {
  let id: ObjectIdentifier
  let matches: (Syntax) -> Bool

  init<Node: SyntaxProtocol>(_ type: Node.Type) {
    id = ObjectIdentifier(type)
    matches = { $0.is(Node.self) }
  }
}

/// Collects the nodes of several types in one walk.
private final class NodeCollector: SyntaxAnyVisitor {
  let queries: [NodeQuery]
  /// One list per query, in source order.
  var found: [[Syntax]]
  /// The queries a kind matches, one bit each, worked out once per kind. `node.is(Node.self)` on every node looks up
  /// `Node`'s generic metadata behind a process-wide lock, which cost over half of a search's time and serialized
  /// parallel searches.
  private var matchesByKind: [SyntaxKind: UInt64] = [:]

  init(_ queries: [NodeQuery]) {
    precondition(queries.count <= 64, "at most 64 node types per walk")
    self.queries = queries
    found = Array(repeating: [], count: queries.count)
    super.init(viewMode: .sourceAccurate)
  }

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    let kind = node.kind
    var matching: UInt64
    if let known = matchesByKind[kind] {
      matching = known
    } else {
      matching = 0
      for index in queries.indices where queries[index].matches(node) { matching |= 1 << index }
      matchesByKind[kind] = matching
    }
    while matching != 0 {
      let index = matching.trailingZeroBitCount
      found[index].append(node)
      matching &= matching - 1
    }
    return .visitChildren
  }
}

/// One read and one parse per file per process, safe from any number of threads and tasks.
enum ParseCache {
  private static let texts = Locked<[String: Once<String?>]>([:])
  private static let entries = Locked<[String: Once<SourceFile?>]>([:])
  private static let parses = Locked<[String: Int]>([:])

  /// The file's text, read once.
  static func text(root: URL, relativePath: String) -> String? {
    once(in: texts, root: root, relativePath: relativePath).value {
      try? String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
  }

  static func file(root: URL, relativePath: String) -> SourceFile? {
    once(in: entries, root: root, relativePath: relativePath).value {
      guard let source = text(root: root, relativePath: relativePath) else { return nil }
      parses.withLock { $0[root.path, default: 0] += 1 }
      let url = root.appendingPathComponent(relativePath)
      return SourceFile(path: url.path, relativePath: relativePath, source: source)
    }
  }

  private static func once<Value>(
    in table: Locked<[String: Once<Value>]>, root: URL, relativePath: String
  ) -> Once<Value> {
    let key = root.path + "|" + relativePath
    return table.withLock { table in
      if let once = table[key] { return once }
      let once = Once<Value>()
      table[key] = once
      return once
    }
  }

  /// How many files this process has parsed under a root, for tests.
  static func parseCount(root: URL) -> Int { parses.withLock { $0[root.path, default: 0] } }
}

extension Character {
  /// The line breaks Swift's parser counts: `\n`, `\r` and `\r\n`, so line numbers agree with locations.
  var isLineBreak: Bool { self == "\n" || self == "\r\n" || self == "\r" }
}
