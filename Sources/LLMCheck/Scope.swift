import SwiftSyntax

/// A set of files to check: part of a codebase, or files made in memory.
///
/// ```swift
/// codebase.productionCode.in("Packages/Features").excluding("DocumentFeature").calls(named: "apply")
/// ```
///
/// Scopes are values: narrowing one returns a new scope. Reading ``files`` parses what is not cached yet, on every
/// core.
public struct Scope: Sendable {
  enum Kind: Sendable { case production, test, all }

  private enum Base: Sendable {
    case codebase(Codebase, Kind)
    case files([SourceFile])
  }

  private let base: Base
  /// Each group narrows the scope: a file must match one pattern of every group.
  private var inclusions: [[String]] = []
  private var exclusions: [String] = []
  /// Each group narrows the scope: a file's text must contain one string of every group.
  private var texts: [[String]] = []

  init(codebase: Codebase, kind: Kind) {
    base = .codebase(codebase, kind)
  }

  /// A scope over in-memory files, for testing rules.
  public init(files: [SourceFile]) {
    base = .files(files)
  }

  /// Only the files that match one of `patterns`, read like ``excluding(_:)-(String...)`` and `excludes`: a name
  /// matches any folder or file (`in("Models")`), a path with a slash matches from the root (`in("Packages/Foo")`,
  /// `in("/Sources")` for the top-level folder only), and `*` is a wildcard. Chained calls narrow further.
  public func `in`(_ patterns: String...) -> Scope { self.in(patterns) }

  public func `in`(_ patterns: [String]) -> Scope {
    var scope = self
    scope.inclusions.append(patterns)
    return scope
  }

  /// Without the files that match any of `patterns`: a name matches any folder or file, a path with a slash matches
  /// from the root, and `*` is a wildcard. See ``in(_:)-(String...)``.
  public func excluding(_ patterns: String...) -> Scope { excluding(patterns) }

  public func excluding(_ patterns: [String]) -> Scope {
    var scope = self
    scope.exclusions += patterns
    return scope
  }

  /// Only the files whose text contains one of `texts`, checked on the raw text before parsing, so files that
  /// cannot match are never parsed. ``calls(named:)`` and ``references(to:)-(String...)`` do this for you.
  ///
  /// ```swift
  /// codebase.productionCode.containing("@Reducer").structs.withAttribute("Reducer")
  /// ```
  public func containing(_ texts: String...) -> Scope { containing(texts) }

  public func containing(_ texts: [String]) -> Scope {
    var scope = self
    scope.texts.append(texts)
    return scope
  }

  /// The paths in the scope, relative to the root, sorted.
  public var relativePaths: [String] {
    switch base {
    case .codebase(let codebase, let kind):
      let paths = codebase.relativePaths.filter { path in
        switch kind {
        case .production: !codebase.configuration.isTestCode(path) && includes(path)
        case .test: codebase.configuration.isTestCode(path) && includes(path)
        case .all: includes(path)
        }
      }
      guard !texts.isEmpty else { return paths }
      let texts = texts
      let kept = concurrentMap(paths) { path in
        Self.contains(ParseCache.text(root: codebase.root, relativePath: path) ?? "", texts)
      }
      return zip(paths, kept).filter(\.1).map(\.0)
    case .files(let files):
      return files.filter { includes($0.relativePath) && Self.contains($0.source, texts) }.map(\.relativePath)
    }
  }

  /// The parsed files, sorted by path.
  public var files: [SourceFile] {
    switch base {
    case .codebase(let codebase, _):
      return concurrentMap(relativePaths) { codebase.file($0) }.compactMap { $0 }
    case .files(let files):
      return files.filter { includes($0.relativePath) && Self.contains($0.source, texts) }
    }
  }

  private static func contains(_ source: String, _ texts: [[String]]) -> Bool {
    texts.allSatisfy { group in group.contains { source.contains($0) } }
  }

  private func includes(_ path: String) -> Bool {
    inclusions.allSatisfy { group in group.contains { PathPattern.matches($0, path) } }
      && !exclusions.contains { PathPattern.matches($0, path) }
  }

  // MARK: Declarations

