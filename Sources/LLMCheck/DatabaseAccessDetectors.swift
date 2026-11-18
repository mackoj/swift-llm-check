import SwiftSyntax

extension Scope {
  /// Closure-literal member `read`, `write`, `writeWithoutTransaction`, `barrierWriteWithoutTransaction`,
  /// `unsafeRead`, `unsafeReentrantRead`, `unsafeReentrantWrite` and `inDatabase` calls with no lexical `await`,
  /// in files that import GRDB or SQLiteData. Imports are parsed, including qualified and conditional imports;
  /// a comment or string mentioning an import does not qualify a file.
  ///
  /// This describes syntax, not the current thread or overload. Receiver types are not resolved; unrelated
  /// closure-taking methods in the same file can also match. Synchronous setup, migrations, tests and deliberate
  /// background work can be valid. Some unsafe methods have no async overload and need a different API, not `await`.
  public var synchronousDatabaseAccess: [Match<FunctionCallExprSyntax>] {
    let databaseFiles = Set(imports(of: "SQLiteData", "GRDB").map(\.file))
    let scope = Scope(files: files.filter { databaseFiles.contains($0) })
    return scope.calls(
      named: "read", "write", "writeWithoutTransaction", "barrierWriteWithoutTransaction", "unsafeRead",
      "unsafeReentrantRead", "unsafeReentrantWrite", "inDatabase"
    ).filter { $0.node.receiver != nil && $0.node.passesClosure && !$0.node.isAwaited }
  }

  /// Member `start(in:scheduling:)` or `publisher(in:scheduling:)` calls with `scheduling: .immediate` or an
  /// explicitly qualified `.immediate` member. The scheduler expression itself must be that member: strings,
  /// `.immediateIfPossible`, factory calls and `.async(onQueue: queueNamedImmediate)` do not match.
  ///
  /// Immediate first delivery is a supported GRDB choice. Use this for an opt-in rule about synchronous first
  /// observation values; it is not inherently an error. Scope to database code because types are not resolved.
  public var immediateDatabaseObservations: [Match<FunctionCallExprSyntax>] {
    calls(named: "start", "publisher").filter { match in
      let call = match.node
      guard call.receiver != nil, call.argument(labeled: "in") != nil,
        let scheduler = call.argument(labeled: "scheduling")?.expression.as(MemberAccessExprSyntax.self)
      else { return false }
      return scheduler.declName.baseName.text == "immediate"
    }
  }
}
