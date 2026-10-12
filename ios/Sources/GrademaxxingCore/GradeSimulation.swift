import Foundation

public struct SimulationRow: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public var category: String
  public var earned: Double?
  public var possible: Double?
  public var excluded: Bool
  public var extraCredit: Bool
  public let unavailable: Bool
  public let recorded: Bool
  public let hidden: Bool
  public let hypothetical: Bool
  public let date: SchoolDate?
  private let publishedEarned: Double?
  private let publishedPossible: Double?
  private let publishedExtraCredit: Bool
  private let preciseEarned: Double?

  public init(_ assignment: Assignment) {
    id = assignment.id
    title = assignment.title
    category = assignment.category
    earned = assignment.pointsEarned
    possible = assignment.pointsPossible
    excluded = assignment.excluded
    extraCredit = assignment.extraCredit
    unavailable = assignment.calculationUnavailable
    recorded =
      assignment.pointsEarned != nil || assignment.publishedPercent != nil
      || (assignment.rawEarned != nil && (assignment.rawPossible ?? 0) > 0)
    hidden = false
    hypothetical = false
    date = Self.schoolDate(assignment.postedDate) ?? Self.schoolDate(assignment.dueDate)
    publishedEarned = assignment.pointsEarned
    publishedPossible = assignment.pointsPossible
    publishedExtraCredit = assignment.extraCredit
    preciseEarned = assignment.calculationEarned
  }
  public init(
    id: String = UUID().uuidString, title: String, category: String, earned: Double?,
    possible: Double?, extraCredit: Bool = false, hidden: Bool = false, date: SchoolDate? = nil
  ) {
    self.id = id
    self.title = title
    self.category = category
    self.earned = earned
    self.possible = possible
    excluded = false
    self.extraCredit = extraCredit
    unavailable = false
    recorded = earned != nil
    self.hidden = hidden
    hypothetical = !hidden
    self.date = date
    publishedEarned = nil
    publishedPossible = nil
    publishedExtraCredit = false
    preciseEarned = nil
  }
  public var calculation: (earned: Double, possible: Double)? {
    guard !excluded, !unavailable else { return nil }
    let unchanged =
      !hypothetical && earned == publishedEarned && possible == publishedPossible
      && extraCredit == publishedExtraCredit
    let value = unchanged && !extraCredit ? preciseEarned ?? earned : earned
    guard let earned = value, earned.isFinite, let possible = extraCredit ? 0 : possible,
      possible.isFinite,
      hidden || extraCredit || possible > 0
    else { return nil }
    return (earned, possible)
  }
  private static func schoolDate(_ value: String) -> SchoolDate? {
    if let iso = SchoolDate(iso: String(value.prefix(10))) { return iso }
    let pieces = value.split(separator: "/")
    guard pieces.count == 3, let month = Int(pieces[0]), let day = Int(pieces[1]),
      let year = Int(pieces[2].prefix(4))
    else { return nil }
    return SchoolDate(iso: String(format: "%04d-%02d-%02d", year, month, day))
  }
}

public struct SimulationEstimate: Sendable, Equatable {
  public let baseline: Double
  public let calculated: Double
  public let projected: Double
  public let change: Double
  public let omittedAssignments: Int
  public let partial: Bool
}
public struct EstimatedGradePoint: Identifiable, Sendable, Equatable {
  public var id: String { date.iso }
  public let date: SchoolDate
  public let percentage: Double
  public let assignments: [String]
}