  /// The top-level declarations of every file, built on every core.
  public var topLevelDeclarations: [Declaration] { Array(concurrentMap(files) { $0.declarations }.joined()) }

  /// Every declaration, nested ones included, depth first.
  public var declarations: [Declaration] { topLevelDeclarations.flatMap { [$0] + $0.descendants } }

  /// Every declaration of a kind, nested ones included.
  public func declarations(_ kind: Declaration.Kind) -> [Declaration] { declarations.ofKind(kind) }

  public var structs: [Declaration] { declarations(.struct) }
  public var classes: [Declaration] { declarations(.class) }
  public var enums: [Declaration] { declarations(.enum) }
  public var actors: [Declaration] { declarations(.actor) }
  public var protocols: [Declaration] { declarations(.protocol) }
  public var extensions: [Declaration] { declarations(.extension) }
  public var functions: [Declaration] { declarations(.function) }
  public var variables: [Declaration] { declarations(.variable) }

  // MARK: Nodes

  /// Every node of a type in the scope, anywhere in a file, in file and source order.
  ///
  /// ```swift
  /// scope.nodes(of: ForceUnwrapExprSyntax.self)
  /// scope.nodes(of: FunctionCallExprSyntax.self) { $0.node.calledName == "fatalError" }
  /// ```
  public func nodes<Node: SyntaxProtocol>(of type: Node.Type) -> [Match<Node>] {
    let perFile = concurrentMap(files) { file in file.nodes(of: Node.self).map { Match(node: $0, file: file) } }
    return Array(perFile.joined())
  }

  /// The nodes of a type that satisfy `predicate`.
  public func nodes<Node: SyntaxProtocol>(
    of type: Node.Type,
    where predicate: (Match<Node>) throws -> Bool
  ) rethrows -> [Match<Node>] {
    try nodes(of: type).filter(predicate)
  }

  /// Calls whose called name (``SwiftSyntax/FunctionCallExprSyntax/calledName``) is one of `names`: `print(x)`,
  /// `edit.apply(to:)`, `await withKnownIssue { }`, wherever they are.
  public func calls(named names: String...) -> [Match<FunctionCallExprSyntax>] {
    let set = Set(names)
    return containing(names).nodes(of: FunctionCallExprSyntax.self) { $0.node.calledName.map(set.contains) ?? false }
  }

  /// Code that names one of `names`: an expression (`URLSession.shared`, `.init`'s `Foo`) or a type (`let x: Foo`,
  /// `Foundation.Foo`). Comments and string literals never match.
  public func references(to names: String...) -> [Match<Syntax>] { references(to: Set(names)) }

  public func references(to names: Set<String>) -> [Match<Syntax>] {
    let perFile = concurrentMap(containing(Array(names)).files) { file in
      let expressions = file.nodes(of: DeclReferenceExprSyntax.self)
        .filter { names.contains($0.baseName.text) }.map(Syntax.init)
      let types = file.nodes(of: IdentifierTypeSyntax.self)
        .filter { names.contains($0.name.text) }.map(Syntax.init)
      let memberTypes = file.nodes(of: MemberTypeSyntax.self)
        .filter { names.contains($0.name.text) }.map(Syntax.init)
      return (expressions + types + memberTypes)
        .sorted { $0.position < $1.position }
        .map { Match(node: $0, file: file) }
    }
    return Array(perFile.joined())
  }
}

extension FunctionCallExprSyntax {
  /// `print` in `print(x)`, `apply` in `edit.apply(to: &doc)`, `init` in `.init()`, `Foo` in `Foo<Bar>()`.
  public var calledName: String? {
    var callee = calledExpression
    if let specialized = callee.as(GenericSpecializationExprSyntax.self) { callee = specialized.expression }
    if let member = callee.as(MemberAccessExprSyntax.self) { return member.declName.baseName.text }
    if let reference = callee.as(DeclReferenceExprSyntax.self) { return reference.baseName.text }
    return nil
  }

  /// `edit` in `edit.apply(to:)`; nil for a free call like `print(x)` or an implicit member like `.init()`.
  public var receiver: ExprSyntax? {
    calledExpression.as(MemberAccessExprSyntax.self)?.base
  }
}
