import Foundation

public enum GradebookReadMode: Sendable, Equatable { case fresh, summary }
public struct GradebookSnapshot: Sendable {
  public let book: Gradebook
  public let checkedAt: Date
  public let fullReadAt: Date?
}

/// Bounded in-memory snapshots, separated by the opaque signed-in session.
@MainActor public final class GradebookRepository {
  private var owner: String?
  private var generation = 0
  private var snapshots: [Int: GradebookSnapshot] = [:]
  public static let completeRefreshInterval: TimeInterval = 1_800
  public init() {}
  public func clear() {
    generation += 1
    owner = nil
    snapshots.removeAll()
  }
  public func cached(owner: String, period: Int) -> GradebookSnapshot? {
    self.owner == owner ? snapshots[period] : nil
  }
  public func load(
    owner: String, period: Int?, force: Bool = true, at suppliedDate: Date? = nil,
    fetch: (Int?, GradebookReadMode) async throws -> Gradebook
  ) async throws -> GradebookSnapshot {
    guard !owner.isEmpty else { throw APIError.invalidInput }
    if let period, !(0...999).contains(period) { throw APIError.invalidInput }
    if self.owner != owner {
      clear()
      self.owner = owner
    }
    let version = generation
    let now = suppliedDate ?? Date()
    let previous = period.flatMap { snapshots[$0] }
    let age = previous?.fullReadAt.map { now.timeIntervalSince($0) }
    let canValidate =
      !force && previous?.book.detailed == true
      && (age.map { $0 >= 0 && $0 < Self.completeRefreshInterval } ?? false)
    var book = try await fetch(period, canValidate ? .summary : .fresh)
    guard version == generation, self.owner == owner else { throw CancellationError() }
    var fullReadAt: Date?
    if book.detailed {
      fullReadAt = suppliedDate ?? Date()
    } else if canValidate, let previous, Self.summaryMatches(previous.book, book) {
      book = Gradebook(
        periods: book.periods.isEmpty ? previous.book.periods : book.periods,
        selectedPeriod: book.selectedPeriod, courses: previous.book.courses, detailed: true)
      fullReadAt = previous.fullReadAt
    } else if canValidate {
      book = try await fetch(period, .fresh)
      guard version == generation, self.owner == owner else { throw CancellationError() }
      fullReadAt = book.detailed ? (suppliedDate ?? Date()) : nil
    }
    let snapshot = GradebookSnapshot(
      book: book, checkedAt: suppliedDate ?? Date(), fullReadAt: fullReadAt)
    snapshots[book.selectedPeriod.index] = snapshot
    if snapshots.count > 8,
      let oldest = snapshots.filter({ $0.key != book.selectedPeriod.index }).min(by: {
        $0.value.checkedAt < $1.value.checkedAt
      })?.key
    {
      snapshots.removeValue(forKey: oldest)
    }
    return snapshot
  }

  public static func summaryMatches(_ cached: Gradebook, _ summary: Gradebook) -> Bool {
    guard cached.detailed, cached.selectedPeriod.index == summary.selectedPeriod.index,
      cached.courses.count == summary.courses.count
    else { return false }
    let indexed = Dictionary(
      cached.courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    guard indexed.count == cached.courses.count,
      Set(summary.courses.map(\.id)).count == summary.courses.count
    else { return false }
    for course in summary.courses {
      guard let prior = indexed[course.id], prior.title == course.title,
        normalized(prior.officialMark) == normalized(course.officialMark),
        prior.officialPercent == course.officialPercent,
        course.teacher.isEmpty || course.teacher == prior.teacher,
        course.room.isEmpty || course.room == prior.room
      else { return false }
    }
    return true
  }
  private static func normalized(_ value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
  }
}
