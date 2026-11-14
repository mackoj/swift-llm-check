import SwiftSyntax

extension SyntaxProtocol {
  /// The comments that belong to this node: those written just before it (its leading trivia) and one at the end of
  /// its last line. Returned as written, with their `//` or `/* */`.
  ///
  /// ```swift
  /// // Why the store is not exhaustive.     ← leading
  /// store.exhaustivity = .off  // or here   ← trailing
  /// ```
  public var attachedComments: [String] {
    leadingComments + trailingComments
  }

  /// The comments before the node, on the lines above it or before it on its line.
  public var leadingComments: [String] {
    leadingTrivia.pieces.compactMap { $0.commentText }
  }

  /// A comment after the node on its last line. Swift puts it in the node's trailing trivia or, past the end of a
  /// statement, in the next token's leading trivia up to the line break.
  public var trailingComments: [String] {
    var pieces = Array(trailingTrivia.pieces)
    if !pieces.contains(where: { $0.isNewline }),
      let next = lastToken(viewMode: .sourceAccurate)?.nextToken(viewMode: .sourceAccurate)
    {
      pieces += next.leadingTrivia.pieces.prefix { !$0.isNewline }
    }
    return pieces.compactMap { $0.commentText }
  }
}

extension TriviaPiece {
  /// The text of a comment piece, or nil.
  var commentText: String? {
    switch self {
    case .lineComment(let text), .blockComment(let text), .docLineComment(let text), .docBlockComment(let text):
      text
    default:
      nil
    }
  }
}
