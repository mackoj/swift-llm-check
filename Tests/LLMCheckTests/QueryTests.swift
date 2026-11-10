import LLMCheck
import SwiftSyntax
import Testing

@Suite struct QueryTests {
  @Test func findsCallsWhereverTheyAre() {
    let scope = Scope(files: [
      file(
        """
        func a() async throws {
          await withKnownIssue { try record() }
          let x = try await track(1)
          defer { track(2) }
        }
        func b() -> Effect {
          return .run { send in await track(3) }
        }
        func c(_ value: Int) {
          switch value {
          case 1: track(4)
          default: if true { _ = [track(5)].map { _ in track(6) } }
          }
        }
        // track(7) in a comment
        let s = "track(8) in a string"
        """)
    ])
    #expect(scope.calls(named: "track").map(\.location.line) == [3, 4, 7, 11, 12, 12])
    #expect(scope.calls(named: "withKnownIssue").map(\.location.line) == [2])
    #expect(scope.calls(named: "withKnownIssue", "record").count == 2)
  }

  @Test func readsTheCalledNameAndReceiver() throws {
    let calls = Scope(files: [file("print(1); edit.apply(to: &doc); .init(); Foo<Int>(); Swift.print(2)")])
      .nodes(of: FunctionCallExprSyntax.self)
    #expect(calls.map(\.node.calledName) == ["print", "apply", "init", "Foo", "print"])
    #expect(calls.map { $0.node.receiver?.trimmedDescription } == [nil, "edit", nil, nil, "Swift"])
  }

  @Test func referencesSkipCommentsAndStrings() {
    let scope = Scope(files: [
      file(
        """
        // URLSession in a comment
        let note = "URLSession in a string"
        let session = URLSession.shared
        var manager: FileManager { .default }
        let qualified: Foundation.URLSession? = nil
        /// Uses `URLSession`.
        func load() {}
        """)
    ])
    let found = scope.references(to: "URLSession", "FileManager")
    #expect(found.map(\.location.line) == [3, 4, 5])
    #expect(
      found.map(\.snippet) == [
        "let session = URLSession.shared", "var manager: FileManager { .default }",
        "let qualified: Foundation.URLSession? = nil",
      ])
  }

  @Test func containingFiltersOnTheRawText() {
    let scope = Scope(files: [file("let a = 1", path: "A.swift"), file("// b\nlet b = 2", path: "B.swift")])
    #expect(scope.containing("b").relativePaths == ["B.swift"])
    #expect(scope.containing("a", "b").relativePaths == ["A.swift", "B.swift"])
    #expect(scope.containing("a").containing("b").relativePaths.isEmpty)
  }

  @Test func genericNodeSearchWithAPredicate() {
    let scope = Scope(files: [file("let a = b!\nlet c = d!.e!\nlet f = g")])
    #expect(scope.nodes(of: ForceUnwrapExprSyntax.self).count == 3)
    #expect(scope.nodes(of: ForceUnwrapExprSyntax.self) { $0.location.line == 1 }.count == 1)
  }

  @Test func matchesKnowTheirEnclosingDeclarations() throws {
    let scope = Scope(files: [
      file(
        """
        struct Feature {
          enum Action {}
          func reduce() {
            track()
          }
          var body: Int { track() }
        }
        extension Feature.State {
          init() { track() }
        }
        """, path: "Sources/Feature.swift")
    ])
    let calls = scope.calls(named: "track")
    #expect(calls[0].declarationNames == ["Feature.reduce", "Feature"])
    #expect(calls[1].declarationNames == ["Feature.body", "Feature"])
    #expect(calls[2].declarationNames == ["Feature.State.init", "Feature.State"])
    #expect(calls[0].location.description == "Sources/Feature.swift:4:5")
    #expect(calls[0].snippet == "track()")
  }

  @Test func snippetsFollowTheParsersLines() {
    for newline in ["\n", "\r\n", "\r"] {
      let source = ["let a = 1", "  track(1)", "let b = 2", "track(2)"].joined(separator: newline)
      let calls = Scope(files: [file(source)]).calls(named: "track")
      #expect(calls.map(\.location.line) == [2, 4])
      #expect(calls.map(\.snippet) == ["track(1)", "track(2)"])
    }
  }

  @Test func readsAttachedComments() throws {
    let scope = Scope(files: [
      file(
        """
        func test() {
          // Why it is off.
          store.exhaustivity = .off
          store.exhaustivity = .off  // Trailing reason.
          store.exhaustivity = .off
          /* block */ store.exhaustivity = .off
          store.exhaustivity = .off
          // About the next line, not the one above.
        }
        """)
    ])
    let statements = scope.nodes(of: CodeBlockItemSyntax.self) { $0.node.item.is(ExprSyntax.self) }
    #expect(
      statements.map(\.node.attachedComments) == [
        ["// Why it is off."], ["// Trailing reason."], [], ["/* block */"], [],
      ])
    #expect(statements[0].node.leadingComments == ["// Why it is off."])
    #expect(statements[1].node.trailingComments == ["// Trailing reason."])
  }

  @Test func findsCallsFromANameSetBuiltAtRunTime() {
    let scope = Scope(files: [file("db.read { }; db.write { }; db.vacuum(); print(1)")])
    let names: Set<String> = ["read", "write"]
    #expect(scope.calls(named: names).map(\.node.calledName) == ["read", "write"])
    #expect(scope.calls(named: ["vacuum"]).count == 1)
  }

  @Test func findsArgumentsByLabel() throws {
    let call = try #require(
      Scope(files: [file("load(r, database: db, scheduler: .async) { }")]).calls(named: "load").first)
    #expect(call.node.argument(labeled: "database")?.expression.trimmedDescription == "db")
    #expect(call.node.argument(labeled: "scheduler")?.expression.trimmedDescription == ".async")
    #expect(call.node.argument(labeled: "animation") == nil)
  }

  @Test func seesClosuresHoweverTheyArePassed() {
    let calls = Scope(files: [
      file("a { }; b(work: { }); c(1); d { } onError: { }; e(f)")
    ]).nodes(of: FunctionCallExprSyntax.self)
    #expect(calls.map(\.node.passesClosure) == [true, true, false, true, false])
  }

  @Test func awaitedMeansUnderAnAwaitInItsOwnExpression() {
    let scope = Scope(files: [
      file(
        """
        func f() async throws {
          try await read(1)
          let a = (try? await read(2)) ?? []
          _ = await [read(3)]
          try read(4)
          Task { try read(5) }
          try await perform { try read(6) }
          let b = read(7)
        }
        struct S { var v: Int { read(8) } }
        """)
    ])
    let awaited = scope.calls(named: "read").filter(\.node.isAwaited).map(\.location.line)
    #expect(awaited == [2, 3, 4])
  }
}
