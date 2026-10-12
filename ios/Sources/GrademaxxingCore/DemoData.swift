import Foundation

/// Entirely invented records. This is the only data used in previews and automated UI checks.
public enum DemoData {
  public static let periods = [
    ReportingPeriod(index: 0, name: "Semester 1"), ReportingPeriod(index: 1, name: "Semester 2"),
  ]
  public static func gradebook(period: Int = 0) -> Gradebook {
    let selected = periods.first(where: { $0.index == period }) ?? periods[0]
    let courses = [
      course("math", "AP Calculus", "1", "Ms. Sample", 94.2, "A", "Tests", "Practice"),
      course(
        "english", "English Honors", "2", "Mr. Example", period == 0 ? 88.5 : 91.0,
        period == 0 ? "B+" : "A-", "Writing", "Reading"),
      course("science", "Chemistry", "3", "Dr. Demo", 91.6, "A-", "Labs", "Assessments"),
      course("history", "World History", "4", "Ms. Example", 86.4, "B", "Assessments", "Projects"),
      course("art", "Studio Art", "5", "Mr. Sample", 97.0, "A", "Portfolio", "Practice"),
    ]
    return Gradebook(periods: periods, selectedPeriod: selected, courses: courses)
  }
  private static func course(
    _ id: String, _ name: String, _ period: String, _ teacher: String, _ percent: Double,
    _ mark: String, _ first: String, _ second: String
  ) -> Course {
    Course(
      wireID: id, title: name, period: period, teacher: teacher, room: "Demo room",
      officialMark: mark, officialPercent: percent,
      assignments: [
        Assignment(
          id: "\(id)-1", title: "Unit review", category: second, dueDate: "10/07/2026",
          displayScore: "47 out of 50", notes: "Synthetic demo assignment", pointsEarned: 47,
          pointsPossible: 50),
        Assignment(
          id: "\(id)-2", title: "Unit assessment", category: first, dueDate: "10/09/2026",
          displayScore: "\(percent) out of 100", pointsEarned: percent, pointsPossible: 100,
          publishedPercent: percent),
        Assignment(
          id: "\(id)-3", title: "Upcoming project", category: second, dueDate: "10/16/2026",
          displayScore: "Not Graded"),
      ],
      categories: [
        GradeCategory(name: first, weight: 70, earned: percent * 2, possible: 200),
        GradeCategory(name: second, weight: 30, earned: percent, possible: 100),
      ])
  }
}
