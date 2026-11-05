import LLMCheck
import Testing

/// This file imports LLMCheck and Testing but not SwiftSyntax, like a rule file that only uses the helpers.
@Suite struct ImportTests {
  @Test func sourceLocationIsTestingsWithoutQualification() {
    // Ambiguous with SwiftSyntax.SourceLocation if LLMCheck re-exported SwiftSyntax.
    let here: SourceLocation = #_sourceLocation
    #expect(here.fileName == "ImportTests.swift")
  }

  @Test func helpersWorkWithoutImportingSwiftSyntax() {
    let calls = Scope(files: [file("print(1); log.print(2)")]).calls(named: "print")
    #expect(calls.map { $0.node.receiver == nil } == [true, false])
    #expect(calls.map(\.node.calledName) == ["print", "print"])
  }
}
