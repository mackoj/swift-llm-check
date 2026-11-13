import LLMCheck
import Testing

/// Each detector on snippets: it finds what its rule forbids and nothing its rule allows.
@Suite struct DetectorTests {
  func scope(_ source: String, at path: String = "Sources/LLMCheck/File.swift") -> Scope {
    Scope(files: [SourceFile(path: path, source: source)])
  }

  @Test func importsOutsideTheBudgetAreFound() {
    let found = Detect.importsOutsideTheBudget(
      in: scope(
        """
        import Foundation
        import SwiftSyntaxBuilder
        #if canImport(Yams)
          import Yams
        #endif
        import struct SwiftOperators.OperatorTable
        """))
    #expect(found.map(\.location.line) == [2, 4, 6])
  }

  @Test func theBudgetPasses() {
    let found = Detect.importsOutsideTheBudget(
      in: scope(
        """
        import Dispatch
        import Foundation
        import SwiftParser
        import struct SwiftSyntax.Syntax
        import Testing
        #if canImport(XCTest)
          import XCTest
        #endif
        // import Yams
        """))
    #expect(found.isEmpty)
  }

  @Test func unconditionalXCTestImportsAreFound() {
    let found = Detect.unconditionalXCTestImports(
      in: scope(
        """
        import XCTest
        #if canImport(XCTest)
        #else
          import XCTest
        #endif
        #if DEBUG
          import XCTest
        #endif
        """))
    #expect(found.map(\.location.line) == [1, 4, 7])
  }

  @Test func conditionalXCTestImportPasses() {
    let found = Detect.unconditionalXCTestImports(
      in: scope(
        """
        #if canImport(XCTest)
          import XCTest
        #endif
        """))
    #expect(found.isEmpty)
  }

  @Test func reexportsAreFound() {
    let found = Detect.reexports(
      in: scope(
        """
        @_exported import SwiftSyntax
        import SwiftParser
        @_exported import struct Foundation.URL
        @_implementationOnly import Dispatch
        """))
    #expect(found.map(\.location.line) == [1, 3])
  }

  @Test func nonSendablePublicTypesAreFound() {
    let found = Detect.nonSendablePublicTypes(
      in: scope(
        """
        public struct Report {}
        public final class Cache {}
        public enum Kind: String, CaseIterable {}
        struct Internal {}
        """))
    #expect(found.map(\.name) == ["Report", "Kind", "Cache"])
  }

  @Test func sendablePublicTypesPass() {
    let found = Detect.nonSendablePublicTypes(
      in: scope(
        """
        public protocol Finding: Sendable {}
        public protocol Located: Finding {}
        public struct Location: Sendable, Hashable {}
        public struct Violation: Finding {}
        public struct Spot: Located {}
        public struct Match<Node>: Finding {}
        public struct Failure: Error {}
        public final class Declaration: Finding, @unchecked Sendable {}
        public struct Box<Value> {}
        extension Box: Sendable where Value: Sendable {}
        """))
    #expect(found.isEmpty)
  }

  @Test func uncommentedUncheckedSendableIsFound() {
    let found = Detect.uncommentedUncheckedSendable(in: scope("final class Cache: @unchecked Sendable {}"))
    #expect(found.map(\.location.line) == [1])
  }

  @Test func commentedUncheckedSendablePasses() {
    let found = Detect.uncommentedUncheckedSendable(
      in: scope(
        """
        /// A value behind a lock.
        final class Locked<Value>: @unchecked Sendable {}
        public final class Declaration: @unchecked Sendable {
          // @unchecked: `parent` is set before any caller sees it.
        }
        """))
    #expect(found.count == 1, "a comment inside the body is not on the declaration")
  }

  @Test func synchronizationOutsideLockedIsFound() {
    let found = Detect.synchronizationOutsideLocked(
      in: scope(
        """
        private let lock = NSLock()
        let semaphore: DispatchSemaphore
        DispatchQueue.global().async {}
        var state = Mutex<Int>(0)
        """))
    #expect(found.map(\.location.line) == [1, 2, 3, 4])
  }

  @Test func synchronizationInLockedPasses() {
    let source = "private let lock = NSLock()\nDispatchQueue.concurrentPerform(iterations: 2) { _ in }"
    #expect(Detect.synchronizationOutsideLocked(in: scope(source, at: "Sources/LLMCheck/Support/Locked.swift")).isEmpty)
    #expect(Detect.synchronizationOutsideLocked(in: scope("// NSLock in a comment\nlet name = \"NSLock\"")).isEmpty)
  }

  @Test func printingIsFound() {
    let found = Detect.printing(in: scope("print(1)\ndebugPrint(2)\ndump(3)"))
    #expect(found.map(\.location.line) == [1, 2, 3])
  }

  @Test func lookAlikesOfPrintingPass() {
    let found = Detect.printing(
      in: scope(
        """
        printer.print(value)
        let text = "print(x)"
        /// print(Baseline(covering: findings).swiftArrayLiteral)
        func dump(into output: inout String) {}
        """))
    #expect(found.isEmpty)
  }

  @Test func xcTestImportsAreFoundOutsideItsTests() {
    let source = "import XCTest\nimport LLMCheck"
    let elsewhere = scope(source, at: "Tests/LLMCheckTests/RuleTests.swift")
    let itsTests = scope(source, at: "Tests/LLMCheckTests/XCTestExpectationsTests.swift")
    #expect(Detect.xcTestImports(in: elsewhere).map(\.location.line) == [1])
    #expect(Detect.xcTestImports(in: itsTests).isEmpty)
  }

  @Test func unexplainedKnownIssuesAreFound() {
    let found = Detect.unexplainedKnownIssues(
      in: scope(
        """
        withKnownIssue { record() }
        withKnownIssue(isIntermittent: true) { record() }
        withKnownIssue(reason) { record() }
        """))
    #expect(found.map(\.location.line) == [1, 2, 3])
  }

  @Test func explainedKnownIssuesPass() {
    let found = Detect.unexplainedKnownIssues(
      in: scope(
        """
        withKnownIssue("sqlite-data drops quotaExceeded (#1)") { record() }
        withKnownIssue {
          record()
        } matching: { issue in
          issue.sourceLocation?.line == 3
        }
        try withKnownIssue {
          try record()
        } matching: { $0.comments.isEmpty }
        """))
    #expect(found.isEmpty)
  }
}
