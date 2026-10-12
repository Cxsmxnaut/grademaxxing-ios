import Foundation

public struct ReportingPeriod: Identifiable, Equatable, Sendable {
  public var id: Int { index }
  public let index: Int
  public let name: String
  public init(index: Int, name: String) {
    self.index = index
    self.name = name
  }
}

public struct Gradebook: Equatable, Sendable {
  public let periods: [ReportingPeriod]
  public let selectedPeriod: ReportingPeriod
  public let courses: [Course]
  public let detailed: Bool
  public init(
    periods: [ReportingPeriod], selectedPeriod: ReportingPeriod, courses: [Course],
    detailed: Bool = true
  ) {
    self.periods = periods
    self.selectedPeriod = selectedPeriod
    self.courses = courses
    self.detailed = detailed
  }
}

public struct Course: Identifiable, Equatable, Sendable {
  public var id: String { "\(wireID)|\(period)" }
  public let wireID: String
  public let title: String
  public let period: String
  public let teacher: String
  public let room: String
  /// Official values from the portal, never replaced with a local calculation.
  public var officialMark: String
  public var officialPercent: Double?
  public var assignments: [Assignment]
  public var categories: [GradeCategory]
  public init(
    wireID: String, title: String, period: String, teacher: String = "", room: String = "",
    officialMark: String = "", officialPercent: Double? = nil,
    assignments: [Assignment] = [], categories: [GradeCategory] = []
  ) {
    self.wireID = wireID
    self.title = title
    self.period = period
    self.teacher = teacher
    self.room = room
    self.officialMark = officialMark
    self.officialPercent = officialPercent
    self.assignments = assignments
    self.categories = categories
  }
}

public struct Assignment: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let category: String
  public let dueDate: String
  public let displayScore: String
  public let notes: String
  public let pointsEarned: Double?
  public let pointsPossible: Double?
  public let publishedPercent: Double?
  public let calculationUnavailable: Bool
  public let postedDate: String
  public let rawEarned: Double?
  public let rawPossible: Double?
  public let calculationEarned: Double?
  public let extraCredit: Bool
  public let description: String
  public let scoreEvidence: Double?
  public var excluded: Bool {
    notes.range(
      of: "^\\s*\\(\\s*not\\s+for\\s+grading\\s*\\)",
      options: [.regularExpression, .caseInsensitive]) != nil
  }
  public var isGraded: Bool {
    if excluded { return false }
    if publishedPercent != nil { return true }
    if displayScore.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "not graded" {
      return false
    }
    return pointsEarned != nil || rawEarned != nil || scoreEvidence != nil
  }
  public init(
    id: String, title: String, category: String, dueDate: String = "", displayScore: String = "",
    notes: String = "", pointsEarned: Double? = nil, pointsPossible: Double? = nil,
    publishedPercent: Double? = nil, calculationUnavailable: Bool = false,
    postedDate: String = "", rawEarned: Double? = nil, rawPossible: Double? = nil,
    calculationEarned: Double? = nil, extraCredit: Bool = false, description: String = "",
    scoreEvidence: Double? = nil
  ) {
    self.id = id
    self.title = title
    self.category = category
    self.dueDate = dueDate
    self.displayScore = displayScore
    self.notes = notes
    self.pointsEarned = pointsEarned
    self.pointsPossible = pointsPossible
    self.publishedPercent = publishedPercent
    self.calculationUnavailable = calculationUnavailable
    self.postedDate = postedDate
    self.rawEarned = rawEarned
    self.rawPossible = rawPossible
    self.calculationEarned = calculationEarned
    self.extraCredit = extraCredit
    self.description = description
    self.scoreEvidence = scoreEvidence
  }
}

public struct GradeCategory: Identifiable, Equatable, Sendable {
  public var id: String { name }
  public let name: String
  public let weight: Double?
  public let earned: Double?
  public let possible: Double?
  public init(name: String, weight: Double?, earned: Double?, possible: Double?) {
    self.name = name
    self.weight = weight
    self.earned = earned
    self.possible = possible
  }
}

public enum APIError: Error, Equatable, Sendable, LocalizedError {
  case invalidConfiguration, invalidInput, invalidResponse, sessionInvalid, reconnectRequired
  case authenticationFailed, rateLimited, unavailable, network, secureStorage
  case http(Int)
  case invalidFile, unsupportedFile, fileStorage, responseTooLarge
  public var errorDescription: String? {
    switch self {
    case .invalidConfiguration: "The service address must be a secure HTTPS origin."
    case .invalidInput: "Enter a valid HTTPS district portal address, username, and password."
    case .invalidResponse: "The school data could not be read. Try refreshing again."
    case .sessionInvalid: "Your app session has ended. Sign in again."
    case .reconnectRequired:
      "StudentVUE needs you to reconnect. Your current grades remain visible."
    case .authenticationFailed: "Sign-in failed. Check your district, username, and password."
    case .rateLimited: "Too many requests. Wait a few minutes before trying again."
    case .unavailable: "The school service is busy or unavailable. Try again shortly."
    case .network: "Could not reach the service. Check your connection and try again."
    case .secureStorage: "The device could not securely save or remove your session. Try again."
    case .http: "The request could not be completed. Try again."
    case .invalidFile: "The file has an invalid size, type, or contents. Open it in StudentVUE."
    case .unsupportedFile: "This format cannot be previewed here. Open it in StudentVUE."
    case .fileStorage: "The device could not create or clear the temporary preview. Try again."
    case .responseTooLarge: "The response is too large to open in the app. Open it in StudentVUE."
    }
  }
}

func finiteNumber(_ value: String?) -> Double? {
  guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
    let number = Double(
      value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)),
    number.isFinite
  else { return nil }
  return number
}
