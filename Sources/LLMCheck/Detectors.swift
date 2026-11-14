import Foundation
import SwiftSyntax

// The detectors that every adopting repository wrote for itself, with the same detector tests. Each returns the
// matches; the `Rule` they break stays the repository's own, worded with its reasons.

extension Scope {
  // MARK: Tests

  /// `import XCTest`, in `#if` blocks too: for "tests use Swift Testing".
  public var xcTestImports: [Match<ImportDeclSyntax>] { imports(of: "XCTest") }

  /// The `.disabled` trait in a `@Test` or `@Suite` attribute: `@Test(.disabled("flaky"))`,
  /// `@Suite(.serialized, .disabled(if: isCI))`. A `.disabled(…)` anywhere else, such as an enum case
  /// `state = .disabled(reason)`, does not match.
  public var disabledTests: [Match<FunctionCallExprSyntax>] {
    calls(named: "disabled").filter { call in
      call.node.receiver == nil && call.node.calledExpression.is(MemberAccessExprSyntax.self)
        && Self.isInTestingAttribute(call.node)
    }
  }

  /// `withKnownIssue { … }` that does not say what the known issue is: its first argument is not an unlabelled,
  /// non-empty string literal. `withKnownIssue("bug 12: sync drops the error") { … }` passes.
  public var unexplainedKnownIssues: [Match<FunctionCallExprSyntax>] {
    calls(named: "withKnownIssue").filter { !Self.startsWithReason($0.node) }
  }

  /// `XCTExpectFailure` that does not say why it is expected to fail: its first argument is not an unlabelled,
  /// non-empty string literal. `XCTExpectFailure("bug 12: sync drops the error")` passes.
  public var unexplainedExpectedFailures: [Match<FunctionCallExprSyntax>] {
    calls(named: "XCTExpectFailure").filter { !Self.startsWithReason($0.node) }
  }

  // MARK: Safety

  /// The `@unchecked` of an `@unchecked Sendable` conformance whose declaration has no comment saying why it is safe.
  ///
  /// A comment counts when it is a `//` or `/* */` comment, not a `///` doc comment (which describes the type to its
  /// users), in one of these places:
  ///
  /// ```swift
  /// // Every access to `storage` holds `lock`.                ← just above, no blank line between
  /// final class Cache: @unchecked Sendable {  // or here       ← at the end of the line that opens the body
  ///   // or here, before the first member
  /// ```
  ///
  /// `// MARK:` comments do not count.
  public var uncommentedUncheckedSendable: [Match<AttributeSyntax>] {
    containing("@unchecked").nodes(of: AttributeSyntax.self) { match in
      guard match.node.attributeName.trimmedDescription == "unchecked" else { return false }
      guard
        let declaration = sequence(first: Syntax(match.node), next: \.parent).first(where: { $0.is(DeclSyntax.self) })
      else { return true }
      return !UncheckedJustification.isExplained(declaration)
    }
  }

  /// `try!`, which traps on any error.
  public var forcedTries: [Match<TryExprSyntax>] {
    containing("try!").nodes(of: TryExprSyntax.self) {
      $0.node.questionOrExclamationMark?.tokenKind == .exclamationMark
    }
  }

  /// `try?`, which turns any error into `nil`. With ``forcedTries``, the errors a rule such as "errors are never
  /// swallowed" looks for: `scope.optionalTries + scope.forcedTries`.
  public var optionalTries: [Match<TryExprSyntax>] {
    containing("try?").nodes(of: TryExprSyntax.self) {
      $0.node.questionOrExclamationMark?.tokenKind == .postfixQuestionMark
    }
  }

  /// `x as! T`, which traps when the cast fails. The match is the `as!` itself.
  ///
  /// SwiftParser leaves operator expressions unfolded, so `let name = value as! String` holds an
  /// `UnresolvedAsExprSyntax`, not an `AsExprSyntax` (README, "Unfolded expressions"). This finds both.
  public var forcedCasts: [Match<Syntax>] {
    let perFile = concurrentMap(containing("as!").files) { file in
      file.indexNodes([NodeQuery(UnresolvedAsExprSyntax.self), NodeQuery(AsExprSyntax.self)])
      let unfolded = file.nodes(of: UnresolvedAsExprSyntax.self)
        .filter { $0.questionOrExclamationMark?.tokenKind == .exclamationMark }.map(Syntax.init)
      let folded = file.nodes(of: AsExprSyntax.self)
        .filter { $0.questionOrExclamationMark?.tokenKind == .exclamationMark }.map(Syntax.init)
      return (unfolded + folded).sorted { $0.position < $1.position }.map { Match(node: $0, file: file) }
    }
    return Array(perFile.joined())
  }

  /// `value!`, which traps on `nil`. `try!`, `as!` and `!=` are not force unwraps.
  public var forceUnwraps: [Match<ForceUnwrapExprSyntax>] {
    containing("!").nodes(of: ForceUnwrapExprSyntax.self)
  }

  // MARK: Helpers

  /// Whether the first argument is an unlabelled string literal with some text in it.
  private static func startsWithReason(_ call: FunctionCallExprSyntax) -> Bool {
    guard let first = call.arguments.first, first.label == nil,
      let literal = first.expression.as(StringLiteralExprSyntax.self)
    else { return false }
    return !literal.segments.allSatisfy { $0.as(StringSegmentSyntax.self)?.content.text.isEmpty ?? false }
  }

  /// Whether the node is an argument of a `@Test` or `@Suite` attribute.
  private static func isInTestingAttribute(_ node: some SyntaxProtocol) -> Bool {
    sequence(first: Syntax(node), next: \.parent).lazy.compactMap { $0.as(AttributeSyntax.self) }.first.map {
      ["Test", "Suite", "Testing.Test", "Testing.Suite"].contains($0.attributeName.trimmedDescription)
    } ?? false
  }
}

/// Where the comment that justifies an `@unchecked Sendable` may be.
enum UncheckedJustification {
  static func isExplained(_ declaration: Syntax) -> Bool {
    // The comments just above the declaration, up to a blank line.
    var pieces = Array(declaration.leadingTrivia.pieces.reversed().prefix { !isBlankLine($0) })
    if let group = declaration.asProtocol(DeclGroupSyntax.self) {
      // The end of the line that opens the body, then the lines before the first member, up to a blank line.
      let brace = group.memberBlock.leftBrace
      pieces += brace.trailingTrivia.pieces
      if let next = brace.nextToken(viewMode: .sourceAccurate) {
        pieces += next.leadingTrivia.pieces.prefix { !isBlankLine($0) }
        // `{}` on one line: the comment after the closing brace.
        if next.id == group.memberBlock.rightBrace.id { pieces += next.trailingTrivia.pieces }
      }
    }
    return pieces.contains(where: isJustification)
  }

  private static func isBlankLine(_ piece: TriviaPiece) -> Bool {
    switch piece {
    case .newlines(let count), .carriageReturns(let count), .carriageReturnLineFeeds(let count): count > 1
    default: false
    }
  }

  private static func isJustification(_ piece: TriviaPiece) -> Bool {
    switch piece {
    case .lineComment(let text): !text.dropFirst(2).trimmingCharacters(in: .whitespaces).hasPrefix("MARK:")
    case .blockComment: true
    default: false
    }
  }
}
