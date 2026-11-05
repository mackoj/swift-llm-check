import Testing

@Test func knownIssue() async {
  await withKnownIssue {
    Issue.record("flaky")
  }
}
