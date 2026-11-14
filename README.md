# swift-llm-check

Architecture and lint rules for Swift codebases, written as Swift Testing tests. A failing rule records one issue per
violation at the offending file, line and column, with the offending line and the rule's full text. That text is the
title, the rationale, how to fix it and a bad and a good example, so the reader can fix the violation without asking.
That reader is often an AI agent.

```
Packages/TelaioCLI/Tests/TelaioCLITests/RunCommandTests.swift:100:11: await withKnownIssue {

RULE: withKnownIssue says what the known issue is. [known-issues-explain-themselves, testing]
WHY: A known issue hides a failing expectation. Without a reason in the call, the next reader cannot tell a bug
     waiting for a fix from a test nobody understood.
HOW TO FIX: Pass the reason as the first argument: name the bug and where it is tracked.
BAD:
    await withKnownIssue { try await sync.upload() }
GOOD:
    await withKnownIssue("sqlite-data 1.12 drops quotaExceeded (bug 1)") { try await sync.upload() }
```

Requirements: Swift 6 (Xcode 16 or later), macOS 14 or iOS 17. The only dependency is
[swift-syntax](https://github.com/swiftlang/swift-syntax).

## Installation

Rules usually live in a small test-only package of their own, so the app's build never sees them:

```swift
// Packages/Architecture/Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Architecture",
  platforms: [.macOS(.v14)],
  dependencies: [.package(url: "https://github.com/mackoj/swift-llm-check.git", from: "0.4.1")],
  targets: [
    .testTarget(name: "ArchitectureTests", dependencies: [.product(name: "LLMCheck", package: "swift-llm-check")])
  ]
)
```

Put a `.llm-check.yaml` at the root of the code to check. `Codebase()` walks up from the calling test file to find it:

```yaml
# Paths never read. A name matches any folder or file; a path with a slash matches from the root; * is a wildcard.
excludes:
  - build
  - DerivedData
  - Packages/Architecture
# Optional. A folder whose name ends with one of these holds test code (default: Tests).
testSuffixes: [Tests]
# Optional. A folder with one of these names holds test code (default: Fixtures).
testFolders: [Fixtures]
```

Hidden folders (`.build`, `.git`, `.swiftpm`…) are always skipped.

## A rule

```swift
import LLMCheck
import Testing

extension RuleCategory {
  static let logging = RuleCategory("logging", description: "Logging and secrets. Read before you log anything.")
}

extension Rule {
  static let noPrint = Rule(
    id: "no-print",
    title: "The app never calls print.",
    category: .logging,
    rationale: "print output is lost in a shipped app and cannot be private.",
    howToFix: "Use a `Logger(subsystem:category:)` and interpolate with `privacy: .private`.",
    badExample: #"print("loaded \(url)")"#,
    goodExample: #"logger.debug("loaded \(url, privacy: .private)")"#
  )
}

@Suite struct LoggingRules {
  @Test func noPrint() throws {
    let calls = try Codebase().productionCode.in("/Sources").calls(named: "print").filter { $0.node.receiver == nil }
    expectNone(calls, rule: .noPrint)
  }
}
```

## Scopes

```swift
let codebase = try Codebase()            // or Codebase(root: url)
codebase.productionCode                  // everything that is not test code
codebase.testCode                        // under a folder ending in Tests or named Fixtures
codebase.allCode
  .in("Packages/Features")               // several patterns are a union, chained calls narrow
  .excluding("DocumentFeature", "*.generated.swift")
  .containing("@Reducer")                // only files whose raw text contains this, before parsing
Scope(files: [SourceFile(path: "A.swift", source: "…")])  // in-memory, to test a rule
```

`in(_:)`, `excluding(_:)` and `excludes` read a pattern the same way, like a `.gitignore` line:

| Pattern | Matches |
|---|---|
| `Models`, `Legacy.swift` | a folder or file with that name, at any depth |
| `Packages/Features` | that path from the root, and everything under it |
| `/Sources` | the top-level `Sources` folder only |
| `*Tests`, `*.generated.swift`, `Sources/*/Models` | `*` is any run of characters inside one path component |

## Queries

**Declarations.** `structs`, `classes`, `enums`, `actors`, `protocols`, `extensions`, `functions` and `variables`
include nested ones. `topLevelDeclarations` and `declarations(.enumCase)` are also available. Each `Declaration` has
`kind`, `name`, `qualifiedName`, `attributes`, `modifiers`, `inheritance`, `children`, `parent`, `file`, `location`
(at the `struct`/`func`… keyword, not the attributes) and `syntax`.

```swift
let reducers = codebase.productionCode.containing("@Reducer").structs.withAttribute("Reducer")
let states = reducers.flatMap(\.structs).named("State")
expectAll(states, rule: .stateIsObservable) { $0.hasAttribute("ObservableState") }

let actions = reducers.flatMap(\.enums).named("Action").filter { $0.cases.contains { $0.name == "view" } }
expectAll(actions, rule: .actionsAreSplit) { $0.inherits(from: "ViewAction") }
```

**Any node, anywhere.** `nodes(of:)` searches the whole tree, including closures, `await`, `try`, `return`, `switch`
and `#if`. It returns `Match`es with the `node`, its `file`, `location` and `snippet`.

```swift
scope.nodes(of: ForceUnwrapExprSyntax.self)
scope.nodes(of: CodeBlockItemSyntax.self) { $0.node.item.is(ExprSyntax.self) }
```

**Helpers for the common cases.**

```swift
scope.calls(named: "withKnownIssue")         // `await withKnownIssue { }`, `return .run { await f() }`…
scope.calls(named: names)                    // a Set<String> built at run time
call.node.calledName                         // "apply" in `edit.apply(to: &doc)`
call.node.receiver                           // `edit`; nil for `print(x)`
call.node.argument(labeled: "database")      // `database: db` in `load(r, database: db)`
call.node.passesClosure                      // `db.read { }`, `run(work: { })`
call.node.isAwaited                          // `try await f()`, `(try? await f()) ?? []`; not `Task { f() }`
scope.imports(of: "Foundation", "Yams")      // `import Foundation`, `import struct Foundation.URL`, in `#if` too
scope.imports                                // every import; `import.node.moduleName` is `Foundation`
node.enclosingIfConfigClauses                // the `#if`/`#elseif`/`#else` clauses around a node, innermost first
clause.ifCondition, clause.isElse            // `canImport(FoundationEssentials)` and true for that `#if`'s `#else`
scope.references(to: "URLSession", "FileManager")  // code only: comments and strings never match
statement.node.attachedComments              // the comments above a node and the one at the end of its line
scope.references(to: "CommandLine") + calls.map(\.erased)  // matches of different node types, for one rule
```

**SwiftSyntax is not re-exported.** `import LLMCheck` is enough for scopes, declarations, `calls(named:)`,
`references(to:)`, `calledName`, `receiver` and the members of the nodes they return (`call.node.arguments`). A file
that names a node type, such as `nodes(of: ForceUnwrapExprSyntax.self)` or `.is(InOutExprSyntax.self)`, adds
`import SwiftSyntax`, and the test target lists the product:

```swift
dependencies: [
  .package(url: "https://github.com/mackoj/swift-llm-check.git", from: "0.4.1"),
  .package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.0"..<"700.0.0"),
],
targets: [
  .testTarget(name: "ArchitectureTests", dependencies: [
    .product(name: "LLMCheck", package: "swift-llm-check"),
    .product(name: "SwiftSyntax", package: "swift-syntax"),
  ])
]
```

Why not re-export: SwiftSyntax and Testing both declare `SourceLocation`, so a re-export made every rule file that
imports Testing write `Testing.SourceLocation`. Now only a file that imports both modules itself sees the clash.

## Assertions and baselines

`expectNone(findings, rule:baseline:)` records one issue per finding. `expectAll(items, rule:baseline:) { … }` records
one per item that fails the predicate. Both return a `CheckResult`. `rule.check(findings, baseline:)` computes the same
result without recording anything, for your own reporting.

**XCTest.** Inside an `XCTestCase`, the same calls are methods that record XCTest failures at the violation's file
and line, and stale baseline entries at the call site:

```swift
import LLMCheck
import XCTest

final class LoggingRules: XCTestCase {
  func testNoPrint() throws {
    let calls = try Codebase().productionCode.calls(named: "print").filter { $0.node.receiver == nil }
    expectNone(calls, rule: .noPrint)
  }
}
```

A baseline lets a rule land before every violation is fixed. An entry is a file name (`Sidebar.swift`), a path or the
end of one (`Feature/Sidebar.swift`), or a file and a declaration (`Sidebar.swift:SidebarFeature.State`, which covers
anything nested in it). **An entry that no longer matches any finding fails as stale**, so baselines only shrink.

To start one, build it from today's findings and paste the output into the test once:

```swift
print(Baseline(covering: findings).swiftArrayLiteral)   // ["Sidebar.swift:SidebarFeature.State", …]
```

`Baseline(covering:)` names each finding's file and innermost declaration, so a new violation elsewhere in the same
file still fails.

## Rules for agents before they fail

`RuleCatalog` renders rules as Markdown, one section per category, for an `AGENTS.md` section or a `SKILL.md`.
`expectFile` keeps the generated file in step with the rules. It fails when the file is out of date, and
`LLM_CHECK_RECORD=1 swift test` rewrites it.

```swift
@Test func rulesMarkdownIsUpToDate() throws {
  let catalog = RuleCatalog([.noPrint, .stateIsObservable])
  #expect(catalog.duplicateIDs.isEmpty)
  try expectFile("docs/RULES.md", in: Codebase(), matches: catalog.markdown(title: "Architecture rules"))
}
```

## Speed and concurrency

- A codebase lists its files once per process. Each file is read once and parsed at most once per process, whatever
  number of scopes, rules and suites read it.
- The caches are thread-safe and never wait on one another: one lock guards a table, and a per-file lock is held only
  while that file is parsed. Swift Testing's parallel suites are safe, and a stress test hammers the cache from 64
  concurrent tasks in two parallel suites.
- Parsing runs on every core. `calls(named:)` and `references(to:)` skip files whose raw text does not contain the
  name, and `containing(_:)` does the same for declaration queries. Unread files are never parsed. The text search is
  a byte search, 13 times faster than `String.contains`.
- Each node-type search runs once per file and is cached; `references(to:)` searches its three node types in one walk.
  Declarations are built on every core too.
- A parsed file keeps its text, its tree and a table of line starts, nothing more: locations and snippets are read
  from them.

On [Telaio](https://github.com/mackoj/telaio), 992 files and 220,000 lines, eight rules run in 0.7 s (2.4 s wall time
for a built `swift test`). The same rules on Harmonize took 35 s. Reading and parsing the whole tree cold takes 2.6 s
in a debug build, almost all of it in swift-syntax's parser, which is unoptimized in debug; the rules stay fast because
`containing(_:)` keeps most files unparsed. `swift test -c release` parses the whole tree in 0.05 s and runs the eight
rules in 0.15 s, but compiling swift-syntax optimized adds about 100 s to a clean build, so it pays only where the
build is cached.

### Benchmarks

`Benchmarks/` measures the library on [ordo-one/benchmark](https://github.com/ordo-one/benchmark) (see
[Swift.org's introduction](https://www.swift.org/blog/benchmarks/)), on swift-syntax's own `Sources`: 321 files,
6.6 MB. It is a separate package, built against the working copy, so the library never depends on it. It needs macOS
15 and jemalloc (`brew install jemalloc`).

```sh
swift package --package-path Benchmarks benchmark
# Compare a change against main:
git switch main && swift package --package-path Benchmarks --allow-writing-to-package-directory benchmark baseline update main
git switch - && swift package --package-path Benchmarks benchmark baseline compare main
# Profile one benchmark with Instruments' Time Profiler; the optional focus counts only the samples under a function:
Benchmarks/scripts/profile.sh 'Declarations, swift-syntax' 25 'DeclarationBuilder.make'
```

Median wall clock on an 18-core Apple silicon Mac, release build, before and after the changes they were written for
(2026-11-14):

| Benchmark (swift-syntax `Sources`) | Before | Now | Allocations |
|---|---|---|---|
| Parse every file | 408 ms | 272 ms | 444 k → 316 k |
| Declarations, first read | 114 ms | 28 ms | 1.42 M → 103 k |
| `calls(named:)`, first read | 321 ms | 52 ms | |
| `references(to:)`, first read | 419 ms | 100 ms | |
| `imports(of:)`, first read | 199 ms | 36 ms | |
| `containing(_:)` | 258 ms | 13 ms | |
| Attached comments of every function | 124 ms | 34 ms | 1.48 M → 162 k |
| Five rules on a cold codebase | listed no files (symbolic-link root) | 160 ms | |

Parsing peaks at 228 MB instead of 254 MB. A first `nodes(of:)` search on a file costs a little more than before
(76 ms against 63 ms here): swift-syntax builds a tree's node data on its first walk, which used to happen while
parsing. Parsing and a first search together take 348 ms instead of 470 ms.

## swift-syntax versions

The range is `601.0.0..<700.0.0`.

- **Lower bound 601** (Swift 6.1). CI builds and tests against 601.0.1 as well as the newest release. The test suite
  also passes pinned to 602.0.0, 603.0.2 and 604.0.0.
- **Upper bound below 700.** swift-syntax releases one major per Swift release (601, 602, 603, 604…). An app's
  macros, such as TCA's, often require the newest one. A narrow cap like Harmonize's `..<605` would hold the app back
  as soon as 605 ships. LLMCheck uses only the parser, `SyntaxVisitor`, `SourceLocationConverter` and the
  long-standing declaration and expression nodes, which have been source-compatible across 601 to 604. Each new major
  is covered by CI when it ships. If a future major breaks LLMCheck, the fix is a patch release that tightens or
  adapts, not an app blocked in the meantime.

## Compared with Harmonize

[Harmonize](https://github.com/perrystreetsoftware/Harmonize) inspired this library: its 2.0 `Rule` text at the
violation is the part that helps agents most. swift-llm-check keeps that and changes the rest:

| | Harmonize 2.0.0-beta.2 | swift-llm-check |
|---|---|---|
| Parallel suites | Deadlock when two suites warm the cache (`.serialized` needed) | Safe, stress-tested |
| Calls | `functionCalls` sees whole-statement calls only | `nodes(of:)`/`calls(named:)` search the whole tree |
| Location | File-level matches report line 1 | Exact line and column, with the offending line |
| Swift 6 | Types not `Sendable` (`@preconcurrency import`) | Everything `Sendable` |
| Speed (Telaio, 8 rules, debug) | 35 s | 0.7 s |
| swift-syntax | `601..<605` | `601..<700` |
| Baselines | File names, fail when stale | File names, paths or `File.swift:Decl`, fail when stale |
| XCTest | Assertions | Assertions, at the violation's file and line |
| Dependencies | swift-syntax, Yams | swift-syntax |

Harmonize has a larger declaration model (properties, accessors, function bodies as objects).
swift-llm-check stays small and gives you the SwiftSyntax node when you need more.

## In use

[Telaio](https://github.com/mackoj/telaio), [forum-offline](https://github.com/mackoj/forum-offline),
[swift-arazzo](https://github.com/mackoj/swift-arazzo), [swift-jsonpath](https://github.com/mackoj/swift-jsonpath)
and swift-llm-check itself (`Architecture/`) run their rules on swift-llm-check.
[docs/adoption-notes.md](docs/adoption-notes.md) compares how each set it up, the recipe they share, and the helpers
that moved from their rules into the library.

## Development

```sh
xcrun swift test
xcrun swift test --package-path Architecture
xcrun swift-format lint --strict -r Package.swift Sources Tests Architecture/Package.swift Architecture/Tests \
  Benchmarks/Package.swift Benchmarks/Benchmarks Benchmarks/Tools
swift package --package-path Benchmarks benchmark   # see "Benchmarks"
```

The library checks itself. `Architecture/` holds swift-llm-check's own rules, written with the working copy of the
library: the dependency budget, no re-export, `Sendable` public types, locks only in `Support/Locked.swift`, no
`print`, and how its tests use XCTest and `withKnownIssue`. They are listed in
[docs/architecture-rules.md](docs/architecture-rules.md), generated from the rules.
