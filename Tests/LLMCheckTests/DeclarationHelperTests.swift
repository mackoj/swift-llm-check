import LLMCheck
import SwiftSyntax
import Testing

@Suite struct DeclarationHelperTests {
  func declarations(_ source: String) -> [Declaration] { Scope(files: [file(source)]).declarations }

  @Test func readsAttributesWithTheirArguments() throws {
    let all = declarations(
      """
      @available(iOS 17, *)
      @available(macOS 14, *)
      @MainActor
      public struct A {
        @available(*, deprecated) public var x = 1
        @Flag<Bool> case y
      }
      """)
    let a = try #require(all.first)
    #expect(a.attribute("available")?.arguments?.trimmedDescription == "iOS 17, *")
    #expect(a.attributes("available").map { $0.arguments?.trimmedDescription } == ["iOS 17, *", "macOS 14, *"])
    #expect(a.attribute("MainActor")?.arguments == nil)
    #expect(a.attribute("MainActor") != nil)
    #expect(a.attribute("Reducer") == nil)
    #expect(a.variables.first?.attribute("available")?.arguments?.trimmedDescription == "*, deprecated")
    #expect(all.first { $0.kind == .enumCase }?.attribute("Flag") != nil)
  }

  @Test func tellsPublicFromInternal() {
    let all = declarations("public struct A {}\nopen class B {}\nstruct C {}\npublic(set) var d = 1")
    #expect(all.map(\.isPublic) == [true, true, false, false])
  }

  @Test func readsGenericParameters() throws {
    let all = declarations(
      """
      struct Form<Model: Codable  &  Sendable, ID> {}
      final class Box<Value> where Value: Hashable, Value: Sendable {}
      func f<T: Equatable>(_ t: T) {}
      enum E {}
      """)
    #expect(
      all[0].genericParameters == [
        GenericParameter(name: "Model", constraint: "Codable & Sendable", constraints: ["Codable", "Sendable"]),
        GenericParameter(name: "ID", constraint: nil, constraints: []),
      ])
    #expect(all[1].genericParameters.first?.constraints == ["Hashable", "Sendable"])
    #expect(all[1].genericParameters.first?.constraint == nil)
    #expect(all[2].genericParameters.map(\.name) == ["T"])
    #expect(all[3].genericParameters.isEmpty)
  }

  @Test func searchesOneDeclarationsCode() throws {
    let all = declarations(
      """
      struct Rating: View {
        var body: some View { Text("a").accessibilityIdentifier("rating") }
      }
      struct Slider: View {
        // .accessibilityIdentifier( is missing
        var body: some View { Text(".accessibilityIdentifier(") }
      }
      """)
    let rating = try #require(all.named("Rating").first)
    let slider = try #require(all.named("Slider").first)
    #expect(rating.contains(".accessibilityIdentifier(", "Text("))
    #expect(!slider.contains(".accessibilityIdentifier("))
    #expect(slider.contains("var body: some View"))
    #expect(rating.calls(named: "accessibilityIdentifier").map(\.location.line) == [2])
    #expect(slider.calls(named: "accessibilityIdentifier").isEmpty)
    #expect(slider.nodes(of: StringLiteralExprSyntax.self).count == 1)
  }

  @Test func readsTheModuleFromThePath() {
    #expect(file("", path: "Sources/App/Feature.swift").module == "App")
    #expect(file("", path: "Packages/Kit/Sources/Kit/Cache/Cache.swift").module == "Kit")
    #expect(file("", path: "Tests/AppTests/A.swift").module == "AppTests")
    #expect(file("", path: "Plugins/Generator/main.swift").module == "Generator")
    #expect(file("", path: "Sources/main.swift").module == nil)
    #expect(file("", path: "Scripts/build.swift").module == nil)
  }

  @Test func findsTopLevelStatementsOutsideAnIf() {
    let scope = Scope(files: [
      file(
        """
        // A header comment is trivia.
        #if canImport(Security)
        import Security
        struct Live {}
        #endif
        """, path: "Sources/Live/Guarded.swift"),
      file(
        """
        import Foundation
        #if canImport(Security) && !os(watchOS)
        struct Live {}
        #endif
        """, path: "Sources/Live/Beside.swift"),
      file(
        """
        #if canImport(Security)
        struct Live {}
        #else
        struct Fake {}
        #endif
        #if canImport(Securityx)
        #endif
        #if os(iOS) || canImport(Security)
        #endif
        struct Open {}
        """, path: "Sources/Live/Unguarded.swift"),
    ])
    let found = scope.topLevelStatements(notUnder: "canImport( Security )")
    #expect(
      found.map { "\($0.file.fileName):\($0.location.line)" } == [
        "Beside.swift:1", "Unguarded.swift:1", "Unguarded.swift:6", "Unguarded.swift:8", "Unguarded.swift:10",
      ])
  }

  @Test func findsDescendants() throws {
    let source = file(
      """
      switch value {
      case .a(let x): f("a: \\(x)", "second")
      default: break
      }
      """
    )
    let switchCase = try #require(source.nodes(of: SwitchCaseSyntax.self).first)
    let first = switchCase.statements.firstDescendant(of: StringLiteralExprSyntax.self)
    #expect(first?.trimmedDescription == #""a: \(x)""#)
    #expect(switchCase.descendants(of: StringLiteralExprSyntax.self).count == 2)
    #expect(switchCase.firstDescendant(of: SwitchCaseSyntax.self) == nil)
    #expect(source.syntax.descendants(of: SwitchCaseSyntax.self).count == 2)
  }

  @Test func seesThroughToClosureTypes() throws {
    let types = file(
      """
      func f(
        a: @escaping @Sendable () -> Void,
        b: ((Int) -> Void)?,
        c: (@MainActor () -> Void)!,
        d: Int,
        e: (x: () -> Void),
        g: @escaping () -> Void
      ) {}
      """
    ).nodes(of: FunctionParameterSyntax.self).map(\.type)
    #expect(types.map { $0.closureType != nil } == [true, true, true, false, false, true])
    #expect(types[1].closureType?.trimmedDescription == "(Int) -> Void")
    #expect(types.map { $0.hasAttribute("Sendable") } == [true, false, false, false, false, false])
    #expect(types[2].hasAttribute("MainActor"))
  }
}
