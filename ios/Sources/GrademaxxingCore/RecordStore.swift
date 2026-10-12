import Foundation
import Observation

/// Per-resource in-memory state. Invalidation prevents a completed old request
/// from reintroducing data after sign-out, account change, or calendar navigation.
@MainActor @Observable
public final class RecordStore<Value: Sendable> {
  public var value: Value?
  public var isLoading = false
  public var error: String?
  public var updatedAt: Date?
  @ObservationIgnored private var generation = 0
  public init() {}

  public func load(
    force: Bool = false, maxAge: TimeInterval = 1_800,
    fetch: () async throws -> Value, onFailure: (Error) -> Void
  ) async {
    guard !isLoading else { return }
    if !force, value != nil, let updatedAt, Date().timeIntervalSince(updatedAt) < maxAge { return }
    let version = generation
    isLoading = true
    error = nil
    defer { if version == generation { isLoading = false } }
    do {
      let result = try await fetch()
      try Task.checkCancellation()
      guard version == generation else { return }
      value = result
      updatedAt = Date()
    } catch {
      guard version == generation, !(error is CancellationError) else { return }
      self.error =
        (error as? APIError)?.errorDescription ?? "The school record could not load. Try again."
      onFailure(error)
    }
  }

  public func clear() {
    generation += 1
    value = nil
    isLoading = false
    error = nil
    updatedAt = nil
  }
}
