import Foundation
import Testing

@testable import LLMCheck

@Suite struct ConfigurationTests {
  @Test func readsBlockAndFlowLists() throws {
    let configuration = try Configuration(
      yaml: """
        # comment
        excludes:
          - build   # trailing comment
          - "Packages/Legacy"
        testSuffixes: [Tests, Specs]
        testFolders: []
        """)
    #expect(configuration.excludes == ["build", "Packages/Legacy"])
    #expect(configuration.testSuffixes == ["Tests", "Specs"])
    #expect(configuration.testFolders == [])
  }

  @Test func defaultsWhenKeysAreMissing() throws {
    let configuration = try Configuration(yaml: "excludes:\n")
    #expect(configuration == Configuration())
  }

  @Test func rejectsUnknownKeysAndScalars() {
    #expect(throws: ConfigurationError.self) { try Configuration(yaml: "exclude:\n  - build") }
    #expect(throws: ConfigurationError.self) { try Configuration(yaml: "excludes: build") }
    #expect(throws: ConfigurationError.self) { try Configuration(yaml: "- build") }
  }

  @Test func testCodeIsAFolderEndingInTestsOrNamedFixtures() {
    let configuration = Configuration()
    #expect(configuration.isTestCode("Packages/Kit/Tests/KitTests/A.swift"))
    #expect(configuration.isTestCode("AppUITests/A.swift"))
    #expect(configuration.isTestCode("Sources/Fixtures/A.swift"))
    #expect(!configuration.isTestCode("Sources/App/ATests.swift"))
    #expect(!configuration.isTestCode("Sources/TestsHelpers/A.swift"))
  }
}

@Suite struct PathPatternTests {
  @Test(arguments: [
    ("build", "build/A.swift", true),
    ("build", "Sources/build/A.swift", true),
    ("build", "Rebuild/A.swift", false),
    ("A.swift", "Sources/A.swift", true),
    ("Packages/Foo", "Packages/Foo/Sources/A.swift", true),
    ("Packages/Foo", "Other/Packages/Foo/A.swift", false),
    ("Packages/Foo/", "Packages/Foo/A.swift", true),
    ("*Tests", "Packages/KitTests/A.swift", true),
    ("*.generated.swift", "Sources/A.generated.swift", true),
    ("Pack*/Foo", "Packages/Foo/A.swift", true),
    ("a*b*c", "aXbYc/x.swift", true),
    ("a*b*c", "aXcYb/x.swift", false),
  ])
  func matches(pattern: String, path: String, expected: Bool) {
    #expect(PathPattern.matches(pattern, path) == expected)
  }

  @Test func anchoredPatternsMatchFromTheRoot() {
    #expect(PathPattern.matches("Sources", "Sources/A.swift", anchored: true))
    #expect(!PathPattern.matches("Sources", "Packages/Kit/Sources/A.swift", anchored: true))
    #expect(PathPattern.matches("Sources/A.swift", "Sources/A.swift", anchored: true))
  }
}

@Suite struct CodebaseTests {
  @Test func findsTheRootFromAFileBelowIt() throws {
    let codebase = try Fixture.codebase()
    #expect(codebase.root.path == Fixture.root.standardizedFileURL.path)
    #expect(codebase.configuration.excludes == ["build", "Generated.swift"])
  }

  @Test func failsWithoutAMarker() {
    #expect(throws: MarkerNotFound.self) {
      try Codebase(filePath: "/no/such/place/File.swift", marker: ".llm-check-missing.yaml")
    }
  }

  @Test func skipsHiddenFoldersAndExcludes() throws {
    #expect(
      try Fixture.codebase().relativePaths == [
        "Packages/Kit/Sources/Kit/Kit.swift",
        "Sources/App/Feature.swift",
        "Sources/App/Legacy.swift",
        "Sources/Model/Item.swift",
        "Tests/AppTests/FeatureTests.swift",
        "Tests/Fixtures/Input.swift",
      ])
  }

  @Test func skipsDotBuild() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("llm-check-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    for path in [".build/checkouts/Dep/A.swift", "Sources/B.swift", "Sources/.swiftpm/C.swift"] {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try "let x = 1".write(to: url, atomically: true, encoding: .utf8)
    }
    #expect(try Codebase(root: root).relativePaths == ["Sources/B.swift"])
  }

  @Test func splitsProductionAndTestCode() throws {
    let codebase = try Fixture.codebase()
    #expect(codebase.testCode.relativePaths == ["Tests/AppTests/FeatureTests.swift", "Tests/Fixtures/Input.swift"])
    #expect(codebase.productionCode.relativePaths.count == 4)
    #expect(codebase.allCode.relativePaths.count == 6)
  }

  @Test func narrowsWithInAndExcluding() throws {
    let production = try Fixture.codebase().productionCode
    #expect(
      production.in("Sources").excluding("Legacy.swift").relativePaths == [
        "Sources/App/Feature.swift", "Sources/Model/Item.swift",
      ])
    #expect(production.in("Sources/App", "Packages").relativePaths.count == 3)
    #expect(production.in("Sources").in("Sources/Model").relativePaths == ["Sources/Model/Item.swift"])
    #expect(production.excluding("Sources/App").relativePaths.count == 2)
    #expect(production.in("Kit").relativePaths.isEmpty, "in(_:) matches from the root")
    #expect(production.in("Nowhere").files.isEmpty)
  }

  @Test func filesCarryTheirRelativePath() throws {
    let file = try #require(try Fixture.codebase().productionCode.in("Sources/Model").files.first)
    #expect(file.relativePath == "Sources/Model/Item.swift")
    #expect(file.fileName == "Item.swift")
    #expect(file.path.hasSuffix("/Fixtures/SampleApp/Sources/Model/Item.swift"))
  }
}
