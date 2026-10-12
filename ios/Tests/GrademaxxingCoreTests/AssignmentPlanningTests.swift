import Foundation
import GrademaxxingCore

enum AssignmentPlanningTests {
  private struct Fixture: Decodable {
    struct Category: Decodable {
      let name: String
      let weight: Double
      let earned: Double
      let possible: Double
    }
    struct Parsed: Decodable {
      let id: String
      let earned: Double?
      let possible: Double?
      let precise: Double?
      let extraCredit: Bool
      let excluded: Bool
    }
    struct Edit: Decodable {
      let id: String
      let earned: Double?
      let possible: Double?
      let excluded: Bool?
      let extraCredit: Bool?
    }
    struct Addition: Decodable {
      let category: String
      let earned: Double
      let possible: Double
    }
    struct Trend: Decodable {
      let date: String
      let percentage: Double
      let assignments: [String]
    }
    let name: String
    let official: Double
    let categories: [Category]
    let wire: [[String: String]]
    let parsed: [Parsed]
    let edit: Edit
    let add: Addition?
    let baseline: Double?
    let projected: Double?
    let omitted: Int
    let partial: Bool
    let targetCategory: String
    let needed: Double?
    let trend: [Trend]
    let domain: [Double]
  }
  private static func near(_ actual: Double?, _ expected: Double?, context: String) throws {
    if let actual, let expected, abs(actual - expected) < 0.000001 { return }
    if actual == nil && expected == nil { return }
    throw CheckFailure(
      description:
        "Assignment parity failed: \(context); \(String(describing: actual)) versus \(String(describing: expected))"
    )
  }
  static func matchesWebAssignmentRules() throws {
    let fixtures = try JSONDecoder().decode(
      [Fixture].self, from: resourceFixture("assignment-policy"))
    for fixture in fixtures {
      let assignments = fixture.wire.map { AssignmentDecoder.decode($0) }
      for (actual, expected) in zip(assignments, fixture.parsed) {
        try near(actual.pointsEarned, expected.earned, context: fixture.name + " earned")
        try near(actual.pointsPossible, expected.possible, context: fixture.name + " possible")
        try near(actual.calculationEarned, expected.precise, context: fixture.name + " precision")
        try expect(
          actual.extraCredit == expected.extraCredit && actual.excluded == expected.excluded)
      }
      let course = Course(
        wireID: "synthetic", title: fixture.name, period: "1", officialMark: "B",
        officialPercent: fixture.official,
        assignments: assignments,
        categories: fixture.categories.map {
          GradeCategory(name: $0.name, weight: $0.weight, earned: $0.earned, possible: $0.possible)
        })
      var simulation = GradeSimulation(course: course)
      try near(simulation.estimate?.baseline, fixture.baseline, context: fixture.name + " baseline")
      try near(
        simulation.estimate?.projected, fixture.official,
        context: fixture.name + " unchanged official")
      try expect(simulation.trend.count == fixture.trend.count)
      for (actual, expected) in zip(simulation.trend, fixture.trend) {
        try expect(actual.date.iso == expected.date && actual.assignments == expected.assignments)
        try near(actual.percentage, expected.percentage, context: fixture.name + " trend")
      }
      let domain = GradeSimulation.chartDomain(simulation.trend.map(\.percentage))
      try near(domain.lowerBound, fixture.domain[0], context: fixture.name + " domain minimum")
      try near(domain.upperBound, fixture.domain[1], context: fixture.name + " domain maximum")
      let index = try require(simulation.rows.firstIndex { $0.id == fixture.edit.id })
      // These fixtures always edit earned points, exclusion, or the extra-credit flag.
      if fixture.edit.excluded == nil && fixture.edit.extraCredit == nil {
        simulation.rows[index].earned = fixture.edit.earned
      }
      if let value = fixture.edit.possible { simulation.rows[index].possible = value }
      if let value = fixture.edit.excluded { simulation.rows[index].excluded = value }
      if let value = fixture.edit.extraCredit { simulation.rows[index].extraCredit = value }
      if let value = fixture.add {
        simulation.add(category: value.category, earned: value.earned, possible: value.possible)
      }
      try near(
        simulation.estimate?.projected, fixture.projected, context: fixture.name + " projection")
      try near(
        simulation.pointsNeeded(target: 90, possible: 20, category: fixture.targetCategory),
        fixture.needed, context: fixture.name + " target")
      if let estimate = simulation.estimate {
        try expect(
          estimate.omittedAssignments == fixture.omitted && estimate.partial == fixture.partial)
      }
      try expect(simulation.course.officialPercent == fixture.official)
      simulation.reset()
      try expect(simulation.rows == simulation.original)
    }
  }
  static func invalidEditsAndUnsupportedEvidenceStayDistinct() throws {
    let course = Course(
      wireID: "synthetic", title: "Synthetic", period: "1", officialPercent: 80,
      assignments: [
        Assignment(
          id: "graded", title: "Graded", category: "Tests", pointsEarned: 8, pointsPossible: 10),
        Assignment(
          id: "unsupported", title: "Raw", category: "Tests", calculationUnavailable: true,
          rawEarned: 4, rawPossible: 5),
      ])
    var simulation = GradeSimulation(course: course)
    try expect(simulation.estimate?.partial == true && simulation.estimate?.omittedAssignments == 1)
    simulation.rows[0].possible = 0
    try expect(simulation.estimate == nil)
    simulation.reset()
    simulation.rows[0].extraCredit = true
    try expect(simulation.estimate == nil)  // No normal denominator remains.
    simulation.reset()
    simulation.rows[0].earned = .infinity
    try expect(simulation.estimate == nil)
    try expect(simulation.pointsNeeded(target: 90, possible: 20, category: "Tests") == nil)
    try expect(GradeSimulation.chartDomain([.nan, .infinity]) == 0...100)
  }
}
