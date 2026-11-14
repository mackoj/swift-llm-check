import Foundation
import SwiftSyntax

/// A place in a file: 1-based line and column.
public struct Location: Sendable, Hashable, CustomStringConvertible {
  public let filePath: String
  public let relativePath: String
  public let line: Int
  public let column: Int

  public init(filePath: String, relativePath: String, line: Int, column: Int) {
    self.filePath = filePath
    self.relativePath = relativePath
    self.line = line
    self.column = column
  }

  public var fileName: String { (relativePath as NSString).lastPathComponent }

  /// `Sources/A.swift:12:5`
  public var description: String { "\(relativePath):\(line):\(column)" }
}

/// Something a rule can report: a declaration, a node match or a hand-made ``Violation``.
public protocol Finding: Sendable {
  var location: Location { get }
  /// The offending source line, trimmed.
  var snippet: String { get }
  /// The qualified names of the declarations around the finding, innermost first (`Feature.State`, `Feature`).
  /// A baseline entry `File.swift:Feature` matches any of them.
  var declarationNames: [String] { get }
}

/// A finding built by hand, for checks that are not about one declaration or node.
public struct Violation: Finding {
  public let location: Location
  public let snippet: String
  public let declarationNames: [String]

  public init(location: Location, snippet: String, declarationNames: [String] = []) {
    self.location = location
    self.snippet = snippet
    self.declarationNames = declarationNames
  }
}

/// A node found in a file, with where it is.
public struct Match<Node: SyntaxProtocol>: Finding {
  public let node: Node
  public let file: SourceFile
  public let location: Location

  public init(node: Node, file: SourceFile) {
    self.node = node
    self.file = file
    self.location = file.location(of: node)
  }

  public var snippet: String { file.line(location.line) }

  public var declarationNames: [String] { DeclarationNames.enclosing(Syntax(node), in: file) }

  /// The same match with its node as `Syntax`, so matches of different node types can be reported under one rule:
  /// `scope.references(to: "CommandLine") + scope.calls(named: "print").map(\.erased)`.
  public var erased: Match<Syntax> { Match<Syntax>(node: Syntax(node), file: file) }
}

enum DeclarationNames {
  /// The qualified names of the named declarations that contain `node` (and `node` itself), innermost first.
  static func enclosing(_ node: Syntax, in file: SourceFile) -> [String] {
    var names: [String] = []
    var current: Syntax? = node
    while let syntax = current {
      if let name = name(of: syntax, in: file) { names.append(name) }
      current = syntax.parent
    }
    let outerFirst = Array(names.reversed())
    return outerFirst.indices.reversed().map { outerFirst[...$0].joined(separator: ".") }
  }

  /// The name a declaration contributes to a qualified name, or nil for anything else.
  static func name(of syntax: Syntax, in file: SourceFile) -> String? {
    switch syntax.as(SyntaxEnum.self) {
    case .structDecl(let decl): decl.name.text
    case .classDecl(let decl): decl.name.text
    case .enumDecl(let decl): decl.name.text
    case .actorDecl(let decl): decl.name.text
    case .protocolDecl(let decl): decl.name.text
    case .extensionDecl(let decl): file.text(of: decl.extendedType)
    case .functionDecl(let decl): decl.name.text
    case .initializerDecl: "init"
    case .enumCaseElement(let element): element.name.text
    case .typeAliasDecl(let decl): decl.name.text
    case .patternBinding(let binding): file.text(of: binding.pattern)
    default: nil
    }
  }
}
