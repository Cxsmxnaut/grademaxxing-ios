import Foundation
import GrademaxxingCore

enum GradeParityTests {
  static func gpaMatchesTheOwningWebModule() throws {
    struct Fixture: Decodable {
      struct Point: Decodable {
        let letter: String
        let points: Double?
      }
      struct Policy: Decodable {
        let title: String
        let bonus: Double
        let academic: Bool
      }
      struct TestCase: Decodable {
        struct Enrollment: Decodable {
          let courseName: String
          let letter: String
          let credits: Double
          let gradeLevel: Int
          let excludeFromGpa: Bool
          let academic: Bool
        }
        struct Expected: Decodable {
          let unweighted: Double
          let weighted: Double
          let academicWeighted: Double
          let attemptedCredits: Double
          let academicCredits: Double
        }
        let enrollments: [Enrollment]
        let expected: Expected
      }
      let policyLabel: String
      let gradePoints: [Point]
      let coursePolicies: [Policy]
      let cases: [TestCase]
    }
    let fixture = try JSONDecoder().decode(Fixture.self, from: resourceFixture("gpa-policy"))
    try expect(fixture.policyLabel == GPAPlanning.policyLabel)
    for point in fixture.gradePoints {
      try expect(GPAPlanning.points(for: point.letter) == point.points)
    }
    for policy in fixture.coursePolicies {
      try expect(GPAPlanning.weightBonus(for: policy.title) == policy.bonus)
      try expect(GPAPlanning.isAcademic(policy.title) == policy.academic)
    }
    for item in fixture.cases {
      let entries = item.enrollments.enumerated().map { index, value in
        GPAEntry(
          id: String(index), title: value.courseName, letter: value.letter, credits: value.credits,
          bonus: GPAPlanning.weightBonus(for: value.courseName), included: !value.excludeFromGpa,
          academic: value.academic, gradeLevel: value.gradeLevel)
      }
      let actual = GPAPlanning.summary(entries)
      try expect(abs((actual.unweighted ?? 0) - item.expected.unweighted) < 0.000001)
      try expect(abs((actual.weighted ?? 0) - item.expected.weighted) < 0.000001)
      try expect(abs((actual.academicWeighted ?? 0) - item.expected.academicWeighted) < 0.000001)
      try expect(abs(actual.attemptedCredits - item.expected.attemptedCredits) < 0.000001)
      try expect(abs(actual.academicCredits - item.expected.academicCredits) < 0.000001)
    }
  }
  static func automaticRefreshPreservesEditedPlansAndUpdatesUntouchedDefaults() throws {
    let baseline = GPAPlanning.entries(for: DemoData.gradebook().courses)
    var edited = baseline
    edited[0].letter = "C"
    edited[0].credits = 2.5
    var courses = DemoData.gradebook().courses
    courses[1].officialMark = "A"
    let next = GPAPlanning.entries(for: courses)
    let result = GPAPlanning.rebase(current: edited, original: baseline, next: next)
    try expect(result[0].letter == "C" && result[0].credits == 2.5)
    try expect(result[1].letter == "A")
    let reduced = GPAPlanning.rebase(current: edited, original: baseline, next: [next[1]])
    try expect(reduced.count == 1 && reduced[0].id == next[1].id)
  }
  static func unpublishedGradesDoNotSilentlyEnterTheGPA() throws {
    let course = Course(wireID: "synthetic", title: "AP Synthetic", period: "1", officialMark: "A")
    let entries = GPAPlanning.entries(for: [course])
    try expect(entries.first?.included == false)
    try expect(GPAPlanning.summary(entries).unweighted == nil)
    try expect(GPAPlanning.displayValue(3.675) == "3.68")
  }
}

