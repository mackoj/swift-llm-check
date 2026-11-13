import LLMCheck
import Testing

@Suite struct DeclarationTests {
  let source = file(
    """
    import Foundation

    @Reducer
    public struct Feature: Sendable, Equatable {
      @ObservableState
      struct State: Equatable {
        var count = 0, title: String
      }

      enum Action: ViewAction {
        case view(View)
        case delegate, binding
      }

      #if DEBUG
      static func debug() {}
      #endif

      init() {}
      typealias Body = Never
    }

    extension Feature.State: CustomStringConvertible {}
    actor Store {}
    protocol Client: Sendable {}
    final class Model<T>: Base<T> {}
    private func helper() { struct Local {} }
    """)

  @Test func listsTopLevelDeclarations() {
    #expect(source.declarations.map(\.kind) == [.struct, .extension, .actor, .protocol, .class, .function])
    #expect(source.declarations.map(\.name) == ["Feature", "Feature.State", "Store", "Client", "Model", "helper"])
  }

  @Test func readsAttributesModifiersAndInheritance() throws {
    let feature = try #require(source.declarations.first)
    #expect(feature.attributes == ["Reducer"])
    #expect(feature.modifiers == ["public"])
    #expect(feature.inheritance == ["Sendable", "Equatable"])
    #expect(feature.inherits(from: "Sendable"))
    let model = try #require(source.declarations.named("Model").first)
    #expect(model.modifiers == ["final"])
    #expect(model.inherits(from: "Base"))
    #expect(source.declarations.named("helper").first?.modifiers == ["private"])
  }

  @Test func inheritsThroughConformanceAttributes() throws {
    let source = file(
      """
      final class Cache: @unchecked Sendable {}
      extension URL: @retroactive Identifiable {}
      struct Delegate: @preconcurrency Observer<Event> {}
      struct Unchecker: UncheckedSendable {}
      """)
    let declarations = source.declarations
    #expect(declarations[0].inheritance == ["@unchecked Sendable"])
    #expect(declarations[0].inherits(from: "Sendable"))
    #expect(declarations[1].inherits(from: "Identifiable"))
    #expect(declarations[2].inherits(from: "Observer"))
    #expect(!declarations[3].inherits(from: "Sendable"))
  }

  @Test func nestsChildrenWithTheirParent() throws {
    let feature = try #require(source.declarations.first)
    #expect(feature.children.map(\.name) == ["State", "Action", "debug", "init", "Body"])
    let state = try #require(feature.structs.named("State").first)
    #expect(state.parent === feature)
    #expect(state.qualifiedName == "Feature.State")
    #expect(state.hasAttribute("ObservableState"))
    #expect(state.variables.map(\.name) == ["count", "title"])
    #expect(feature.enums.first?.cases.map(\.name) == ["view", "delegate", "binding"])
    #expect(feature.functions.first?.modifiers == ["static"])
  }

  @Test func skipsLocalDeclarations() {
    #expect(Scope(files: [source]).structs.map(\.name) == ["Feature", "State"])
  }

  @Test func locatesTheIntroducerNotTheAttributes() throws {
    let feature = try #require(source.declarations.first)
    #expect(feature.location.line == 4)
    #expect(feature.location.column == 8)
    #expect(feature.snippet == "public struct Feature: Sendable, Equatable {")
    let state = try #require(feature.structs.first)
    #expect(state.location.line == 6)
    #expect(state.declarationNames == ["Feature.State", "Feature"])
    let binding = try #require(feature.enums.first?.cases.last)
    #expect(binding.location.line == 12)
    #expect(binding.location.column == 20)
  }

  @Test func scopeFlattensNestedDeclarations() {
    let scope = Scope(files: [source])
    #expect(scope.topLevelDeclarations.count == 6)
    #expect(scope.enums.map(\.qualifiedName) == ["Feature.Action"])
    #expect(scope.declarations(.enumCase).count == 3)
    #expect(scope.functions.map(\.name) == ["debug", "helper"])
    #expect(scope.structs.withAttribute("Reducer").map(\.name) == ["Feature"])
    #expect(scope.extensions.inheriting(from: "CustomStringConvertible").count == 1)
    #expect(scope.actors.count == 1)
    #expect(scope.protocols.count == 1)
    #expect(scope.classes.count == 1)
    #expect(scope.variables.count == 2)
  }
}
