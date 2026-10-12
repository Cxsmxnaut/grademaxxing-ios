import Foundation

public struct Projection: Equatable, Sendable {
  public let baseline: Double
  public let projected: Double
  public var change: Double { projected - baseline }
}

public enum GradePlanning {
  /// Uses authoritative category totals, avoiding re-counting dropped or hidden assignments.
  /// Deliberately unavailable if the baseline cannot reproduce the official percentage.
  public static func project(course: Course, category: String, earned: Double, possible: Double)
    -> Projection?
  {
    guard earned.isFinite, possible.isFinite, earned >= 0, possible > 0,
      course.categories.contains(where: { $0.name == category }),
      let official = course.officialPercent, official.isFinite,
      let baseline = percentage(course.categories), abs(baseline - official) <= 0.25
    else { return nil }
    let modified = course.categories.map { item in
      if item.name != category { return item }
      return GradeCategory(
        name: item.name, weight: item.weight,
        earned: (item.earned ?? 0) + earned, possible: (item.possible ?? 0) + possible)
    }
    guard let projected = percentage(modified) else { return nil }
    return Projection(baseline: baseline, projected: projected)
  }

  private static func percentage(_ categories: [GradeCategory]) -> Double? {
    guard !categories.isEmpty, Set(categories.map(\.name)).count == categories.count else {
      return nil
    }
    var sum = 0.0
    var weightSum = 0.0
    for item in categories {
      guard let weight = item.weight, let earned = item.earned, let possible = item.possible,
        weight.isFinite, earned.isFinite, possible.isFinite,
        weight >= 0, earned >= 0, possible >= 0
      else { return nil }
      if possible == 0 { continue }
      sum += earned / possible * weight
      weightSum += weight
    }
    guard weightSum > 0 else { return nil }
    return sum / weightSum * 100
  }
}

public struct GPAEntry: Identifiable, Sendable, Equatable {
  public let id: String
  public let title: String
  public var letter: String
  public var credits: Double
  public var bonus: Double
  public var included: Bool
  public var academic: Bool
  public var gradeLevel: Int
  public init(
    id: String, title: String, letter: String, credits: Double = 5, bonus: Double = 0,
    included: Bool = true, academic: Bool = true, gradeLevel: Int = 9
  ) {
    self.id = id
    self.title = title
    self.letter = letter
    self.credits = credits
    self.bonus = bonus
    self.included = included
    self.academic = academic
    self.gradeLevel = gradeLevel
  }
}

public struct GPASummary: Sendable, Equatable {
  public let unweighted: Double?
  public let weighted: Double?
  public let academicWeighted: Double?
  public let attemptedCredits: Double
  public let academicCredits: Double
}

public enum GPAPlanning {
  public static let policyLabel = "PUSD provisional"
  public static func points(for letter: String) -> Double? {
    switch letter.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
    case "A", "A+", "A-": 4
    case "B", "B+", "B-": 3
    case "C", "C+", "C-": 2
    case "D", "D+", "D-": 1
    case "F", "NC", "NP": 0
    default: nil
    }
  }
  public static func weightBonus(for title: String) -> Double {
    if title.range(
      of: "(?:^|\\s)(?:AP|IB)(?:\\s|$)", options: [.regularExpression, .caseInsensitive]) != nil
    {
      return 1
    }
    if title.range(of: "honou?rs?", options: [.regularExpression, .caseInsensitive]) != nil {
      return 0.5
    }
    return 0
  }
  public static func isAcademic(_ title: String) -> Bool {
    let patterns = [
      "(?:^|\\s)(?:PE|P\\.E\\.|Physical Education)(?:\\s|$)", "driver'?s education",
      "(?:^|\\s)ROTC(?:\\s|$)",
    ]
    return !patterns.contains {
      title.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
    }
  }
  public static func entries(for courses: [Course], gradeLevel: Int = 9) -> [GPAEntry] {
    courses.map { course in
      return GPAEntry(
        id: course.id, title: course.title, letter: course.officialMark,
        bonus: weightBonus(for: course.title),
        included: course.officialPercent?.isFinite == true
          && points(for: course.officialMark) != nil,
        academic: isAcademic(course.title), gradeLevel: gradeLevel)
    }
  }
  /// The provisional web policy uses flat plus/minus bands and no rigor bonus for D/F.
  public static func calculate(_ entries: [GPAEntry], weighted: Bool, academicOnly: Bool = false)
    -> Double?
  {
    var quality = 0.0
    var credits = 0.0
    for entry in entries
    where entry.included && entry.gradeLevel >= 9 && (!academicOnly || entry.academic) {
      guard let base = points(for: entry.letter), entry.credits.isFinite, entry.credits > 0,
        entry.bonus.isFinite, (0...1).contains(entry.bonus)
      else { continue }
      let scaledCredits = (entry.credits * 1_000).rounded()
      let points = base + (weighted && base >= 2 ? entry.bonus : 0)
      quality += (points * 1_000).rounded() * scaledCredits
      credits += scaledCredits
    }
    guard credits > 0, quality.isFinite else { return nil }
    return (quality / credits).rounded() / 1_000
  }
  public static func summary(_ entries: [GPAEntry]) -> GPASummary {
    let eligible = entries.filter {
      $0.included && $0.gradeLevel >= 9 && points(for: $0.letter) != nil && $0.credits.isFinite
        && $0.credits > 0 && $0.bonus.isFinite && (0...1).contains($0.bonus)
    }
    return GPASummary(
      unweighted: calculate(eligible, weighted: false),
      weighted: calculate(eligible, weighted: true),
      academicWeighted: calculate(eligible, weighted: true, academicOnly: true),
      attemptedCredits: eligible.reduce(0) { $0 + $1.credits },
      academicCredits: eligible.filter(\.academic).reduce(0) { $0 + $1.credits })
  }
  /// Automatic refresh updates untouched defaults while preserving deliberate local edits.
  public static func rebase(current: [GPAEntry], original: [GPAEntry], next: [GPAEntry])
    -> [GPAEntry]
  {
    let prior = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let defaults = Dictionary(original.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return next.map { seed in
      guard let entry = prior[seed.id], entry != defaults[seed.id] else { return seed }
      return GPAEntry(
        id: seed.id, title: seed.title, letter: entry.letter, credits: entry.credits,
        bonus: entry.bonus, included: entry.included, academic: entry.academic,
        gradeLevel: entry.gradeLevel)
    }
  }
  public static func displayValue(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "—" }
    let rounded = ((value + Double.ulpOfOne) * 100).rounded() / 100
    return rounded.formatted(.number.precision(.fractionLength(2)))
  }
}
