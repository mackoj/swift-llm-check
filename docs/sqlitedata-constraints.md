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

The trigger-value detector reports the Swift expression, rather than the whole trigger. Functions and nested types
declared inside a builder are not executed just by being declared and are excluded. A deliberately constant date is
not inherently wrong; explicit `Date(timeIntervalSince1970:)` and `UUID(uuidString:)` initializers are left alone.
The observable detector excludes local variables, computed and static/class properties, and treats nested types
independently. The snippet detector accepts decimal, binary, octal, hex and signed integer literals.

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

## What still needs database tests

Check trigger installation again after reopening, bulk updates, transaction rollback, FTS insert/update/delete
maintenance, literal search quoting and rank ordering against real SQLite. CloudKit schema rules need inspection of
the migrated tables and an explicit sync-table list, not a guess based on an `id` spelling in Swift. In particular,
local analytics and FTS virtual tables must not inherit every rule for synced records.
