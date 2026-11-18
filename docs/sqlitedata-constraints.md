# SQLiteData syntax constraints

These detectors return matches for an adopting repository's `Rule`, with its own rationale and exceptions.
They need only SwiftSyntax. Select your SQLiteData/StructuredQueries code before calling them; names alone cannot
prove which library a method belongs to. They do not validate migrations, SQL strings, helper bodies or runtime data.

| Detector | Bad | Good | Limit |
|---|---|---|---|
| `temporaryTriggersInMigrations` | `registerMigration("v2") { db in Item.createTemporaryTrigger(...) }` | Install the temporary trigger after migration on every opening | Direct lexical calls only; raw SQL and helpers need database tests |
| `swiftValuesInSQLTriggers` | `Item.createTemporaryTrigger(afterUpdateTouch: { $0.at = Date() })` | `$0.at = #sql("datetime('subsec')")` | Finds `Date()`, `Date.now`, `UUID()` and Foundation-qualified spellings; constants, dependencies and custom factories need review |
| `unignoredObservablePropertyWrappers` | `@Observable class Model { @FetchAll var items: [Item] }` | Add `@ObservationIgnored` to the property | Direct stored instance `Fetch`, `FetchAll`, `FetchOne`, `Dependency` properties only; module-qualified attributes count; TCA is separate |
| `invalidFTS5SnippetTokenCounts` | `text.snippet("[", "]", "...", 0)` | `text.snippet("[", "]", "...", 40)` | Four unlabelled member-call arguments; literal counts only; dynamic counts need runtime checks |
| `temporaryViewsInMigrations` | A runtime query's view is installed only by `registerMigration` | Install it with `configuration.prepareDatabase` on every querying connection | Finds typed lexical calls; a migration-only transformation view is legitimate |
| `swiftValuesInSQLViews` | `Summary.createTemporaryView(as: Item.where { $0.at < Date() })` | Compute the clock value in SQL | Same direct-expression contract and exclusions as trigger values; prebuilt query values need review |
| `jsonEncodedFTS5Columns` | Encoded tags are indexed as JSON when search expects plain tag names | Flatten the document text before indexing | An opt-in plain-document policy, not a SQL error; opaque UNINDEXED metadata and intentional JSON indexing can be valid |
| `synchronousDatabaseAccess` | UI work calls `database.read { ... }` synchronously | Await an async API from an effect | Real GRDB/SQLiteData imports and inline member-call closures; no receiver or thread inference; named closure arguments are not followed |
| `immediateDatabaseObservations` | A policy requiring deferred first delivery uses `observation.start(in: db, scheduling: .immediate)` | Use the default scheduler or the async observation sequence | Exact `start`/`publisher` member calls with `in:` and an immediate scheduler member; deliberate immediate delivery is valid |

The trigger-value detector reports the Swift expression, rather than the whole trigger. Functions and nested types
declared inside a builder are not executed just by being declared and are excluded. A deliberately constant date is
not inherently wrong; explicit `Date(timeIntervalSince1970:)` and `UUID(uuidString:)` initializers are left alone.
The observable detector excludes local variables, computed and static/class properties, and treats nested types
independently. The snippet detector accepts decimal, binary, octal, hex and signed integer literals.

Temporary objects can be useful only during a migration. Their presence inside `registerMigration` is a placement
finding, not proof that a later feature depends on them. A repository can select the relevant migrations or filter
the matches. A synchronous bootstrap or background transaction is also different from a UI-thread transaction.
Some unsafe GRDB APIs have no async overload and need replacement rather than adding `await`.

Two tempting checks were deliberately excluded after reading the current implementations. TCA's
`ObservableStateMacro` automatically adds `ObservationStateIgnored` for Fetch, FetchAll and FetchOne, so requiring
the source to spell it out would reject valid code. StructuredQueries column-level `match("")` becomes a quoted
column phrase and can validly return no rows, unlike a bare empty table MATCH query. A blanket empty-match ban
would conflate these different APIs.

## Sources

- Point-Free [#330, Persistence Callbacks: Triggers](https://www.pointfree.co/episodes/ep330-persistence-callbacks-triggers),
  27:37 to 29:05, and [#331, Type-Safe Triggers](https://www.pointfree.co/episodes/ep331-persistence-callbacks-type-safe-triggers),
  0:50 to 1:23 and 5:32 to 6:31. Migrations run once; temporary triggers last for a connection. A Swift date in a
  trigger builder becomes a bound constant when the statement is constructed.
- SQLite's [temporary trigger documentation](https://www.sqlite.org/lang_createtrigger.html#temp_triggers_on_non_temp_tables).
- Point-Free [#338, Modern Search: Highlights & Snippets](https://www.pointfree.co/episodes/ep338-modern-search-highlights-snippets),
  11:04 and 15:02, and SQLite's [FTS5 snippet reference](https://www.sqlite.org/fts5.html#the_snippet_function).
- Point-Free [#377, WWDC26: SQLiteData Observation](https://www.pointfree.co/episodes/ep377-wwdc26-sqlitedata-observation),
  4:15 to 4:46 and 13:12. Fetch and dependency wrappers in an Observable model do their own tracking.
- Point-Free [#345, CloudKit Sync: Participants](https://www.pointfree.co/episodes/ep345-cloudkit-sync-participants),
  8:49 to 10:18, and SQLite's [temporary view lifetime](https://www.sqlite.org/lang_createview.html).
- StructuredQueries' [view builder](https://github.com/pointfreeco/swift-structured-queries/blob/main/Sources/StructuredQueriesSQLiteCore/Views.swift)
  compiles its query at creation. Its [query fragment compiler](https://github.com/pointfreeco/swift-structured-queries/blob/main/Sources/StructuredQueriesCore/QueryFragment.swift)
  reports bound Date/UUID values and serializes them into SQL literals, which remain fixed in a view definition.
- Telaio's [database rules](https://github.com/mackoj/telaio/tree/develop/Packages/TelaioArchitecture), and GRDB's
  [observation scheduler](https://github.com/groue/GRDB.swift/blob/master/GRDB/ValueObservation/ValueObservationScheduler.swift).
  Immediate first notification is intentionally synchronous; it remains a supported scheduling option.
- TCA's [ObservableState macro](https://github.com/pointfreeco/swift-composable-architecture/blob/main/Sources/ComposableArchitectureMacros/ObservableStateMacro.swift)
  and StructuredQueries' [two MATCH implementations](https://github.com/pointfreeco/swift-structured-queries/blob/main/Sources/StructuredQueriesSQLiteCore/FTS5.swift)
  establish the exclusions above.

## What still needs database tests

Check trigger installation again after reopening, bulk updates, transaction rollback, FTS insert/update/delete
maintenance, literal search quoting and rank ordering against real SQLite. CloudKit schema rules need inspection of
the migrated tables and an explicit sync-table list, not a guess based on an `id` spelling in Swift. In particular,
local analytics and FTS virtual tables must not inherit every rule for synced records.
