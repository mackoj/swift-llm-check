import SwiftSyntax

/// A declaration: a type, an extension, a function, a variable, an enum case or a type alias.
///
/// Declarations nest: a struct's ``children`` are its members, and each member's ``parent`` is the struct. Members
/// inside `#if` blocks count as members. Local declarations inside function bodies are not listed; search them with
/// ``Scope/nodes(of:where:)``.
public final class Declaration: Finding, @unchecked Sendable {
  // @unchecked: `parent` and `children` are set while the file's declarations are built, before any caller sees
  // them, and never change afterwards.

  public enum Kind: String, Sendable, Hashable, CaseIterable {
    case `struct`, `class`, `enum`, actor, `protocol`, `extension`, function, initializer, variable, enumCase,
      `typealias`
  }

  public let kind: Kind
  /// The declared name. For an extension, the extended type (`Foo`, `Foo.Bar`); for an initializer, `init`.
  public let name: String
  /// Attribute names without `@` or arguments: `Reducer`, `MainActor`, `ObservableState`.
  public let attributes: [String]
  /// `public`, `static`, `private(set)`, `nonisolated`…
  public let modifiers: [String]
  /// The inheritance clause as written: `Equatable`, `ViewAction`, `DependencyKey`, `Foo<Bar>`.
  public let inheritance: [String]
  /// The node: `StructDeclSyntax`, `FunctionDeclSyntax`… For a variable, its `PatternBindingSyntax`; for an enum case,
  /// its `EnumCaseElementSyntax`.
  public let syntax: Syntax
  public let file: SourceFile
  public let location: Location
  public private(set) weak var parent: Declaration?
  public private(set) var children: [Declaration] = []

  init(
    kind: Kind, name: String, attributes: [String], modifiers: [String], inheritance: [String], syntax: Syntax,
    introducer: TokenSyntax, file: SourceFile, parent: Declaration?
  ) {
    self.kind = kind
    self.name = name
    self.attributes = attributes
    self.modifiers = modifiers
    self.inheritance = inheritance
    self.syntax = syntax
    self.file = file
    self.location = file.location(of: introducer)
    self.parent = parent
  }

  func append(_ child: Declaration) { children.append(child) }

  /// `Feature.State` for `State` nested in `Feature`.
  public var qualifiedName: String { parent.map { "\($0.qualifiedName).\(name)" } ?? name }

  public var snippet: String { file.line(location.line) }

  public var declarationNames: [String] { [qualifiedName] + (parent?.declarationNames ?? []) }

  /// Whether the declaration has `@name` (without the `@`).
  public func hasAttribute(_ name: String) -> Bool { attributes.contains(name) }

  /// Whether the inheritance clause names `type`, with or without generic arguments, and through an attribute:
  /// `@unchecked Sendable` inherits from `Sendable`, `@retroactive Identifiable` from `Identifiable`.
  public func inherits(from type: String) -> Bool {
    inheritance.contains { written in
      var name = Substring(written)
      while name.hasPrefix("@"), let space = name.firstIndex(of: " ") {
        name = name[space...].drop { $0 == " " }
      }
      return name == type || name.hasPrefix(type + "<")
    }
  }

  /// Whether the declaration has a modifier: `public`, `static`…
  public func hasModifier(_ name: String) -> Bool { modifiers.contains(name) }

  /// The direct children of a kind.
  public func children(_ kind: Kind) -> [Declaration] { children.filter { $0.kind == kind } }

  /// This declaration and everything nested in it, depth first.
  public var descendants: [Declaration] { children.flatMap { [$0] + $0.descendants } }

  public var structs: [Declaration] { children(.struct) }
  public var classes: [Declaration] { children(.class) }
  public var enums: [Declaration] { children(.enum) }
  public var functions: [Declaration] { children(.function) }
  public var variables: [Declaration] { children(.variable) }
  /// An enum's cases, one per element: `case a, b` gives two.
  public var cases: [Declaration] { children(.enumCase) }
}

extension Array where Element == Declaration {
  public func ofKind(_ kind: Declaration.Kind) -> [Declaration] { filter { $0.kind == kind } }
  public func named(_ names: String...) -> [Declaration] { filter { names.contains($0.name) } }
  public func withAttribute(_ name: String) -> [Declaration] { filter { $0.hasAttribute(name) } }
  public func inheriting(from type: String) -> [Declaration] { filter { $0.inherits(from: type) } }
  public func withModifier(_ name: String) -> [Declaration] { filter { $0.hasModifier(name) } }
}

enum DeclarationBuilder {
  static func declarations(in file: SourceFile) -> [Declaration] {
    var result: [Declaration] = []
    collect(file.syntax.statements.map { Syntax($0.item) }, file: file, parent: nil, into: &result)
    return result
  }

