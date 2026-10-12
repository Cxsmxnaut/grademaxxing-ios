import Foundation

public enum AssignmentDecoder {
  /// The same weighted/raw/published evidence rules as parseSynergyAssignment in the web app.
  public static func decode(_ a: [String: String], fallbackID: String = "assignment") -> Assignment
  {
    let display = a["Points"] ?? ""
    let pattern = "^\\s*(-?\\d+(?:\\.\\d+)?)\\s*/\\s*(-?\\d+(?:\\.\\d+)?)?\\s*$"
    let match = captures(display, pattern)
    let earnedText = a["Point"] ?? match?.first
    let possibleText = a["PointPossible"] ?? match?.dropFirst().first
    let earned: Double? = a["Point"] == "" ? 0 : number(earnedText)
    let displayedMaximum =
      display.contains("/")
      ? number(match?.dropFirst().first)
      : number(display.components(separatedBy: " Points Possible").first)
    let maximum = number(a["PointPossible"]) ?? displayedMaximum
    let unavailable =
      a["CalculationUnavailable"]?.lowercased() == "true" || a["CalculationUnavailable"] == "1"
    let extra =
      !unavailable
      && (a["PointPossible"] == "" || (match != nil && number(match?.dropFirst().first) == nil)
        || maximum == 0)
    let possible = extra ? 0 : maximum
    let percentage = number(a["AssignmentPercentage"])
    var calculationEarned: Double?
    if let percentage, let possible, possible > 0, !extra {
      let precision = number(a["AssignmentPercentagePrecision"])
      let precise =
        precision.map {
          $0 >= 0 && $0.rounded() == $0
            && pow(10, -$0)
              < ratioUncertainty(
                earned: earned ?? 0, possible: possible, earnedText: earnedText,
                possibleText: possibleText)
        } ?? true
      if earned == nil || precise { calculationEarned = percentage / 100 * possible }
    }
    return Assignment(
      id: a["GradebookID"] ?? fallbackID, title: a["Measure"] ?? "Assignment",
      category: a["Type"] ?? "",
      dueDate: a["DueDate"] ?? "", displayScore: a["DisplayScore"] ?? "", notes: a["Notes"] ?? "",
      pointsEarned: earned, pointsPossible: possible, publishedPercent: percentage,
      calculationUnavailable: unavailable,
      postedDate: a["Date"] ?? "", rawEarned: number(a["ScoreCalValue"]),
      rawPossible: number(a["ScoreMaxValue"]),
      calculationEarned: calculationEarned, extraCredit: extra,
      description: a["MeasureDescription"] ?? "", scoreEvidence: scoreEvidence(a["Score"]))
  }
  private static func scoreEvidence(_ text: String?) -> Double? {
    guard let text,
      let range = text.range(
        of: "^\\s*-?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:e[+-]?\\d+)?",
        options: [.regularExpression, .caseInsensitive])
    else { return nil }
    return number(String(text[range]))
  }
  private static func number(_ text: String?) -> Double? {
    guard let text,
      text.trimmingCharacters(in: .whitespacesAndNewlines).range(
        of: "^-?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:e[+-]?\\d+)?$",
        options: [.regularExpression, .caseInsensitive]) != nil,
      let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite
    else { return nil }
    return value
  }
  private static func captures(_ text: String, _ pattern: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
      let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    else { return nil }
    return (1..<result.numberOfRanges).map {
      Range(result.range(at: $0), in: text).map { String(text[$0]) } ?? ""
    }
  }
  private static func uncertainty(_ text: String?) -> Double {
    guard let text,
      let groups = captures(
        text.trimmingCharacters(in: .whitespacesAndNewlines),
        "^-?(?:\\d+(?:\\.(\\d*))?|\\.(\\d+))(?:e([+-]?\\d+))?$"), groups.count == 3
    else { return .infinity }
    let decimalPlaces = (groups[0].isEmpty ? groups[1] : groups[0]).count
    return 0.5 * pow(10, Double(Int(groups[2]) ?? 0) - Double(decimalPlaces))
  }
  private static func ratioUncertainty(
    earned: Double, possible: Double, earnedText: String?, possibleText: String?
  ) -> Double {
    let earnedDelta = uncertainty(earnedText)
    let possibleDelta = uncertainty(possibleText)
    guard possible > possibleDelta else { return .infinity }
    let ratios = [
      (earned - earnedDelta) / (possible - possibleDelta),
      (earned - earnedDelta) / (possible + possibleDelta),
      (earned + earnedDelta) / (possible - possibleDelta),
      (earned + earnedDelta) / (possible + possibleDelta),
    ]
    return ratios.map { abs($0 - earned / possible) * 100 }.max() ?? .infinity
  }
}
