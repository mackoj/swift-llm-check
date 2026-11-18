import LLMCheck
import Testing

@Suite struct AdditionalDatabaseDetectorTests {
  func scope(_ source: String) -> Scope { Scope(files: [file(source)]) }

  @Test func findsTemporaryViewsInMigrations() {
    let code = scope(
      """
      migrator.registerMigration("v2") { db in
        let view = Summary.createTemporaryView(as: query)
        try view.execute(db)
        func later() { Summary.createTemporaryView(as: query) }
      }
      migrator.registerMigration("v3", migrate: { db in
        try Summary.createTemporaryView(as: query).execute(db)
      })
      configuration.prepareDatabase { db in try Summary.createTemporaryView(as: query).execute(db) }
      // Summary.createTemporaryView(as: query)
      """)
    #expect(code.temporaryViewsInMigrations.map(\.location.line) == [2, 7])
  }

  @Test func viewDefinitionsComputeTheirClockAndIDsInSQL() {
    let code = scope(
      """
      Summary.createTemporaryView(as: Item.where { $0.createdAt < Date() })
      Summary.createTemporaryView(as: Item.select { (Date.now, UUID()) })
      Summary.createTemporaryView(as: Item.where { $0.createdAt < #sql("datetime('subsec')") })
      let query = Item.where { $0.createdAt < Date() }
      Summary.createTemporaryView(as: query)
      Summary.createTemporaryView(as: Item.where { $0.createdAt < Date(timeIntervalSince1970: 0) })
      """)
    #expect(code.swiftValuesInSQLViews.map(\.location.line) == [1, 2, 2])
  }

  @Test func ftsDocumentJSONColumnsAreFoundOnlyOnTheirOwningType() {
    let code = scope(
      """
      @Table struct Document: FTS5 {
        @Column(as: [String].JSONRepresentation.self) var tags: [String]
        @Column(as: Data.JSONBRepresentation.self) var body: Data
        @Column(as: UUID.self) var id: UUID
        var text: String
        struct Nested { @Column(as: Data.JSONBRepresentation.self) var payload: Data }
      }
      @SQLiteData.Table struct Qualified: StructuredQueriesSQLite.FTS5 {
        @SQLiteData.Column(as: Value.JSONRepresentation.self) var value: Value
      }
      @Table struct Normal {
        @Column(as: [String].JSONRepresentation.self) var tags: [String]
      }
      struct NotATable: FTS5 { @Column(as: Value.JSONBRepresentation.self) var value: Value }
      """)
    #expect(code.jsonEncodedFTS5Columns.map(\.location.line) == [2, 3, 9])
  }

  @Test func synchronousDatabaseAccessRequiresARealImportAndUnawaitedClosure() {
    let code = scope(
      """
      @preconcurrency import GRDB
      try database.read { db in 1 }
      try database.write(updates: { db in })
      try await database.read { db in try database.write { _ in } }
      try await database.writeWithoutTransaction { db in }
      try queue.inDatabase { db in }
      try database.unsafeReentrantRead { db in }
      data.write(to: url)
      read { 1 }
      try database.read(work)
      """)
    #expect(code.synchronousDatabaseAccess.map(\.location.line) == [2, 3, 4, 6, 7])
    #expect(scope("// import GRDB\ncoordinator.read { url in }").synchronousDatabaseAccess.isEmpty)
    #expect(scope("let text = \"import SQLiteData\"\ncoordinator.write { url in }").synchronousDatabaseAccess.isEmpty)
    #expect(scope("public import SQLiteData\ntry db.read { _ in }").synchronousDatabaseAccess.count == 1)
  }

  @Test func immediateObservationSchedulingIsAnExactMemberNotASubstring() {
    let code = scope(
      """
      observation.start(in: database, scheduling: .immediate) { _ in }
      observation.start(in: database, scheduling: ValueObservationScheduler.immediate) { _ in }
      observation.start(in: database, scheduling: .async(onQueue: .main)) { _ in }
      observation.start(in: database, scheduling: .immediateIfPossible) { _ in }
      observation.start(in: database, scheduling: "immediate") { _ in }
      observation.start(in: database, scheduling: makeScheduler(.immediate)) { _ in }
      observation.start(in: database, scheduling /* split */ : .immediate) { _ in }
      observation.start(in: database) { _ in }
      recorder.finish(in: database, scheduling: .immediate)
      observation.publisher(in: database, scheduling: .immediate)
      """)
    #expect(code.immediateDatabaseObservations.map(\.location.line) == [1, 2, 7, 10])
  }
}
