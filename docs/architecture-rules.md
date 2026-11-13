# Architecture rules

swift-llm-check's own rules, enforced on this repository by the `Architecture/` package with the library itself: `swift test --package-path Architecture`. Each rule cites the README or CHANGELOG promise it keeps. Generated from the rules; do not edit by hand.

## dependencies

What the library imports and exports. Read before you add an `import` to `Sources`.

### `Sources` imports only Foundation, Dispatch, SwiftSyntax, SwiftParser, Testing and XCTest.

`sources-import-their-budget`: The only dependency is swift-syntax (README, "Requirements"), and only its parser and syntax tree (README, "swift-syntax versions"): that is what lets the library accept every swift-syntax from 601 to below 700, and never hold back an app whose macros need the newest one. Another swift-syntax module (SwiftSyntaxBuilder, SwiftOperators, SwiftDiagnostics) or another package narrows the range or adds to every adopter's build.

**How to fix:** Write it with the parser and `SyntaxVisitor`, as the rest of `Sources` is. A new module is a decision for the maintainer: add it to `Package.swift`, to `Detect.allowedImports` and to the README's "swift-syntax versions" section in the same change, and check it on swift-syntax 601 (CI's pinned job).

Bad:

```swift
import SwiftSyntaxBuilder
let call = FunctionCallExprSyntax(callee: DeclReferenceExprSyntax(baseName: "print"))
```

Good:

```swift
import SwiftParser
let tree = Parser.parse(source: "print(x)")
```

### `Sources` imports XCTest only inside `#if canImport(XCTest)`.

`xctest-is-conditional`: XCTest is not there everywhere LLMCheck builds: a Swift Testing-only target or a toolchain without it would fail to compile the whole library for the sake of the XCTest assertions (README, "Assertions and baselines"). `XCTestExpectations.swift` compiles them only where XCTest exists.

**How to fix:** Move the code and its import into the `#if canImport(XCTest)` block of `XCTestExpectations.swift`.

Bad:

```swift
import XCTest
extension XCTestCase { public func expectNone(…) }
```

Good:

```swift
#if canImport(XCTest)
  import XCTest
  extension XCTestCase { public func expectNone(…) }
#endif
```

### `Sources` re-exports nothing: no `@_exported import`.

`swiftsyntax-is-not-reexported`: 0.2.0 stopped re-exporting SwiftSyntax (CHANGELOG, 0.2.0, "Breaking"): SwiftSyntax and Testing both declare `SourceLocation`, so the re-export made every rule file that imports Testing write `Testing.SourceLocation`. Re-exporting any module brings that clash, or one like it, back to every adopter.

**How to fix:** Import the module plainly. A rule file that names a node type imports SwiftSyntax itself (README, "SwiftSyntax is not re-exported").

Bad:

```swift
@_exported import SwiftSyntax
```

Good:

```swift
import SwiftSyntax
```

## concurrency

Sendable types and the lock discipline. Read before you add a public type, a lock or a queue.

### A public struct, enum or class is `Sendable`.

`public-types-are-sendable`: Everything is `Sendable` (README, "Compared with Harmonize"): Swift Testing runs suites in parallel, and a rule shares its `Codebase`, `Scope` and findings across them. A public type that is not `Sendable` makes adopters write `@preconcurrency import LLMCheck`, as Harmonize's did; they cannot add the conformance themselves.

**How to fix:** Declare `Sendable` on the type, or conform to a protocol that refines it (`Finding`, `Error`). A generic type declares it in an extension, conditionally on its parameters.

Bad:

```swift
public struct Report {
```

Good:

```swift
public struct Report: Sendable {
```

### An `@unchecked Sendable` conformance has a comment that proves it safe.

`unchecked-sendable-explains-itself`: `@unchecked Sendable` turns off the compiler's data-race check for the type. The comment is the only proof left that it is safe to share, and the caches promise exactly that (README, "Speed and concurrency": "Swift Testing's parallel suites are safe").

**How to fix:** Prefer a `Sendable` value type, or keep the state in `Locked`. If neither fits, put a comment on the declaration that says what guards the mutable state, as `Declaration` and `Locked` do.

Bad:

```swift
final class Cache: @unchecked Sendable {
```

Good:

```swift
// Every access to `storage` holds `lock`.
final class Cache: @unchecked Sendable {
```

### Only `Support/Locked.swift` uses a lock, a semaphore or a dispatch queue.

`locks-stay-in-locked`: The caches never wait on one another (README, "Speed and concurrency"): one lock guards a table, a per-file `Once` is held only while that file is parsed, and nothing that computes a value takes another lock. That holds because every lock is a `Locked` or a `Once` and every fan-out is `concurrentMap`. A lock or a queue elsewhere can be taken inside one of them and deadlock parallel suites, as Harmonize did.

**How to fix:** Keep shared state in `Locked`, compute once with `Once`, and run work on every core with `concurrentMap`. A new primitive goes in `Support/Locked.swift`, with a comment on why it cannot wait on the others. `Mutex` needs macOS 15; the library supports macOS 14.

Bad:

```swift
private let lock = NSLock()
private var trees: [String: SourceFileSyntax] = [:]
```

Good:

```swift
private let trees = Locked<[String: SourceFileSyntax]>([:])
```

## reporting

How the library talks to its user. Read before you write output.

### `Sources` never prints: no `print`, `debugPrint` or `dump`.

`library-prints-nothing`: A violation is reported as a test issue at its file and line, with the rule's full text (README, top): that is where Xcode, `swift test` and an agent look. Text printed by a library run inside a test is interleaved with every parallel suite's output, attached to no test, and lost in Xcode's test navigator.

**How to fix:** Record an issue (`Issue.record` with a `sourceLocation`, or `XCTFail` in the XCTest assertions), or return the text for the caller to use, like `Baseline.swiftArrayLiteral`.

Bad:

```swift
print("stale baseline entry \(entry)")
```

Good:

```swift
Issue.record(Comment(rawValue: staleMessage(for: entry, rule: rule)), sourceLocation: sourceLocation)
```

## testing

The library's own tests. Read before you add a test or mark a known issue.

### Tests use Swift Testing; only `XCTestExpectationsTests.swift` imports XCTest.

`xctest-is-tested-alone`: The library is built for Swift Testing first (README, top: rules are "written as Swift Testing tests"), and its own tests are written the way its users write rules. XCTest is imported in one file, to test the XCTest assertions in an `XCTestCase`, the only place they run.

**How to fix:** Write an `@Suite` of `@Test` functions with `#expect` and `#require`, and `import Testing`.

Bad:

```swift
import XCTest
final class ScopeTests: XCTestCase { func testExcluding() { XCTAssertEqual(…) } }
```

Good:

```swift
import Testing
@Suite struct ScopeTests { @Test func excluding() { #expect(…) } }
```

### `withKnownIssue` names its issue, or pins the issue it expects with `matching:`.

`known-issues-explain-themselves`: A known issue hides a failing expectation. The library's tests use it on purpose, to check that `expectNone`, `expectAll` and `expectFile` record the right issue; there, `matching:` says which issue, and the test fails if another one is recorded. A bare `withKnownIssue { }` accepts any failure, so the next reader cannot tell a check of the recorded issue from a bug nobody understood.

**How to fix:** To check what is recorded, add `matching:` with the file, line or text the issue must have. To silence a bug, pass the reason first, with the GitHub issue that tracks it.

Bad:

```swift
withKnownIssue { expectNone(calls, rule: .sample) }
```

Good:

```swift
withKnownIssue {
  expectNone(calls, rule: .sample)
} matching: { issue in
  issue.sourceLocation?.line == 3
}
```
