import LLMCheck
import Testing

/// Database rules use syntax, so each detector tests its look-alikes as well as its violations.
@Suite struct SQLiteDataDetectorTests {
  func scope(_ source: String) -> Scope { Scope(files: [file(source)]) }

  @Test func temporaryTriggersBelongToConnectionSetup() {
    let code = scope(
      """
      migrator.registerMigration("v2") { db in
        try Item.createTemporaryTrigger(afterUpdateTouch: \\.updatedAt).execute(db)
      }
      migrator.registerMigration("v3", migrate: { db in
        try Item.createTemporaryTrigger(afterInsertTouch: \\.createdAt).execute(db)
      })
      try Item.createTemporaryTrigger(afterUpdateTouch: \\.updatedAt).execute(db)
      // Item.createTemporaryTrigger inside registerMigration
      let text = "Item.createTemporaryTrigger()"
      """)
    #expect(code.temporaryTriggersInMigrations.map(\.location.line) == [2, 5])
  }

  @Test func triggerDatesAndIDsAreComputedBySQL() {
    let code = scope(
      """
      try Item.createTemporaryTrigger(after: .insert { new in
        Item.update {
          $0.updatedAt = Date()
          $0.createdAt = Foundation.Date.now
          $0.id = UUID()
        }
      }).execute(db)
      let date = Date()
      let uuid = UUID()
      try Item.createTemporaryTrigger(afterUpdateTouch: {
        $0.updatedAt = #sql("datetime('subsec')")
        $0.createdAt = Date(timeIntervalSince1970: 0)
      }).execute(db)
      try Item.createTemporaryTrigger(afterUpdateTouch: {
        $0.updatedAt = Foundation.Date()
        $0.id = Foundation.UUID()
      }).execute(db)
      """)
    #expect(code.swiftValuesInSQLTriggers.map(\.location.line) == [3, 4, 5, 15, 16])
  }

  @Test func storedWrappersInObservableClassesIgnoreObservation() {
    let code = scope(
      """
      @Observable class Model {
        @FetchAll var items: [Item]
        @Dependency(\\.defaultDatabase) var database
        @ObservationIgnored @FetchOne var item: Item?
        @FetchAll static var shared: [Item]
        struct Nested { @FetchAll var items: [Item] }
        class Plain { @FetchAll var items: [Item] }
        func load() { @Dependency(\\.defaultDatabase) var local }
        var value: Int { @Dependency(\\.number) var number; return number }
        @Observable class Child { @Fetch var rows: Rows }
      }
      @Observation.Observable class Qualified {
        @SQLiteData.FetchAll var items: [Item]
        @Observation.ObservationIgnored @Dependencies.Dependency(\\.number) var number
      }
      @ObservableState struct State { @FetchAll var items: [Item] }
      """)
    #expect(code.unignoredObservablePropertyWrappers.map(\.location.line) == [2, 3, 10, 13])
  }

  @Test func snippetTokenLimitsAreBetweenOneAnd64() {
    let code = scope(
      """
      text.snippet("<b>", "</b>", "...", 0)
      text.snippet("<b>", "</b>", "...", 65)
      text.snippet("<b>", "</b>", "...", -1)
      text.snippet("<b>", "</b>", "...", 1)
      text.snippet("<b>", "</b>", "...", 64)
      text.snippet("<b>", "</b>", "...", limit)
      snippet("ordinary function", 100)
      text.snippet("...", count: 100)
      // text.snippet("<b>", "</b>", "...", 0)
      text.snippet("<b>", "</b>", "...", 0x41)
      """)
    #expect(code.invalidFTS5SnippetTokenCounts.map(\.location.line) == [1, 2, 3, 10])
  }

  @Test func contextIncludesBindingsButNotSeparateFunctionBodies() {
    let code = scope(
      """
      migrator.registerMigration("v2") { db in
        let trigger = Item.createTemporaryTrigger(afterUpdateTouch: {
          let date = Date()
          $0.updatedAt = date
          func later() { _ = Date() }
        })
        func separate() { Item.createTemporaryTrigger(afterUpdateTouch: \\.updatedAt) }
      }
      @Observable class Model {
        #if DEBUG
        @FetchAll var items: [Item]
        #endif
        @Dependency(\\.number) var number { didSet {} }
        class Nested { @FetchOne var item: Item? }
      }
      """)
    #expect(code.temporaryTriggersInMigrations.map(\.location.line) == [2])
    #expect(code.swiftValuesInSQLTriggers.map(\.location.line) == [3])
    #expect(code.unignoredObservablePropertyWrappers.map(\.location.line) == [11, 13])
  }
}
