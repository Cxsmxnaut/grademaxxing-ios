import Foundation
import GrademaxxingCore

func contractFixture() throws -> Data {
  try Data(contentsOf: require(Bundle.module.url(forResource: "gradebook", withExtension: "json")))
}
func envelope(_ xml: String, detailed: Bool = true) throws -> Data {
  try JSONSerialization.data(withJSONObject: ["xml": xml, "detailed": detailed])
}

enum GradebookTests {
  static func decodesRealBackendBuilderContract() throws {
    let book = try GradebookDecoder.decode(contractFixture())
    try expect(book.selectedPeriod.index == 2)
    try expect(book.periods.map(\.index) == [0, 2])
    try expect(book.courses.count == 2)
    let math = try require(book.courses.first)
    try expect(math.officialMark == "A-")
    try expect(math.officialPercent == 92.5)
    try expect(math.categories.first?.weight == 70)
    try expect(math.assignments.first?.title == "Scaled quiz & review")
    try expect(math.assignments.first?.pointsEarned == 18)
    try expect(math.assignments.first?.pointsPossible == 20)
    try expect(math.assignments.first?.publishedPercent == 90)
    try expect(math.assignments.last?.calculationUnavailable == true)
    try expect(math.assignments.last?.pointsEarned == nil)
    // Preserve published point maxima for display; the unavailable flag blocks calculation.
    try expect(math.assignments.last?.pointsPossible == 100)
    try expect(SimulationRow(math.assignments.last!).calculation == nil)
    try expect(book.courses.last?.officialPercent == nil)
  }
  static func preservesOfficialPercentInsteadOfInferringRawScore() throws {
    let xml = """
      <Gradebook><ReportingPeriod GradePeriod="Current" Index="0"/><Courses>
      <Course CourseID="synthetic" Period="1" CourseName="Synthetic"><Marks>
      <Mark CalculatedScoreString="A" CalculatedScoreRaw="91.35"><Assignments>
      <Assignment GradebookID="one" Measure="Review" ScoreCalValue="9" ScoreMaxValue="10" DisplayScore="9 out of 10"/>
      </Assignments></Mark><Mark CalculatedScoreString="F" CalculatedScoreRaw="0"/>
      </Marks></Course></Courses></Gradebook>
      """
    let book = try GradebookDecoder.decode(envelope(xml))
    try expect(book.courses.first?.officialPercent == 91.35)
    try expect(book.courses.first?.assignments.first?.pointsEarned == nil)
    try expect(book.courses.first?.assignments.first?.pointsPossible == nil)
  }
  static func handlesEmptyAndSummaryGradebooks() throws {
    let book = try GradebookDecoder.decode(
      envelope(
        "<Gradebook><ReportingPeriod Index=\"0\" GradePeriod=\"Current\"/><Courses/></Gradebook>",
        detailed: false))
    try expect(book.courses.isEmpty)
    try expect(book.detailed == false)
  }
  static func rejectsInvalidAndExternalEntityXML(_ xml: String) throws {
    let data = try envelope(xml)
    try expectThrows(APIError.invalidResponse) { try GradebookDecoder.decode(data) }
  }
  static func rejectsNonJSONResponse() throws {
    try expectThrows(APIError.invalidResponse) {
      try GradebookDecoder.decode(Data("service unavailable".utf8))
    }
  }
  static func rejectsDuplicateAssignmentIDs() throws {
    let xml = """
      <Gradebook><ReportingPeriod Index="0"/><Courses><Course CourseID="one"><Marks><Mark><Assignments>
      <Assignment GradebookID="duplicate"/><Assignment GradebookID="duplicate"/>
      </Assignments></Mark></Marks></Course></Courses></Gradebook>
      """
    let data = try envelope(xml)
    try expectThrows(APIError.invalidResponse) { try GradebookDecoder.decode(data) }
  }
}

enum PlanningTests {
  static func weightedProjectionUsesCategoryTotalsAndLeavesOfficialMarkUnchanged() throws {
    let course = try require(DemoData.gradebook().courses.first)
    let result = try require(
      GradePlanning.project(course: course, category: "Tests", earned: 100, possible: 100))
    try expect(abs(result.baseline - 94.2) < 0.00001)
    try expect(abs(result.projected - 95.5533333333) < 0.00001)
    try expect(course.officialPercent == 94.2)
  }
  static func refusesUnreliableBaselineAndUnknownWeights() throws {
    var course = try require(DemoData.gradebook().courses.first)
    course.officialPercent = 50
    try expect(
      GradePlanning.project(course: course, category: "Tests", earned: 100, possible: 100) == nil)
    course.officialPercent = 94.2
    course.categories = [GradeCategory(name: "Tests", weight: nil, earned: 94.2, possible: 100)]
    try expect(
      GradePlanning.project(course: course, category: "Tests", earned: 100, possible: 100) == nil)
  }
  static func extraCreditIsAllowedButInvalidInputsAreRejected() throws {
    let course = try require(DemoData.gradebook().courses.first)
    try expect(
      GradePlanning.project(course: course, category: "Tests", earned: 110, possible: 100) != nil)
    try expect(
      GradePlanning.project(course: course, category: "Tests", earned: -1, possible: 100) == nil)
    try expect(
      GradePlanning.project(course: course, category: "Tests", earned: .infinity, possible: 100)
        == nil)
    try expect(
      GradePlanning.project(course: course, category: "Tests", earned: 10, possible: 0) == nil)
  }
  static func gpaMatchesProvisionalWebPolicyAndCreditWeighting() throws {
    let entries = [
      GPAEntry(id: "ap", title: "AP Synthetic", letter: "A-", credits: 5, bonus: 1),
      GPAEntry(id: "honors", title: "Synthetic Honors", letter: "B+", credits: 5, bonus: 0.5),
      GPAEntry(id: "d", title: "Synthetic D", letter: "D", credits: 10, bonus: 1),
      GPAEntry(id: "pass", title: "Synthetic Pass", letter: "P", credits: 5),
      GPAEntry(id: "excluded", title: "Excluded", letter: "A", included: false),
    ]
    try expect(GPAPlanning.calculate(entries, weighted: false) == 2.25)
    try expect(GPAPlanning.calculate(entries, weighted: true) == 2.625)
    try expect(GPAPlanning.points(for: "NC") == 0)
    try expect(GPAPlanning.calculate([], weighted: true) == nil)
  }
}