private func header(_ book: Gradebook, percent: Double? = nil, period: Int? = nil) -> Gradebook {
  let courses = book.courses.map { course -> Course in
    var copy = course
    copy.assignments = []
    copy.categories = []
    if let percent { copy.officialPercent = percent }
    return copy
  }
  return Gradebook(
    periods: book.periods,
    selectedPeriod: ReportingPeriod(
      index: period ?? book.selectedPeriod.index, name: book.selectedPeriod.name), courses: courses,
    detailed: false)
}
private actor SuspendedGradebook {
  private var pending: CheckedContinuation<Gradebook, Never>?
  private var watcher: CheckedContinuation<Void, Never>?
  private var started = false
  func fetch() async -> Gradebook {
    started = true
    watcher?.resume()
    watcher = nil
    return await withCheckedContinuation { pending = $0 }
  }
  func waitForStart() async { if !started { await withCheckedContinuation { watcher = $0 } } }
  func complete() {
    pending?.resume(returning: DemoData.gradebook())
    pending = nil
  }
}
@MainActor enum GradebookRepositoryTests {
  private static let owner = "synthetic-session"
  private static let now = Date(timeIntervalSince1970: 1_800_000_000)
  static func unchangedHeadersReuseAssignmentsWithoutExtendingFullReadAge() async throws {
    let repository = GradebookRepository()
    var modes: [GradebookReadMode] = []
    _ = try await repository.load(
      owner: owner, period: 0, at: now,
      fetch: { _, mode in
        modes.append(mode)
        return DemoData.gradebook()
      })
    let checked = try await repository.load(
      owner: owner, period: 0, force: false, at: now.addingTimeInterval(60),
      fetch: { _, mode in
        modes.append(mode)
        return header(DemoData.gradebook())
      })
    try expect(modes == [.fresh, .summary])
    try expect(checked.book.courses.first?.assignments.count == 3)
    try expect(checked.fullReadAt == now && checked.checkedAt == now.addingTimeInterval(60))
  }
  static func changedMarksForceCompleteRetrieval() async throws {
    let repository = GradebookRepository()
    var modes: [GradebookReadMode] = []
    _ = try await repository.load(
      owner: owner, period: 0, at: now, fetch: { _, _ in DemoData.gradebook() })
    let result = try await repository.load(
      owner: owner, period: 0, force: false, at: now.addingTimeInterval(60),
      fetch: { _, mode in
        modes.append(mode)
        return mode == .summary ? header(DemoData.gradebook(), percent: 50) : DemoData.gradebook()
      })
    try expect(modes == [.summary, .fresh])
    try expect(result.book.detailed && result.fullReadAt == now.addingTimeInterval(60))
  }
  static func missingPercentageAndStructuralChangesCannotReuseDetails() throws {
    let book = DemoData.gradebook()
    var missing = book.courses
    missing[0].officialPercent = nil
    let summary = Gradebook(
      periods: book.periods, selectedPeriod: book.selectedPeriod, courses: missing, detailed: false)
    try expect(!GradebookRepository.summaryMatches(book, summary))
    try expect(!GradebookRepository.summaryMatches(book, header(book, period: 1)))
    let fewer = Gradebook(
      periods: book.periods, selectedPeriod: book.selectedPeriod,
      courses: Array(book.courses.dropLast()), detailed: false)
    try expect(!GradebookRepository.summaryMatches(book, fewer))
  }
  static func thirtyMinuteDeadlineAndExplicitRefreshAlwaysUseCompleteReads() async throws {
    let repository = GradebookRepository()
    var modes: [GradebookReadMode] = []
    _ = try await repository.load(
      owner: owner, period: 0, at: now, fetch: { _, _ in DemoData.gradebook() })
    _ = try await repository.load(
      owner: owner, period: 0, force: false, at: now.addingTimeInterval(1_800),
      fetch: { _, mode in
        modes.append(mode)
        return DemoData.gradebook()
      })
    _ = try await repository.load(
      owner: owner, period: 0, force: true, at: now.addingTimeInterval(1_801),
      fetch: { _, mode in
        modes.append(mode)
        return DemoData.gradebook()
      })
    try expect(modes == [.fresh, .fresh])
  }
  static func summaryFallbackCompleteResponseIsAccepted() async throws {
    let repository = GradebookRepository()
    _ = try await repository.load(
      owner: owner, period: 0, at: now, fetch: { _, _ in DemoData.gradebook() })
    let result = try await repository.load(
      owner: owner, period: 0, force: false, at: now.addingTimeInterval(60),
      fetch: { _, _ in DemoData.gradebook() })
    try expect(result.fullReadAt == now.addingTimeInterval(60))
  }
  static func sessionChangesRemovePreviousRecords() async throws {
    let repository = GradebookRepository()
    _ = try await repository.load(
      owner: owner, period: 0, at: now, fetch: { _, _ in DemoData.gradebook() })
    try expect(repository.cached(owner: "other-session", period: 0) == nil)
    _ = try await repository.load(
      owner: "other-session", period: 1, at: now, fetch: { _, _ in DemoData.gradebook(period: 1) })
    try expect(repository.cached(owner: owner, period: 0) == nil)
  }
  static func cacheIsBoundedAndUsesReceivedPeriod() async throws {
    let repository = GradebookRepository()
    for index in 0..<10 {
      _ = try await repository.load(
        owner: owner, period: index, at: now.addingTimeInterval(Double(index)),
        fetch: { _, _ in
          Gradebook(
            periods: [], selectedPeriod: ReportingPeriod(index: index, name: "Synthetic"),
            courses: [])
        })
    }
    try expect(
      repository.cached(owner: owner, period: 0) == nil
        && repository.cached(owner: owner, period: 1) == nil)
    try expect(repository.cached(owner: owner, period: 9) != nil)
    let actual = try await repository.load(
      owner: owner, period: 8, at: now.addingTimeInterval(20),
      fetch: { _, _ in DemoData.gradebook() })
    try expect(actual.book.selectedPeriod.index == 0)
    try expect(repository.cached(owner: owner, period: 0) != nil)
  }
  static func clearedCacheCannotBeRepopulatedByAnOldResponse() async throws {
    let repository = GradebookRepository()
    let suspended = SuspendedGradebook()
    let task = Task {
      try await repository.load(owner: owner, period: 0, fetch: { _, _ in await suspended.fetch() })
    }
    await suspended.waitForStart()
    repository.clear()
    await suspended.complete()
    do {
      _ = try await task.value
      throw CheckFailure(description: "Old gradebook should be invalidated")
    } catch is CancellationError {}
    try expect(repository.cached(owner: owner, period: 0) == nil)
  }
}
