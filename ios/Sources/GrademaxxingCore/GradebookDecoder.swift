import Foundation

#if canImport(FoundationXML)
  import FoundationXML
#endif

public enum GradebookDecoder {
  public static func decode(_ data: Data) throws -> Gradebook {
    struct Envelope: Decodable {
      let xml: String
      let detailed: Bool
    }
    guard data.count <= 20 * 1_024 * 1_024,
      let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
      !envelope.xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
      !envelope.xml.localizedCaseInsensitiveContains("<!ENTITY")
    else { throw APIError.invalidResponse }
    let delegate = GradebookXMLDelegate()
    let parser = XMLParser(data: Data(envelope.xml.utf8))
    parser.shouldResolveExternalEntities = false
    parser.delegate = delegate
    guard parser.parse(), !delegate.invalid, delegate.hasRoot, delegate.hasCourses,
      let period = delegate.selectedPeriod
    else { throw APIError.invalidResponse }
    return Gradebook(
      periods: delegate.periods, selectedPeriod: period, courses: delegate.courses,
      detailed: envelope.detailed)
  }
}

private final class GradebookXMLDelegate: NSObject, XMLParserDelegate {
  var periods: [ReportingPeriod] = []
  var selectedPeriod: ReportingPeriod?
  var courses: [Course] = []
  var invalid = false
  var hasRoot = false
  var hasCourses = false
  private var path: [String] = []
  private var currentCourse: Course?
  private var hasMark = false
  private var selectedMark = false
  private var elements = 0

  func parser(
    _ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
    qualifiedName: String?, attributes a: [String: String]
  ) {
    path.append(name)
    elements += 1
    guard path.count <= 32, elements <= 150_000 else {
      invalid = true
      parser.abortParsing()
      return
    }
    switch path.joined(separator: "/") {
    case "Gradebook": hasRoot = true
    case "Gradebook/Courses": hasCourses = true
    case "Gradebook/ReportingPeriods/ReportPeriod":
      if let period = period(a) { periods.append(period) } else { invalid = true }
    case "Gradebook/ReportingPeriod": selectedPeriod = period(a)
    case "Gradebook/Courses/Course":
      guard let identifier = a["CourseID"], !identifier.isEmpty else {
        invalid = true
        return
      }
      currentCourse = Course(
        wireID: identifier, title: a["CourseName"] ?? a["Title"] ?? "Course",
        period: a["Period"] ?? "", teacher: a["Staff"] ?? "", room: a["Room"] ?? "")
      hasMark = false
    case "Gradebook/Courses/Course/Marks/Mark":
      selectedMark = !hasMark
      hasMark = true
      if selectedMark {
        currentCourse?.officialMark = a["CalculatedScoreString"] ?? ""
        currentCourse?.officialPercent = finiteNumber(a["CalculatedScoreRaw"])
      }
    case "Gradebook/Courses/Course/Marks/Mark/GradeCalculationSummary/AssignmentGradeCalc":
      if selectedMark {
        currentCourse?.categories.append(
          GradeCategory(
            name: a["Type"] ?? "Category", weight: finiteNumber(a["Weight"]),
            earned: finiteNumber(a["Points"]), possible: finiteNumber(a["PointsPossible"])))
      }
    case "Gradebook/Courses/Course/Marks/Mark/Assignments/Assignment":
      if selectedMark {
        let fallbackID = "assignment-\(currentCourse?.assignments.count ?? 0)"
        currentCourse?.assignments.append(AssignmentDecoder.decode(a, fallbackID: fallbackID))
      }
    default: break
    }
  }

  func parser(
    _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?
  ) {
    if path == ["Gradebook", "Courses", "Course"] {
      if let course = currentCourse {
        if courses.contains(where: { $0.id == course.id }) { invalid = true }
        if Set(course.assignments.map(\.id)).count != course.assignments.count { invalid = true }
        courses.append(course)
      }
      currentCourse = nil
    }
    if path == ["Gradebook", "Courses", "Course", "Marks", "Mark"] { selectedMark = false }
    if !path.isEmpty { path.removeLast() }
  }

  private func period(_ a: [String: String]) -> ReportingPeriod? {
    guard let value = a["Index"], let index = Int(value), (0...999).contains(index) else {
      return nil
    }
    return ReportingPeriod(index: index, name: a["GradePeriod"] ?? "Reporting period")
  }
}
