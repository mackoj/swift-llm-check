import Foundation

/// A folder of Swift files, from its root (where `.llm-check.yaml` is) down.
///
/// ```swift
/// let codebase = try Codebase()  // walks up from this test file to .llm-check.yaml
/// let reducers = codebase.productionCode.in("Packages/Features").structs.withAttribute("Reducer")
/// ```
///
/// A codebase lists its files once per process and every file is parsed once per process, however many scopes and
/// suites read it, in parallel or not.
public struct Codebase: Sendable {
  /// The folder that holds the marker file.
  public let root: URL
  public let configuration: Configuration

  /// A codebase rooted at `root`. Without a configuration, reads the marker file there if there is one.
  public init(root: URL, configuration: Configuration? = nil) throws {
    let root = root.standardizedFileURL
    self.root = root
    if let configuration {
      self.configuration = configuration
    } else {
      let marker = root.appendingPathComponent(Configuration.markerFileName)
      if let yaml = try? String(contentsOf: marker, encoding: .utf8) {
        self.configuration = try Configuration(yaml: yaml)
      } else {
        self.configuration = Configuration()
      }
    }
  }

  /// The codebase whose root is the nearest folder above `filePath` that holds the marker file.
  ///
  /// - Parameters:
  ///   - filePath: where to start; the calling file by default.
  ///   - marker: the file that marks the root.
  public init(filePath: String = #filePath, marker: String = Configuration.markerFileName) throws {
    // Walk the folder's components up to "/", without relying on how `deletingLastPathComponent()` treats the root.
    var components = URL(fileURLWithPath: filePath).deletingLastPathComponent().standardizedFileURL.pathComponents
    while !components.isEmpty {
      let folder = URL(fileURLWithPath: NSString.path(withComponents: components), isDirectory: true)
      let candidate = folder.appendingPathComponent(marker)
      if FileManager.default.fileExists(atPath: candidate.path) {
        let yaml = try String(contentsOf: candidate, encoding: .utf8)
        try self.init(root: folder, configuration: Configuration(yaml: yaml))
        return
      }
      components.removeLast()
    }
    throw MarkerNotFound(start: filePath, marker: marker)
  }

  /// Every file that is not test code.
  public var productionCode: Scope { Scope(codebase: self, kind: .production) }
  /// Every file under a test folder: a path component ending in `Tests` or named `Fixtures` by default.
  public var testCode: Scope { Scope(codebase: self, kind: .test) }
  /// Every file.
  public var allCode: Scope { Scope(codebase: self, kind: .all) }

  /// The Swift files under the root, relative to it and sorted, without hidden folders, `.build` or excludes.
  public var relativePaths: [String] {
    let key = "\(root.path)|\(configuration.excludes.joined(separator: ","))"
    let once = Codebase.listings.withLock { listings in
      if let once = listings[key] { return once }
      let once = Once<[String]>()
      listings[key] = once
      return once
    }
    return once.value { Self.list(root: root, excludes: configuration.excludes) }
  }

  /// The parsed file at a path relative to the root, from the process-wide cache.
  public func file(_ relativePath: String) -> SourceFile? {
    ParseCache.file(root: root, relativePath: relativePath)
  }

  private static let listings = Locked<[String: Once<[String]>]>([:])

  private static func list(root: URL, excludes: [String]) -> [String] {
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard
      let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else { return [] }
    var paths: [String] = []
    for case let url as URL in enumerator {
      let path = url.standardizedFileURL.path
      guard path.hasPrefix(rootPath) else { continue }
      let relative = String(path.dropFirst(rootPath.count))
      let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      if excludes.contains(where: { PathPattern.matches($0, relative) }) {
        if isDirectory { enumerator.skipDescendants() }
        continue
      }
      if !isDirectory && url.pathExtension == "swift" { paths.append(relative) }
    }
    return paths.sorted()
  }
}

/// No folder above the starting file holds the marker file.
public struct MarkerNotFound: Error, CustomStringConvertible {
  public let start: String
  public let marker: String

  public var description: String {
    "No \(marker) in any folder above \(start). Create one at the root of the code to check, for example with "
      + "`excludes: [build]`."
  }
}