public struct GradeSimulation: Sendable {
  public let course: Course
  public let original: [SimulationRow]
  public var rows: [SimulationRow]
  public let categories: [GradeCategory]?
  private let adjustments: [SimulationRow]
  public init(course: Course) {
    self.course = course
    categories = course.categories.isEmpty ? nil : course.categories.filter { $0.name != "TOTAL" }
    original = course.assignments.map(SimulationRow.init)
    rows = original
    adjustments = GradeSimulation.reconcile(original, categories: categories)
  }
  public mutating func reset() { rows = original }
  public mutating func add(
    title: String = "What-if", category: String, earned: Double, possible: Double,
    extraCredit: Bool = false
  ) {
    rows.append(
      SimulationRow(
        title: title, category: category, earned: earned, possible: possible,
        extraCredit: extraCredit))
  }
  public func issue(_ row: SimulationRow) -> String? {
    Self.issue(row, categories: categories)
  }
  public var estimate: SimulationEstimate? {
    let before = original + adjustments
    guard !Self.model(before, categories: categories).compactMap(\.calculation).isEmpty,
      let baseline = Self.percentage(before, categories: categories)
    else { return nil }
    for row in rows where !row.excluded && !row.hidden {
      let zeroWeight = categories?.first(where: { $0.name == row.category })?.weight == 0
      if zeroWeight { continue }
      let source = original.first { $0.id == row.id }
      if !row.hypothetical, let source, Self.issue(source, categories: categories) != nil {
        continue
      }
      if row.hypothetical || row.recorded || row.earned != nil {
        guard row.calculation != nil else { return nil }
      }
    }
    guard let calculated = Self.percentage(rows + adjustments, categories: categories) else {
      return nil
    }
    let official = course.officialPercent ?? baseline
    let projected = official + calculated - baseline
    let omitted = Self.omitted(rows, categories: categories)
    return SimulationEstimate(
      baseline: baseline, calculated: calculated, projected: projected,
      change: calculated - baseline,
      omittedAssignments: omitted, partial: omitted > 0 || abs(baseline - official) > 0.25)
  }
  public func pointsNeeded(target: Double, possible: Double, category: String) -> Double? {
    guard target.isFinite, possible.isFinite, possible > 0, let estimate else { return nil }
    let localTarget = target - ((course.officialPercent ?? estimate.baseline) - estimate.baseline)
    let totals = Self.totals(rows + adjustments, categories: categories)
    if let categories {
      guard let selected = categories.first(where: { $0.name == category }),
        let weight = selected.weight, weight > 0, weight.isFinite
      else { return nil }
      var activeWeight = weight
      var other = 0.0
      for item in categories where item.name != category {
        guard let itemWeight = item.weight, itemWeight.isFinite, itemWeight >= 0 else { return nil }
        let points = totals[item.name] ?? (0, 0)
        if points.possible > 0 {
          activeWeight += itemWeight
          other += points.earned / points.possible * itemWeight
        } else if points.possible < 0 {
          return nil
        }
      }
      let points = totals[category] ?? (0, 0)
      let requiredRatio = (localTarget / 100 * activeWeight - other) / weight
      let result = requiredRatio * (points.possible + possible) - points.earned
      return result.isFinite ? result : nil
    }
    let values = Self.model(rows + adjustments, categories: nil).compactMap(\.calculation)
    let earned = values.reduce(0) { $0 + $1.earned }
    let maximum = values.reduce(0) { $0 + $1.possible }
    let result = localTarget / 100 * (maximum + possible) - earned
    return result.isFinite ? result : nil
  }
  public var trend: [EstimatedGradePoint] {
    guard let official = course.officialPercent, official.isFinite else { return [] }
    let usable = Self.model(original, categories: categories).filter {
      $0.calculation != nil && $0.date != nil
    }
    let dates = Set(usable.compactMap(\.date)).sorted()
    let points = dates.compactMap { date -> EstimatedGradePoint? in
      let included = usable.filter { $0.date! <= date }
      guard let percent = Self.percentage(included, categories: categories) else { return nil }
      return EstimatedGradePoint(
        date: date, percentage: percent, assignments: usable.filter { $0.date == date }.map(\.title)
      )
    }
    guard let last = points.last else { return [] }
    return points.compactMap { point in
      let value = point.percentage + official - last.percentage
      return value.isFinite && value >= 0
        ? EstimatedGradePoint(date: point.date, percentage: value, assignments: point.assignments)
        : nil
    }
  }
  public var impacts: [String: Double] {
    var included: [SimulationRow] = []
    var result: [String: Double] = [:]
    for row in Self.model(original, categories: categories).reversed() where row.calculation != nil
    {
      let before = Self.percentage(included, categories: categories)
      included.append(row)
      if let before, let after = Self.percentage(included, categories: categories) {
        result[row.id] = after - before
      }
    }
    return result
  }
  public static func chartDomain(_ values: [Double]) -> ClosedRange<Double> {
    let finite = values.filter(\.isFinite)
    guard let minimum = finite.min(), let maximum = finite.max() else { return 0...100 }
    let padding = minimum == maximum ? 5 : max(2, (maximum - minimum) * 0.1)
    return (minimum - padding)...(maximum + padding)
  }
  private static func issue(_ row: SimulationRow, categories: [GradeCategory]?) -> String? {
    if let categories {
      let category = categories.first { $0.name == row.category }
      if category?.weight == 0 { return nil }
      guard let weight = category?.weight, weight.isFinite, weight >= 0 else {
        return "Category weight is unavailable."
      }
    }
    if row.unavailable { return "StudentVUE has not established the weighted score scale." }
    var included = row
    included.excluded = false
    if row.recorded && included.calculation == nil { return "Weighted points are unavailable." }
    return nil
  }
  private static func model(_ rows: [SimulationRow], categories: [GradeCategory]?)
    -> [SimulationRow]
  {
    rows.filter { row in
      !row.excluded && issue(row, categories: categories) == nil
        && (categories == nil
          || categories!.contains { $0.name == row.category && ($0.weight ?? 0) > 0 })
    }
  }
  private static func totals(_ rows: [SimulationRow], categories: [GradeCategory]?) -> [String: (
    earned: Double, possible: Double
  )] {
    var result: [String: (Double, Double)] = [:]
    for row in model(rows, categories: categories) {
      guard let points = row.calculation else { continue }
      let previous = result[row.category] ?? (0, 0)
      result[row.category] = (previous.0 + points.earned, previous.1 + points.possible)
    }
    return result
  }
  private static func percentage(_ rows: [SimulationRow], categories: [GradeCategory]?) -> Double? {
    let values = model(rows, categories: categories).compactMap(\.calculation)
    if values.isEmpty { return 0 }
    if let categories {
      guard Set(categories.map(\.name)).count == categories.count else { return nil }
      let sums = totals(rows, categories: categories)
      var sum = 0.0
      var weights = 0.0
      for category in categories {
        guard let points = sums[category.name] else { continue }
        guard let weight = category.weight, weight.isFinite, weight >= 0, points.possible >= 0
        else { return nil }
        if weight == 0 || points.possible == 0 { continue }
        sum += points.earned / points.possible * weight
        weights += weight
      }
      guard weights > 0 else { return nil }
      let result = sum / weights * 100
      return result.isFinite ? result : nil
    }
    let earned = values.reduce(0) { $0 + $1.earned }
    let possible = values.reduce(0) { $0 + $1.possible }
    guard possible > 0 else { return nil }
    let result = earned / possible * 100
    return result.isFinite ? result : nil
  }
  private static func reconcile(_ rows: [SimulationRow], categories: [GradeCategory]?)
    -> [SimulationRow]
  {
    guard let categories else { return [] }
    var sums: [String: (Double, Double)] = [:]
    for row in rows {
      guard let points = row.calculation else { continue }
      let prior = sums[row.category] ?? (0, 0)
      sums[row.category] = (prior.0 + points.earned, prior.1 + points.possible)
    }
    return categories.compactMap { category in
      guard let earned = category.earned, let possible = category.possible, earned.isFinite,
        possible.isFinite, possible > 0
      else { return nil }
      let sum = sums[category.name] ?? (0, 0)
      let earnedGap = earned - sum.0
      let possibleGap = possible - sum.1
      guard abs(earnedGap) >= 0.000001 || abs(possibleGap) >= 0.000001 else { return nil }
      return SimulationRow(
        id: "official-totals:\(category.name)", title: "Official category totals",
        category: category.name, earned: earnedGap, possible: possibleGap, hidden: true)
    }
  }
  private static func omitted(_ rows: [SimulationRow], categories: [GradeCategory]?) -> Int {
    let sums = totals(rows, categories: categories)
    let undefined = Set(
      (categories ?? []).filter { category in
        let points = sums[category.name] ?? (0, 0)
        return (category.weight ?? 0) > 0 && (category.possible ?? 0) <= 0 && points.possible == 0
          && points.earned != 0
      }.map(\.name))
    return rows.filter {
      !$0.excluded && $0.recorded
        && (issue($0, categories: categories) != nil || undefined.contains($0.category))
    }.count
  }
}
