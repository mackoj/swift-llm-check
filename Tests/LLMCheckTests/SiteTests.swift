import Foundation
import Testing

/// `site/index.html`, the GitHub Pages landing page, quotes the README in its `data-readme` blocks. A README change
/// that leaves the page behind fails here.
@Suite struct SiteTests {
  @Test func sitePageQuotesTheReadme() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
    let page = try String(contentsOf: root.appendingPathComponent("site/index.html"), encoding: .utf8)

    let blocks = page.components(separatedBy: " data-readme>").dropFirst().map { block in
      String(block.prefix { $0 != "<" })
        .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
    }
    let readmeLines = Set(readme.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
    let strayLines = blocks.flatMap { $0.split(separator: "\n").map(String.init) }.filter {
      !readmeLines.contains($0)
    }

    #expect(blocks.count == 9)
    #expect(strayLines == [])
  }
}
