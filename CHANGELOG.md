# Changelog

All notable changes to swift-llm-check. The project follows [Semantic Versioning](https://semver.org); before 1.0, a
minor release may break source compatibility, and each break is listed under **Breaking** with how to migrate.

## Unreleased

### Added

- Built-in detectors on `Scope`, the checks every adopting repository copied from swift-arazzo with their tests:
  `xcTestImports`, `disabledTests` (`.disabled` in a `@Test` or `@Suite` attribute), `unexplainedKnownIssues`
  (`withKnownIssue` without a reason string first), `unexplainedExpectedFailures` (the same for `XCTExpectFailure`),
  `uncommentedUncheckedSendable`, `forcedTries`, `optionalTries`, `forcedCasts` and `forceUnwraps`. Each returns the
  matches; the `Rule` stays the repository's own. `uncommentedUncheckedSendable` counts only `//` and `/* */`
  comments, so a doc comment no longer passes, and sees the comment at the end of the line that opens the body or
  before its first member. `forcedCasts` finds `as!` in parsed code, where SwiftParser leaves it unfolded as an
  `UnresolvedAsExprSyntax`; the README's new "Unfolded expressions" says which nodes arrive that way.
- `Declaration.isPublic`, `attribute(_:)` and `attributes(_:)` (the `AttributeSyntax`, with its arguments, for
  `@available(…)` rules), and `genericParameters` (`GenericParameter`: name, constraint as written, and every
  conformance from the constraint and the `where` clause).
- `Declaration.contains(_:)`, `calls(named:)` and `nodes(of:)` search one declaration's code, so two types in one file
  are told apart; `contains` skips comments and string literals.
- `SourceFile.module`: the target folder under `Sources`, `Tests` or `Plugins`, for per-module import budgets.
- `Scope.topLevelStatements(notUnder:)`: what sits outside a whole-file `#if <condition>` with no `#else`, for rules
  such as "every file in this target is wrapped in `#if canImport(Security)`".
- `firstDescendant(of:)` and `descendants(of:)` on any node, and `TypeSyntax.closureType` and `hasAttribute(_:)`,
  which see through attributes, optionals and parentheses to a closure type and its `@Sendable`.

### Changed

- Faster, measured by the new `Benchmarks/` package on swift-syntax's own sources: parsing 1.5x, declarations 4x
  with 14x fewer allocations, `calls(named:)` 6x, `references(to:)` 4x, `imports(of:)` 5.5x, `containing(_:)` 20x.
  A parsed file keeps one copy of its text instead of three. README, "Benchmarks", has the table.

### Fixed

- A codebase whose root is a symbolic link lists its files. It listed none: `FileManager`'s enumerator does not
  descend into a link.
- `Declaration.inherits(from:)` sees through an attribute in the inheritance clause: `@unchecked Sendable` inherits
  from `Sendable`, `@retroactive Identifiable` from `Identifiable`. It returned false, so a rule such as "public types
  are `Sendable`" flagged a type declared `@unchecked Sendable`. `inheritance` still lists the clause as written.

## 0.4.1 (2026-11-13)

### Added

- `Match.erased` turns a `Match<FunctionCallExprSyntax>` (or any node type) into a `Match<Syntax>`, so one rule can
  report `references(to:)`, `calls(named:)` and `nodes(of:)` findings together. Replaces the hand-written
  `Match(node: Syntax($0.node), file: $0.file)` in swift-arazzo's and swift-jsonpath's no-I/O rules.

## 0.4.0 (2026-11-13)

### Added

- `Scope.imports` and `Scope.imports(of:)` find `import` declarations, inside `#if` blocks too, and
  `ImportDeclSyntax.moduleName` reads `Foundation` from `import struct Foundation.URL`. For rules such as "the core
  target imports only its declared dependencies".
- `enclosingIfConfigClauses` on any node lists the `#if`/`#elseif`/`#else` clauses it is compiled under, and
  `IfConfigClauseSyntax.ifCondition` and `isElse` say which branch of which `#if` a clause is. For rules such as
  "`import Foundation` only as the `#else` of `#if canImport(FoundationEssentials)`".

## 0.3.0 (2026-11-10)

### Added

- `isAwaited` on any node: whether it sits under an `await` in its own expression (`try await f()`,
  `(try? await f()) ?? []`). The search stops at the enclosing statement, closure or declaration, so a call inside
  `Task { }` or inside an awaited call's closure is not awaited. For rules such as "database access is awaited".
- `FunctionCallExprSyntax.argument(labeled:)` returns the argument with a label, and `passesClosure` says whether a
  closure is passed, trailing or as an argument.
- `Scope.calls(named:)` takes a `Set<String>`, for a list of names built at run time.
- `Baseline(covering:)` builds a baseline that accepts exactly the given findings, one `File.swift:Declaration` entry
  each, and `swiftArrayLiteral` renders it for pasting into a test. It lands a rule on code that already breaks it
  without hand-writing the entries.

## 0.2.0 (2026-11-06)

### Breaking

- **`import LLMCheck` no longer re-exports SwiftSyntax.** SwiftSyntax and Testing both declare `SourceLocation`, so the
  re-export forced every rule file that imports Testing to write `Testing.SourceLocation`. Scopes, declarations,
  `calls(named:)`, `references(to:)`, `calledName`, `receiver` and the members of returned nodes still work with
  `import LLMCheck` alone. To migrate, a file that names a node type (`CodeBlockItemSyntax`, `InOutExprSyntax.self`,
  `.is(StringLiteralExprSyntax.self)`…) adds `import SwiftSyntax`, and its test target adds the product:

  ```swift
  .package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.0"..<"700.0.0"),
  // …
  .product(name: "SwiftSyntax", package: "swift-syntax"),
  ```

- **`Scope.in(_:)` reads patterns like `excluding(_:)` and `excludes`.** A name without a slash now matches a folder or
  file at any depth, as it already did for exclusions; a path with a slash still matches from the root. `in("Sources")`
  used to mean the top-level `Sources` folder only; it now also matches `Packages/Kit/Sources`. To keep the old
  meaning, anchor the name with a leading slash: `in("/Sources")`. Paths with a slash (`in("Packages/Features")`) are
  unchanged.

### Added

- XCTest assertions: inside an `XCTestCase`, `expectNone(_:rule:baseline:)` and `expectAll(_:rule:baseline:_:)` are
  methods that record an XCTest failure at each violation's file and line, and stale baseline entries at the call
  site. `record(_:)` reports a `CheckResult` the same way.
- `SourceFile` is `Hashable`, so rules can write `declaration.file == other.file` or build a `Set` of files. Equality
  is identity: a codebase parses each path once per process, so its files compare like their paths, while in-memory
  files made separately differ even with the same path.
- A leading slash anchors a single name at the root (`/Sources`). It worked in `excluding(_:)` and `excludes` by
  accident; it is now documented and tested for all three.

### Fixed

- Files with CRLF (`\r\n`) or CR line endings: snippets were empty past line 1, because `"\r\n"` is a single Swift
  `Character` and lines were split on `"\n"` only. A CRLF `.llm-check.yaml` failed to parse for the same reason.
- `.llm-check.yaml`: a comment after a tab (`- build\t# why`) is stripped like one after a space.

### Performance

- Declarations are built on every core. On Telaio (992 files, 220,000 lines) in a debug build, every declaration of
  the whole tree takes 0.18 s instead of 0.78 s.

## 0.1.0

First release: rules as Swift Testing tests with agent-friendly failures, scopes, declaration and node queries,
baselines that fail when stale, `RuleCatalog` and `expectFile`, and a process-wide parse cache safe under parallel
suites.
