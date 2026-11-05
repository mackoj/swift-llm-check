public enum Kit {
  public static func load() async throws -> Data {
    try await URLSession.shared.data(from: URL(string: "https://example.com")!).0
  }
}
