@testable import LLMCheck
import SwiftSyntax
import Testing

@Suite struct SourceTextTests {
  @Test(arguments: [
    """
    @available(macOS 14, *) @MainActor
    public private(set) var é: [String: Int] = [:] // trailing
    extension Foo<Bar>.Baz: @unchecked Sendable, Collection where Element == Int {}
    """,
    "struct A {\r\n  /// doc 🙂\r\n  nonisolated(unsafe) static let (x, y) = (1, 2)\r\n}\r\n",
    "func f() { #if DEBUG\n  print(\"日本\")\n#endif }",
  ])
  func textIsTheTrimmedDescription(source: String) {
    let file = file(source)
    for node in file.nodes(of: Syntax.self) {
      #expect(file.text(of: node) == node.trimmedDescription)
    }
  }

  @Test func textSearchFindsWhatStringContainsFinds() {
    let sources = [
      "", "print(x)", "let é = \"e\u{301}\" // 🙂 fatalError(", "a\r\nb", String(repeating: "ab", count: 5_000) + "abc",
    ]
    let texts = ["", "print", "print(x)", "fatalError(", "e", "abc", "b\r", "\n", "x)", "zzz", "é", "🙂"]
    for source in sources {
      for text in texts where source.contains(text) {
        #expect(TextSearch.contains(source, text), "\(text) in \(source.prefix(20))")
      }
    }
    #expect(!TextSearch.contains("print(x)", "printf"))
    #expect(!TextSearch.contains("", "a"))
  }
}
