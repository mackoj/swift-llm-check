# Agent notes

swift-llm-check is a Swift library: architecture and lint rules for Swift codebases, written as Swift Testing tests.
`README.md` is the user documentation; `CHANGELOG.md` lists every change, with breaks and how to migrate.

## Build and test

- `xcrun swift test` runs the library's tests; `Tests/LLMCheckTests/Fixtures/SampleApp` is a sample codebase that
  breaks rules on purpose.
- `xcrun swift test --package-path Architecture` runs the library's own rules, written with the library (the working
  copy, so your change is checked by the rules it touches). They are listed in `docs/architecture-rules.md`. A failure
  prints the rule, why it exists and how to fix it: fix the code, never add a baseline. A new or changed rule needs its
  rationale citing the README or CHANGELOG, bad and good examples, a `DetectorTests` case, and
  `LLM_CHECK_RECORD=1 xcrun swift test --package-path Architecture` to regenerate the document.
- Benchmarks: `swift package --package-path Benchmarks benchmark` (README, "Benchmarks"; needs jemalloc). A change
  made for speed or memory states its before and after from `benchmark baseline compare main` in the pull request; a
  change to a hot path (parsing, `nodes(of:)`, declarations, text filters, locations) checks it did not regress.
  `Benchmarks/scripts/profile.sh '<name>' [count] [focus]` shows where a benchmark spends its time.
- Format check: `xcrun swift-format lint --strict -r Package.swift Sources Tests Architecture/Package.swift
  Architecture/Tests Benchmarks/Package.swift Benchmarks/Benchmarks Benchmarks/Tools` (config in `.swift-format`).

## Docs travel with code

In the same change as any API or behaviour change: the doc comment on each public declaration you touch, every README
section and example it affects, and a `CHANGELOG.md` entry under "Unreleased".
