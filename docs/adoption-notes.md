# Adoption notes

How four repositories and the library itself adopted swift-llm-check, what they have in common, and what a future
guide should say. These are working notes, written from the code and history of each repository on 2026-11-13 (the
library itself on 2026-11-14). The README stays the reference; this file collects material for a "Adopting
swift-llm-check" guide.

| | [Telaio](https://github.com/mackoj/telaio) | [forum-offline](https://github.com/mackoj/forum-offline) | [swift-arazzo](https://github.com/mackoj/swift-arazzo) | [swift-jsonpath](https://github.com/mackoj/swift-jsonpath) | [swift-llm-check](https://github.com/mackoj/swift-llm-check) |
|---|---|---|---|---|---|
| Kind | macOS app, TCA, 992 files | iOS app, SQLiteData/GRDB | Swift library, Linux and Swift 6.0 support | Swift library, no imports at all, Linux and Swift 6.0 support | this library, dogfooding |
| Package | `Packages/TelaioArchitecture` | `Architecture/` | `Architecture/` | `Architecture/` | `Architecture/`, on the working copy (`path: ".."`) |
| Rules | 19, in 7 categories | 4, one category (`database`) | 8, in 4 categories | 9, in 4 categories | 9, in 4 categories |
| Rules come from | PLAN, decision records (D-…), owner issues | profiling hangs (Time Profiler, Hangs) | `CODING_STANDARDS.md`, `CONSTRAINTS.md` | `CODING_STANDARDS.md`, `CONSTRAINTS.md` | promises in the README and CHANGELOG |
| First run | 29 findings, all fixed or decided | 85 sync accesses and 11 loads, all fixed | 0 findings | 2 findings (coders not `Sendable`), fixed | 0 findings |
| Baseline today | none | none | none | none | none |
| Runs from | `scripts/test.sh` on any Swift change, `scripts/ci.sh` | by hand before every push (`AGENTS.md`) | CI's macOS job | CI's macOS job | CI's `architecture` job |
| Rules document | `Packages/TelaioArchitecture/RULES.md` | `ForumOfflineReader/docs/architecture-rules.md` | `docs/architecture-rules.md` | `docs/architecture-rules.md` | `docs/architecture-rules.md` |
| Gave back to the library | the library itself (ported from a Harmonize pilot) | `isAwaited`, `passesClosure`, `argument(labeled:)` (#4, 0.3.0) | `imports(of:)`, `enclosingIfConfigClauses` (#6, 0.4.0) | `Match.erased` | `inherits(from:)` sees `@unchecked Sendable` |

## The recipe they share

All four ended up with the same shape, without a template. A guide can present it as the default.

1. **A standalone, test-only package.** Rules never build with the product: the app's Xcode project or the library's
   manifests do not reference the package, so swift-syntax resolves there only and never holds back the product's
   macros or toolchain. swift-arazzo depends on this most: its library supports Linux and Swift 6.0, and swift-llm-check
   needs macOS 14, so the rules run only in CI's macOS job.

   ```swift
   // swift-tools-version: 6.0
   let package = Package(
       name: "Architecture",
       platforms: [.macOS(.v14)],
       dependencies: [
           .package(url: "https://github.com/mackoj/swift-llm-check.git", from: "0.3.0"),
           .package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.0"..<"700.0.0"),
       ],
       targets: [
           .testTarget(name: "ArchitectureTests", dependencies: [
               .product(name: "LLMCheck", package: "swift-llm-check"),
               .product(name: "SwiftSyntax", package: "swift-syntax"),
           ])
       ]
   )
   ```

   All three list `SwiftSyntax` too: every repository soon has a rule that names a node type.

2. **`.llm-check.yaml` at the repository root**, excluding the rules package itself and folders that hold no product
   code (`docs`, `marketing`, `scripts`, `build`, `DerivedData`).

3. **Rules written from a rule the project already had.** Every `Rule` cites its source in the rationale: a decision
   record (Telaio's D-156, D-162), a measured hang (forum-offline: "Storage usage hung 1.75 s this way"), or a section
   of `CODING_STANDARDS.md` (swift-arazzo). A rule with no source is a rule nobody can argue with or retire.

4. **Detectors apart from the codebase.** forum-offline and swift-arazzo put each query in an `enum Detect` that takes a
   `Scope`; the `@Test` passes the real codebase and `DetectorTests` passes in-memory snippets
   (`Scope(files: [SourceFile(path:source:)])`). Each detector gets a test for what it catches and one for look-alikes
   it lets through (`FileHandle.read(upToCount:)` is not a database read; `Date(timeIntervalSince1970:)` is pure).
   Telaio does the same for its most intricate rules (`RoundedBorderDetector`, nine cases).

5. **A sanity count where a scope could silently be empty.** A rule over an empty scope passes. Telaio guards with
   `#expect(count > 20, "found \(count) reducers: is .llm-check.yaml at the root?")`; swift-arazzo with
   `#expect(models.structs.count > 15)`. A guide should recommend one per rule whose scope is a path pattern.

6. **A generated rules document**, from the same `Rule` values the failures print, with `expectFile` failing when it is
   stale and `LLM_CHECK_RECORD=1` rewriting it. It is the agent-facing list: `AGENTS.md`/`CLAUDE.md` link it instead of
   restating the rules.

7. **Agent instructions next to the rules.** Each repository's `AGENTS.md` or `CLAUDE.md` says: run the package, a
   failure explains itself, fix the code, never add to a baseline. Telaio adds "without the owner's agreement".

8. **Baselines only on the way in.** forum-offline landed its rule with 85 + 11 entries (`File.swift:Declaration`) and
   deleted the baseline once every access was converted, in the same pull request. Telaio started with baselines in the
   Harmonize pilot and dropped them within a day. swift-arazzo needed none. The stale-entry failure is what makes this
   work: a baseline can only shrink.

## Telaio

The first user, and where the library came from.

- **History.** Eight rules were piloted on Harmonize (`exp/harmonize-pilot`, 2026-11-05). Harmonize deadlocked under
  parallel suites (`.serialized`), reported file-level matches at line 1 and took 35 s. The same rules were ported to
  swift-llm-check the same day, with the same 29 findings at the same lines, and ran in 0.7 s. All 29 were then fixed
  or settled by a decision (D-153, D-156), and every baseline was removed.
- **Rules.** `reducer` (State is `@ObservableState`, actions are split, only DocumentFeature applies edits),
  `layering` (model and runtime do no I/O), `dependencies` (a client and its live value are declared together),
  `logging` (no `print`), `testing` (known issues explain themselves, non-exhaustive TestStores say why, snapshots
  draw in a `SnapshotWindow`), `design` (eight rules from D-162: toolbar wrapper, text sized by role, colours from
  tokens, icon-only buttons have a label, rounded views border their own shape…), `database` (access is awaited,
  observations are not immediate).
- **Queries used.** Declarations for reducers and clients, `calls(named:)` with argument labels, `references(to:)` for
  I/O types (a comment mentioning `URLSession` no longer matches, as a grep did), `nodes(of:)` with `attachedComments`
  for "say why", and hand-written modifier-chain walks for the design rules.
- **Running.** `scripts/test.sh` reruns the package whenever a `.swift` file, `.llm-check.yaml` or `RULES.md` changes;
  `scripts/ci.sh` always runs it. The package README keeps a table of each rule, its source and the query it uses.
- **Local helpers still there.** `Support/Syntax.swift` has `isInside(_:)`, `modifierNames`, `unmodified`,
  `chainNames` and `Declaration.calls(named:)`: candidates for the library (see below).

## forum-offline

A focused adoption: one category of rules, written to stop a class of bug from coming back.

- **Why.** Profiling found main-thread hangs from SQLite work: a synchronous `db.read` in a view (1.75 s), a write that
  re-ran observed requests before returning (2.7 s), `@Fetch` loads that fetched synchronously when subscribing
  (368 ms to 1.08 s). The rules encode the fix so the hangs cannot return.
- **Rules.** `database-access-is-awaited`, `fetch-load-uses-animated-async`, `fetch-wrappers-load-explicitly`,
  `observation-is-not-immediate`. Each rationale quotes the measured hang.
- **History.** #171 added the package with every existing violation baselined, then converted the code repository by
  repository and removed entries as it went; the last commit deleted the baseline. #179 moved to 0.3.0, whose
  `isAwaited`, `passesClosure` and `argument(labeled:)` were upstreamed from this package's own helpers (#4): the local
  copies would have clashed, so they were deleted in the same change.
- **Running.** By hand before every push (`cd Architecture && swift test`), per `AGENTS.md`. Not in CI.

## swift-arazzo

A library adoption, where the rules restate written standards rather than fix found bugs.

- **Why.** `CODING_STANDARDS.md` and `CONSTRAINTS.md` already listed the rules; some were checked by `grep` in the
  constraints table, the rest only in review. The rules make the mechanical part fail at the offending line.
- **Rules.** `purity` (no I/O, clock, UUID, singleton or `print` in `Sources`), `platforms` (`import Foundation` only
  as the `#else` of `#if canImport(FoundationEssentials)`; ArazzoKit imports only its budget and Yams stays under
  `#if YAML`), `models` (public models are `Hashable` and `Sendable`; `@unchecked Sendable` has a comment), `testing`
  (Swift Testing only, no `.disabled`, `withKnownIssue` names its issue).
- **Checking the rules themselves.** Beyond `DetectorTests`, one violation per rule was planted in the real `Sources`
  and `Tests` and each of the eight rules failed at the right line, then the plants were removed. A guide should
  suggest this once per new rule: it catches a scope pattern that matches nothing.
- **What the repository needed.** The package follows the repository's own `.swift-format` (4 spaces), which the
  soundness format check applies to every tracked Swift file; the format commands in `CONSTRAINTS.md` and `AGENTS.md`
  gained `Architecture`. `.gitignore` anchored `/.build` at the root, so `Architecture/.build` needed its own line.
- **Gave back.** Two rules need an import and the `#if` branch it is in. The local helpers became `Scope.imports`,
  `imports(of:)`, `ImportDeclSyntax.moduleName`, `enclosingIfConfigClauses`, `IfConfigClauseSyntax.ifCondition` and
  `isElse` (#6). swift-arazzo#11 moved to 0.4.0 and deleted its copies, as forum-offline's #179 did.

## swift-jsonpath

A second library adoption, copied from swift-arazzo's shape on the first try.

- **Why.** As in swift-arazzo, `CODING_STANDARDS.md` and `CONSTRAINTS.md` already listed the rules, and the dependency
  budget ("`Sources` imports nothing") was a `grep` in the constraints table.
- **Rules.** `platforms` (`Sources` imports nothing, not even libc), `purity` (no `print`, `readLine`, `CommandLine` or
  randomness), `models` (public types are structs or enums, `Sendable` and `Hashable`; `@unchecked Sendable` has a
  comment), `testing` (no `fatalError("TODO")` stubs, Swift Testing only, no `.disabled`, `withKnownIssue` names its
  issue). Four rules are swift-arazzo's, word for word apart from the examples: `tests-use-swift-testing`,
  `tests-are-not-disabled`, `known-issues-explain-themselves` and `unchecked-sendable-explains-itself`.
- **First run.** Two findings: `JSONValueDecoder` and `JSONValueEncoder` were not `Sendable`. They became `Sendable`;
  they cannot be `Hashable` (`userInfo` holds `any Sendable`), so the rule lists them by name with the reason.
- **What the detector needed.** `OrderedDictionary<Key, Value>` declares `Hashable` and `Sendable` conditionally in
  extensions, as a generic container must. The conformance rule looks at the type and `scope.extensions` whose name is
  the type's qualified name; swift-arazzo's version, which reads only the type's own inheritance clause, would have
  flagged it.
- **Checked like swift-arazzo.** One violation per rule planted in the real `Sources` and `Tests`; all nine failed at
  the planted line.
- **Gave back.** `Match.erased`, for the no-I/O rule that merges `references(to:)` and `calls(named:)`.

## swift-llm-check itself

The library checks itself, with the recipe above and one difference: the rules package depends on the working copy.

- **Why.** The README makes promises a reviewer has to remember: the only dependency is swift-syntax's parser,
  SwiftSyntax is not re-exported (0.2.0), everything public is `Sendable`, the caches never wait on one another. The
  rules make each promise fail at the line that breaks it, and each rationale cites the README or CHANGELOG section.
- **Rules.** `dependencies` (`Sources` imports only Foundation, Dispatch, SwiftSyntax, SwiftParser, Testing and XCTest;
  XCTest only under `#if canImport(XCTest)`; no `@_exported import`), `concurrency` (public types are `Sendable`,
  directly or through `Finding` or `Error`; `@unchecked Sendable` has a comment; locks, semaphores and dispatch queues
  only in `Support/Locked.swift`), `reporting` (no `print`), `testing` (XCTest only in `XCTestExpectationsTests.swift`;
  `withKnownIssue` names its issue or pins it with `matching:`).
- **`path: ".."`.** `.package(name: "swift-llm-check", path: "..")` builds the rules against the code they check, so
  a change to a query is run by the rules in the same pull request. The cost: a planted violation must compile, since
  the library under check is built too (`import SwiftSyntaxBuilder` does not; `import Darwin` does).
- **A rule adapted to the repository.** The library's own tests use `withKnownIssue` on purpose, to check what
  `expectNone` records. swift-arazzo's `known-issues-explain-themselves` would flag all four; here a `matching:`
  closure that pins the expected issue counts as the explanation.
- **What the sanity counts caught.** `scope.in("Support/Locked.swift")` matched nothing: a pattern with a slash is
  anchored at the root, as the README says. The count (`== 1`, "Locked.swift moved") failed before the rule could
  pass on the wrong scope. A guide should show a root-anchored path in its first example.
- **Checked like swift-arazzo.** One violation per rule planted in `Sources` and `Tests`; all nine failed at the
  planted line.
- **Gave back.** `Declaration.inherits(from: "Sendable")` was false for `@unchecked Sendable`, since `inheritance`
  keeps the clause as written. The `Sendable` detector stripped the attribute itself; the library now sees through
  `@unchecked`, `@retroactive` and `@preconcurrency`.

## The loop between repositories and the library

Each adoption writes a helper, and a general one moves into the library:

1. A rule needs a query the library lacks; the rules package writes it in `Support/`.
2. If it is not specific to the repository, it is proposed upstream with tests, a README line and a CHANGELOG entry.
3. When the release ships, the repository bumps `from:` and deletes its copy in the same change. The copies clash
   with the library's (same names), so the bump forces the cleanup.

Still local, and worth a look for the library:

- Telaio's `isInside(_:)` (is a node inside a declaration) and `Declaration.calls(named:)` (calls within one
  declaration, nested closures included).
- Telaio's modifier-chain helpers (`modifierNames`, `unmodified`, `chainNames`), for SwiftUI rules.
- Rules copied between repositories. swift-arazzo and swift-jsonpath carry the same four `Rule`s and detectors
  (Swift Testing only, no `.disabled`, `withKnownIssue` names its issue, `@unchecked Sendable` has a comment), and
  Telaio and swift-llm-check have their own `known-issues-explain-themselves` (the latter accepting `matching:`).
  swift-llm-check's `Architecture/` carries `unchecked-sendable-explains-itself` word for word too. A small set of ready-made rules, with a project-specific
  rationale passed in, would end the copying.
- A sort by location for merged findings. Combining findings of different node types is `Match.erased` now (from
  swift-jsonpath's adoption); the merged array is still in the order the queries ran.

## For the future guide

- Start from the recipe above; it is what three independent adoptions converged on.
- Show both entry paths: rules from a written standard with no findings (swift-arazzo), and rules landed on a codebase
  that breaks them, with a baseline that is deleted when it is empty (forum-offline). `Baseline(covering:)` makes the
  second path one line.
- Say where the rules run: a test script keyed on changed files (Telaio), CI on macOS (swift-arazzo), or by hand
  (forum-offline). A library that supports Linux runs them on a macOS job only.
- Recommend the sanity count and the one-time planted violation per rule.
- Explain that the rules document and the failure text come from the same `Rule`, so agents read the rule before they
  break it and again when they do.
