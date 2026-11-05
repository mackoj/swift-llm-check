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

  let converter: SourceLocationConverter
  private let lines: [String]
  private let declarationsOnce = Once<[Declaration]>()
  private let nodeIndex = Locked<[ObjectIdentifier: [Syntax]]>([:])

  /// Parses `source`. `relativePath` defaults to `path`.
  public init(path: String, relativePath: String? = nil, source: String) {
    self.path = path
    self.relativePath = relativePath ?? path
    self.source = source
    let tree = Parser.parse(source: source)
    self.syntax = tree
    self.converter = SourceLocationConverter(fileName: path, tree: tree)
    self.lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
  }

  /// `Sidebar.swift` in `Sources/Sidebar/Sidebar.swift`.
  public var fileName: String { (relativePath as NSString).lastPathComponent }

  /// The folders and the file name of ``relativePath``.
  public var pathComponents: [String] { relativePath.split(separator: "/").map(String.init) }

  /// The top-level declarations. Their ``Declaration/children`` hold the nested ones.
  public var declarations: [Declaration] {
    declarationsOnce.value { DeclarationBuilder.declarations(in: self) }
  }

  /// Every node of a type, anywhere in the file, in source order: inside closures, `await`, `try`, `return`, `switch`
  /// and `#if`. The search runs once per file and node type.
  public func nodes<Node: SyntaxProtocol>(of type: Node.Type) -> [Node] {
    let key = ObjectIdentifier(type)
    if let found = nodeIndex.withLock({ $0[key] }) { return found.map { $0.cast(Node.self) } }
    let collector = NodeCollector<Node>()
    collector.walk(syntax)
    nodeIndex.withLock { $0[key] = collector.found }
    return collector.found.map { $0.cast(Node.self) }
  }

  /// Where a node starts, after its leading trivia.
  public func location(of node: some SyntaxProtocol) -> Location {
    location(at: node.positionAfterSkippingLeadingTrivia)
  }

  func location(at position: AbsolutePosition) -> Location {
    let location = converter.location(for: position)
    return Location(filePath: path, relativePath: relativePath, line: location.line, column: location.column)
  }

  /// The trimmed text of a 1-based line.
  public func line(_ number: Int) -> String {
    guard number >= 1, number <= lines.count else { return "" }
    return lines[number - 1].trimmingCharacters(in: .whitespaces)
  }
}

private final class NodeCollector<Node: SyntaxProtocol>: SyntaxAnyVisitor {
  var found: [Syntax] = []

  init() { super.init(viewMode: .sourceAccurate) }

  override func visitAny(_ node: Syntax) -> SyntaxVisitorContinueKind {
    if node.is(Node.self) { found.append(node) }
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
