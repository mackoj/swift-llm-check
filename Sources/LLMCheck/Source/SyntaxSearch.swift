import SwiftSyntax

extension SyntaxProtocol {
  /// The first node of a type under this one, in source order, or nil: the first string literal of a `switch` case is
  /// `switchCase.statements.firstDescendant(of: StringLiteralExprSyntax.self)`. The node itself is not a candidate.
  public func firstDescendant<Node: SyntaxProtocol>(of type: Node.Type) -> Node? {
    for child in children(viewMode: .sourceAccurate) {
      if let node = child.as(Node.self) { return node }
      if let node = child.firstDescendant(of: type) { return node }
    }
    return nil
  }

  /// Every node of a type under this one, in source order, nested ones included. The node itself is not one.
  public func descendants<Node: SyntaxProtocol>(of type: Node.Type) -> [Node] {
    children(viewMode: .sourceAccurate).flatMap { child -> [Node] in
      (child.as(Node.self).map { [$0] } ?? []) + child.descendants(of: type)
    }
  }
}

extension TypeSyntax {
  /// The function type this type is, looking through attributes, `?`, `!` and parentheses: `() -> Void` for
  /// `@escaping @Sendable () -> Void`, `((Int) -> Void)?` and `(@MainActor () -> Void)`. Nil for any other type.
  public var closureType: FunctionTypeSyntax? {
    if let function = self.as(FunctionTypeSyntax.self) { return function }
    return wrappedType?.closureType
  }

  /// Whether `@name` is on this type or on a type it wraps, down to the closure or named type: true for
  /// `hasAttribute("Sendable")` on `(@Sendable () -> Void)?`. `name` is written without `@`.
  public func hasAttribute(_ name: String) -> Bool {
    if let attributed = self.as(AttributedTypeSyntax.self),
      attributed.attributes.contains(where: { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == name })
    {
      return true
    }
    return wrappedType?.hasAttribute(name) ?? false
  }

  /// The type under one attribute list, `?`, `!` or pair of parentheses; nil for anything else.
  private var wrappedType: TypeSyntax? {
    if let attributed = self.as(AttributedTypeSyntax.self) { return attributed.baseType }
    if let optional = self.as(OptionalTypeSyntax.self) { return optional.wrappedType }
    if let optional = self.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) { return optional.wrappedType }
    if let tuple = self.as(TupleTypeSyntax.self), tuple.elements.count == 1, let only = tuple.elements.first,
      only.firstName == nil
    {
      return only.type
    }
    return nil
  }
}
