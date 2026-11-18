import Foundation
import SwiftSyntax

extension Scope {
  /// Typed `createTemporaryTrigger` calls lexically inside a `registerMigration` call. Temporary triggers disappear
  /// when the connection closes, but a migration runs once. Install them during connection setup instead.
  ///
  /// This is a syntax check: raw SQL, helper calls and aliases are not followed. Scope it to SQLiteData code.
  public var temporaryTriggersInMigrations: [Match<FunctionCallExprSyntax>] {
    calls(named: "createTemporaryTrigger").filter {
      SQLiteSyntax.isInsideCall($0.node, named: "registerMigration")
    }
  }

  /// Typed `createTemporaryView` calls lexically inside `registerMigration`. A temporary view needed at runtime
  /// must be installed on every connection that queries it, because it disappears when the connection closes.
  /// A view used only as a migration's own transformation helper can be legitimate. This detector reports the
  /// placement; the adopting rule selects which migrations or views must remain available after launch.
  /// Raw SQL, aliases and separately declared helpers are not followed.
  public var temporaryViewsInMigrations: [Match<FunctionCallExprSyntax>] {
    calls(named: "createTemporaryView").filter {
      SQLiteSyntax.isInsideCall($0.node, named: "registerMigration")
    }
  }

  /// `Date()`, `Date.now` and `UUID()` inside typed `createTemporaryTrigger` arguments, including Foundation-qualified
  /// spellings. Those Swift values are evaluated when the SQL is built, not each time the trigger fires. Use SQL
  /// functions or a registered database function for values that must change on each invocation.
  ///
  /// Explicit date/UUID initializers, dependency values, aliases, raw SQL and separately declared helpers are not
  /// analyzed. Calls nested in a function/type declaration are not treated as trigger-building expressions.
  public var swiftValuesInSQLTriggers: [Match<Syntax>] {
    swiftValues(inSQLBuilder: "createTemporaryTrigger")
  }

  /// `Date()`, `Date.now` and `UUID()` evaluated directly while building a typed `createTemporaryView`. Like trigger
  /// builders, these expressions produce values at installation time, not when a later query reads the view.
  /// Foundation-qualified spellings count. Explicit date/UUID initializers, previously built queries, custom
  /// factories and raw SQL require review. Use SQL functions for values that should change on each query.
  public var swiftValuesInSQLViews: [Match<Syntax>] {
    swiftValues(inSQLBuilder: "createTemporaryView")
  }

  /// JSON/JSONB `@Column(as:)` representations directly owned by a `@Table` struct explicitly conforming to `FTS5`.
  /// Module-qualified Table, Column and FTS5 names count. Nested non-FTS types and ordinary table columns do not.
  ///
  /// This is an opt-in document policy, not an invalid-SQL detector: JSON text can be indexed deliberately, and
  /// opaque metadata can be UNINDEXED in the actual schema. Index membership is not inferred from Swift syntax.
  /// Conformance in an extension, type aliases and custom representation types are not resolved.
  public var jsonEncodedFTS5Columns: [Declaration] {
    containing("FTS5").structs.filter { type in
      type.attributes.contains { $0.split(separator: ".").last == "Table" }
        && type.inheritance.contains { $0.split(separator: ".").last == "FTS5" }
    }.flatMap { type in
      type.variables.filter { variable in
        variable.attributes.filter { $0.split(separator: ".").last == "Column" }.contains { name in
          variable.attributes(name).contains { attribute in
            guard case .argumentList(let arguments) = attribute.arguments,
              let representation = arguments.first(where: { $0.label?.text == "as" })?.expression
                .as(MemberAccessExprSyntax.self),
              representation.declName.baseName.text == "self",
              let member = representation.base?.as(MemberAccessExprSyntax.self)
            else { return false }
            return ["JSONRepresentation", "JSONBRepresentation"].contains(member.declName.baseName.text)
          }
        }
      }
    }
  }

  private func swiftValues(inSQLBuilder name: String) -> [Match<Syntax>] {
    let scope = containing(name)
    let calls = scope.calls(named: "Date", "UUID").filter {
      $0.node.arguments.isEmpty && !$0.node.passesClosure
        && ($0.node.receiver == nil || $0.node.receiver?.trimmedDescription == "Foundation")
        && SQLiteSyntax.isInsideCall($0.node, named: name)
    }
    let members = scope.nodes(of: MemberAccessExprSyntax.self) {
      $0.node.declName.baseName.text == "now"
        && ["Date", "Foundation.Date"].contains($0.node.base?.trimmedDescription ?? "")
        && SQLiteSyntax.isInsideCall($0.node, named: name)
    }
    return (calls.map(\.erased) + members.map(\.erased)).sorted {
      ($0.file.relativePath, $0.node.position.utf8Offset) < ($1.file.relativePath, $1.node.position.utf8Offset)
    }
  }

