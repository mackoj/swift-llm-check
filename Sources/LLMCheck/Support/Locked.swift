import Dispatch
import Foundation

/// A value behind a lock. `Mutex` from Synchronization needs macOS 15, so this uses `NSLock` to keep macOS 14.
final class Locked<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) {
    self.value = value
  }

  func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }
}

/// A value computed at most once, by the first caller; later callers wait for it and share it.
///
/// Each `Once` has its own lock, and nothing that computes a value takes another lock, so two callers can never wait on
/// each other: whoever holds the lock is parsing, not waiting.
final class Once<Value: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value?

  func value(_ make: () -> Value) -> Value {
    lock.lock()
    defer { lock.unlock() }
    if let value { return value }
    let made = make()
    value = made
    return made
  }
}

/// Maps `items` on every core, keeping their order. `transform` must not wait on work that this call schedules.
func concurrentMap<Item: Sendable, Result: Sendable>(
  _ items: [Item],
  _ transform: @Sendable (Item) -> Result
) -> [Result] {
  guard items.count > 1 else { return items.map(transform) }
  let results = Locked([Result?](repeating: nil, count: items.count))
  DispatchQueue.concurrentPerform(iterations: items.count) { index in
    let result = transform(items[index])
    results.withLock { $0[index] = result }
  }
  return results.withLock { $0.map { $0! } }
}