  /// Adds the declarations among `nodes` (statements or members), looking inside `#if` clauses.
  private static func collect(
    _ nodes: [Syntax], file: SourceFile, parent: Declaration?, into result: inout [Declaration]
  ) {
    for node in nodes {
      if let ifConfig = node.as(IfConfigDeclSyntax.self) {
        for clause in ifConfig.clauses {
          switch clause.elements {
          case .statements(let items): collect(items.map { Syntax($0.item) }, file: file, parent: parent, into: &result)
          case .decls(let members): collect(members.map { Syntax($0.decl) }, file: file, parent: parent, into: &result)
          default: break
          }
        }
        continue
      }
      for declaration in make(node, file: file, parent: parent) {
        result.append(declaration)
        if let members = node.asProtocol(DeclGroupSyntax.self)?.memberBlock.members {
          var children: [Declaration] = []
          collect(members.map { Syntax($0.decl) }, file: file, parent: declaration, into: &children)
          children.forEach(declaration.append)
        }
      }
    }
  }

  private static func make(_ node: Syntax, file: SourceFile, parent: Declaration?) -> [Declaration] {
    func one(
      _ kind: Declaration.Kind, _ name: String, _ introducer: TokenSyntax, attributes: AttributeListSyntax,
      modifiers: DeclModifierListSyntax, inheritance: InheritanceClauseSyntax? = nil
    ) -> [Declaration] {
      [
        Declaration(
          kind: kind, name: name, attributes: names(attributes, in: file),
          modifiers: modifiers.map { file.text(of: $0) },
          inheritance: inheritance?.inheritedTypes.map { file.text(of: $0.type) } ?? [], syntax: node,
          introducer: introducer, file: file, parent: parent)
      ]
    }

    switch node.as(SyntaxEnum.self) {
    case .structDecl(let d):
      return one(
        .struct, d.name.text, d.structKeyword, attributes: d.attributes, modifiers: d.modifiers,
        inheritance: d.inheritanceClause)
    case .classDecl(let d):
      return one(
        .class, d.name.text, d.classKeyword, attributes: d.attributes, modifiers: d.modifiers,
        inheritance: d.inheritanceClause)
    case .enumDecl(let d):
      return one(
        .enum, d.name.text, d.enumKeyword, attributes: d.attributes, modifiers: d.modifiers,
        inheritance: d.inheritanceClause)
    case .actorDecl(let d):
      return one(
        .actor, d.name.text, d.actorKeyword, attributes: d.attributes, modifiers: d.modifiers,
        inheritance: d.inheritanceClause)
    case .protocolDecl(let d):
      return one(
        .protocol, d.name.text, d.protocolKeyword, attributes: d.attributes, modifiers: d.modifiers,
        inheritance: d.inheritanceClause)
    case .extensionDecl(let d):
      return one(
        .extension, file.text(of: d.extendedType), d.extensionKeyword, attributes: d.attributes,
        modifiers: d.modifiers, inheritance: d.inheritanceClause)
    case .functionDecl(let d):
      return one(.function, d.name.text, d.funcKeyword, attributes: d.attributes, modifiers: d.modifiers)
    case .initializerDecl(let d):
      return one(.initializer, "init", d.initKeyword, attributes: d.attributes, modifiers: d.modifiers)
    case .typeAliasDecl(let d):
      return one(.typealias, d.name.text, d.typealiasKeyword, attributes: d.attributes, modifiers: d.modifiers)
    case .variableDecl(let d):
      return d.bindings.map { binding in
        Declaration(
          kind: .variable, name: file.text(of: binding.pattern), attributes: names(d.attributes, in: file),
          modifiers: d.modifiers.map { file.text(of: $0) }, inheritance: [], syntax: Syntax(binding),
          introducer: binding.pattern.firstToken(viewMode: .sourceAccurate) ?? d.bindingSpecifier, file: file,
          parent: parent)
      }
    case .enumCaseDecl(let d):
      return d.elements.map { element in
        Declaration(
          kind: .enumCase, name: element.name.text, attributes: names(d.attributes, in: file),
          modifiers: d.modifiers.map { file.text(of: $0) }, inheritance: [], syntax: Syntax(element),
          introducer: element.name, file: file, parent: parent)
      }
    default:
      return []
    }
  }

  private static func names(_ attributes: AttributeListSyntax, in file: SourceFile) -> [String] {
    attributes.compactMap { element in
      guard case .attribute(let attribute) = element else { return nil }
      let name = file.text(of: attribute.attributeName)
      return name.split(separator: "<").first.map(String.init) ?? name
    }
  }
}