  /// Stored instance `@Fetch`, `@FetchAll`, `@FetchOne` and `@Dependency` properties directly owned by an
  /// `@Observable` class without `@ObservationIgnored`. These wrappers implement their own access tracking.
  /// Module-qualified attributes count too. Nested types, local variables and static/computed properties are
  /// considered separately; `@ObservableState` belongs to TCA and is not checked by this detector.
  public var unignoredObservablePropertyWrappers: [Match<VariableDeclSyntax>] {
    containing("Observable").nodes(of: VariableDeclSyntax.self) { match in
      let variable = match.node
      let names = SQLiteSyntax.attributes(variable.attributes)
      guard !names.contains("ObservationIgnored"),
        !names.isDisjoint(with: ["Fetch", "FetchAll", "FetchOne", "Dependency"]),
        !variable.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }),
        variable.bindings.contains(where: { binding in
          guard let block = binding.accessorBlock else { return true }
          guard case .accessors(let accessors) = block.accessors else { return false }
          return accessors.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
        })
      else { return false }
      // Only member-list and conditional-compilation wrappers may separate the property from its owning class.
      for ancestor in sequence(first: Syntax(variable).parent, next: { $0?.parent }) {
        guard let ancestor else { break }
        if let owner = ancestor.as(ClassDeclSyntax.self) {
          return SQLiteSyntax.attributes(owner.attributes).contains("Observable")
        }
        if (ancestor.is(DeclSyntax.self) && !ancestor.is(IfConfigDeclSyntax.self))
          || ancestor.is(ClosureExprSyntax.self)
          || ancestor.is(AccessorDeclSyntax.self)
        {
          return false
        }
      }
      return false
    }
  }

  /// A member `.snippet(open, close, ellipsis, count)` whose fourth unlabelled argument is an integer literal outside
  /// SQLite FTS5's `1...64` token limit. Signed and radix-prefixed integer literals are supported. Dynamic expressions
  /// are left to runtime tests. Scope this to StructuredQueries code: receiver types are not resolved, and unrelated
  /// methods with the same four-argument spelling would also match.
  public var invalidFTS5SnippetTokenCounts: [Match<FunctionCallExprSyntax>] {
    calls(named: "snippet").filter { match in
      let call = match.node
      guard call.receiver != nil, call.arguments.count == 4,
        call.arguments.allSatisfy({ $0.label == nil }), let last = call.arguments.last,
        let count = SQLiteSyntax.integer(last.expression)
      else { return false }
      return !(1...64).contains(count)
    }
  }
}

/// Syntax shared by the SQLiteData detectors, without linking SQLiteData or resolving symbols.
private enum SQLiteSyntax {
  static func isInsideCall(_ node: some SyntaxProtocol, named name: String) -> Bool {
    var current = Syntax(node).parent
    while let ancestor = current {
      if let call = ancestor.as(FunctionCallExprSyntax.self), call.calledName == name { return true }
      if ancestor.is(FunctionDeclSyntax.self) || ancestor.is(InitializerDeclSyntax.self)
        || ancestor.is(AccessorDeclSyntax.self) || ancestor.isProtocol(DeclGroupSyntax.self)
      {
        return false
      }
      current = ancestor.parent
    }
    return false
  }

  static func attributes(_ list: AttributeListSyntax) -> Set<String> {
    Set(
      list.compactMap {
        $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription.split(separator: ".").last.map(String.init)
      })
  }

  static func integer(_ expression: ExprSyntax) -> Int? {
    if let prefix = expression.as(PrefixOperatorExprSyntax.self), ["-", "+"].contains(prefix.operator.text),
      let value = integer(prefix.expression)
    {
      return prefix.operator.text == "-" ? -value : value
    }
    guard let literal = expression.as(IntegerLiteralExprSyntax.self) else { return nil }
    let text = literal.literal.text.replacingOccurrences(of: "_", with: "")
    for (prefix, radix) in [("0x", 16), ("0o", 8), ("0b", 2)] where text.hasPrefix(prefix) {
      return Int(text.dropFirst(2), radix: radix)
    }
    return Int(text)
  }
}
