import Foundation
import LLMCheck
import SwiftSyntax

/// The detectors, separate from the codebase so `DetectorTests` can run them on snippets.
enum Detect {
  /// The modules `Sources` may import: the dependency budget.
  static let allowedImports: Set<String> = [
    "Foundation", "Dispatch", "SwiftSyntax", "SwiftParser", "Testing", "XCTest",
  ]

  /// Imports of any other module, in `#if` blocks too.
  static func importsOutsideTheBudget(in scope: Scope) -> [Match<ImportDeclSyntax>] {
    scope.imports.filter { !allowedImports.contains($0.node.moduleName) }
  }

  /// `import XCTest` that is not inside an `#if canImport(XCTest)` clause.
  static func unconditionalXCTestImports(in scope: Scope) -> [Match<ImportDeclSyntax>] {
    scope.imports(of: "XCTest").filter { match in
      !match.node.enclosingIfConfigClauses.contains { $0.ifCondition == "canImport(XCTest)" && !$0.isElse }
    }
  }

  /// `@_exported import`.
  static func reexports(in scope: Scope) -> [Match<ImportDeclSyntax>] {
    scope.imports.filter { match in
      match.node.attributes.contains { $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "_exported" }
    }
  }

  /// Public or open structs, enums and classes that are not `Sendable`. A conformance counts on the type or an
  /// extension of it, directly or through a protocol that refines `Sendable` (`Error`, or one declared in the scope).
  static func nonSendablePublicTypes(in scope: Scope) -> [Declaration] {
    var sendable: Set<String> = ["Sendable", "Error"]
    var protocols = scope.protocols
    while let refining = protocols.firstIndex(where: { conformsTo(sendable, $0.inheritance) }) {
      sendable.insert(protocols.remove(at: refining).qualifiedName)
    }
    let extensions = scope.extensions
    return (scope.structs + scope.enums + scope.classes).filter { type in
      guard type.hasModifier("public") || type.hasModifier("open") else { return false }
      let declarations = [type] + extensions.filter { $0.name == type.qualifiedName }
      return !declarations.contains { conformsTo(sendable, $0.inheritance) }
    }
  }

  private static func conformsTo(_ names: Set<String>, _ inheritance: [String]) -> Bool {
    inheritance.contains { written in
      let name = written.replacingOccurrences(of: "@unchecked", with: "").trimmingCharacters(in: .whitespaces)
      return names.contains(name) || names.contains(String(name.prefix { $0 != "<" }))
    }
  }

  /// `@unchecked Sendable` conformances with no comment on the declaration that makes them.
  static func uncommentedUncheckedSendable(in scope: Scope) -> [Match<AttributeSyntax>] {
    scope.containing("@unchecked").nodes(of: AttributeSyntax.self) { match in
      guard match.node.attributeName.trimmedDescription == "unchecked" else { return false }
      let declaration = sequence(first: Syntax(match.node), next: \.parent).first { $0.is(DeclSyntax.self) }
      return declaration?.attachedComments.isEmpty ?? true
    }
  }

  /// Types that lock, wait or schedule work: every one of them belongs in `Support/Locked.swift`.
  static let synchronizationTypes: Set<String> = [
    "NSLock", "NSRecursiveLock", "NSCondition", "NSConditionLock", "Mutex", "DispatchQueue", "DispatchSemaphore",
    "DispatchGroup", "OperationQueue", "os_unfair_lock", "pthread_mutex_t", "pthread_rwlock_t",
  ]

  /// The one file that may lock, wait or schedule work.
  static let lockedFile = "Sources/LLMCheck/Support/Locked.swift"

  /// Uses of ``synchronizationTypes`` outside ``lockedFile``, as an expression (`DispatchQueue.main`) or a type
  /// (`let lock: NSLock`).
  static func synchronizationOutsideLocked(in scope: Scope) -> [Match<Syntax>] {
    scope.excluding(lockedFile).references(to: synchronizationTypes)
  }

  /// `print(x)`, `debugPrint(x)`, `dump(x)`: free calls only, so `printer.print(x)` passes.
  static func printing(in scope: Scope) -> [Match<FunctionCallExprSyntax>] {
    scope.calls(named: "print", "debugPrint", "dump").filter {
      $0.node.calledExpression.is(DeclReferenceExprSyntax.self)
    }
  }

  /// The one test file that may import XCTest.
  static let xcTestFile = "XCTestExpectationsTests.swift"

  /// `import XCTest` in any other test file.
  static func xcTestImports(in scope: Scope) -> [Match<ImportDeclSyntax>] {
    scope.excluding(xcTestFile).imports(of: "XCTest")
  }

  /// `withKnownIssue { … }` with neither a reason (an unlabelled string first) nor a `matching:` closure.
  static func unexplainedKnownIssues(in scope: Scope) -> [Match<FunctionCallExprSyntax>] {
    scope.calls(named: "withKnownIssue").filter { call in
      let explained =
        call.node.arguments.first.map { $0.label == nil && $0.expression.is(StringLiteralExprSyntax.self) } ?? false
      let matching =
        call.node.additionalTrailingClosures.contains { $0.label.text == "matching" }
        || call.node.argument(labeled: "matching") != nil
      return !explained && !matching
    }
  }
}
