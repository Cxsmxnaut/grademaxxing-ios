import Foundation

/// A date in the school calendar, without a timezone or time-of-day conversion.
public struct SchoolDate: Hashable, Comparable, Sendable {
  public let year: Int
  public let month: Int
  public let day: Int
  public var iso: String { String(format: "%04d-%02d-%02d", year, month, day) }
  public init?(iso: String) {
    let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
      (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day)
    else { return nil }
    guard String(format: "%04d-%02d-%02d", year, month, day) == iso else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = DateComponents(year: year, month: month, day: day, hour: 12)
    guard let value = calendar.date(from: components),
      calendar.component(.month, from: value) == month,
      calendar.component(.day, from: value) == day
    else { return nil }
    self.year = year
    self.month = month
    self.day = day
  }
  public static func < (lhs: SchoolDate, rhs: SchoolDate) -> Bool { lhs.iso < rhs.iso }
  /// Construct at local noon so displaying a date cannot cross a day at midnight or DST.
  public var localDate: Date {
    Calendar(identifier: .gregorian).date(
      from: DateComponents(year: year, month: month, day: day, hour: 12))!
  }
}

public struct SchoolMonth: Hashable, Sendable {
  public let year: Int
  public let month: Int
  public init?(year: Int, month: Int) {
    guard (2000...2200).contains(year), (1...12).contains(month) else { return nil }
    self.year = year
    self.month = month
  }
  public static var current: SchoolMonth {
    let calendar = Calendar(identifier: .gregorian)
    return SchoolMonth(
      year: calendar.component(.year, from: Date()), month: calendar.component(.month, from: Date())
    )!
  }
  public var firstDay: SchoolDate { SchoolDate(iso: String(format: "%04d-%02d-01", year, month))! }
  public var days: [SchoolDate] {
    let calendar = Calendar(identifier: .gregorian)
    let count = calendar.range(of: .day, in: .month, for: firstDay.localDate)!.count
    return (1...count).compactMap {
      SchoolDate(iso: String(format: "%04d-%02d-%02d", year, month, $0))
    }
  }
  public func contains(_ date: SchoolDate) -> Bool { date.year == year && date.month == month }
  public func offset(_ amount: Int) -> SchoolMonth? {
    guard (-2_400...2_400).contains(amount),
      let date = Calendar(identifier: .gregorian).date(
        byAdding: .month, value: amount, to: firstDay.localDate)
    else { return nil }
    let calendar = Calendar(identifier: .gregorian)
    return SchoolMonth(
      year: calendar.component(.year, from: date), month: calendar.component(.month, from: date))
  }
}

public enum AttendanceStatus: String, CaseIterable, Sendable {
  case present = "Present"
  case absent = "Absent"
  case tardy = "Tardy"
  case excused = "Excused"
  case activity = "Activity"
  case unknown = "Unknown"
  public static func classify(_ text: String) -> AttendanceStatus {
    let value = text.lowercased()
    if value.contains("truan") || value.contains("absent") || value.contains("non ada") {
      return .absent
    }
    if value.contains("tardy") || value.contains("late") { return .tardy }
    if value.contains("unexcused") || value.contains("unverified") { return .absent }
    if value.contains("field trip") || value.contains("activity")
      || value.contains("school business") || value.contains("school pass")
    {
      return .activity
    }
    if value.contains("excused") || value.contains("illness") || value.contains("medical")
      || value.contains("wellness")
    {
      return .excused
    }
    if value.contains("present") { return .present }
    return .unknown
  }
  var priority: Int {
    switch self {
    case .absent: 5
    case .tardy: 4
    case .excused: 3
    case .activity: 2
    case .present: 1
    case .unknown: 0
    }
  }
}

public struct AttendancePeriod: Equatable, Sendable {
  public let number: String
  public let course: String
  public let status: String
  public let reason: String
}
public struct AttendanceRecord: Identifiable, Equatable, Sendable {
  public var id: String { date.iso }
  public let date: SchoolDate
  public let status: AttendanceStatus
  public let reason: String
  public let periods: [AttendancePeriod]
}
public struct AttendanceCourseTotal: Equatable, Sendable, Decodable {
  public let course: String
  public let present: Int?
  public let tardy: Int?
  public let absent: Int?
  public let excused: Int?
  public let unexcused: Int?
  enum CodingKeys: String, CodingKey {
    case course = "Course"
    case present = "Present"
    case tardy = "Tardy"
    case absent = "Absent"
    case excused = "Excused"
    case unexcused = "Unexcused"
  }
}
public struct AttendanceBook: Equatable, Sendable {
  public let schoolName: String
  public let records: [AttendanceRecord]
  public let courseTotals: [AttendanceCourseTotal]
}

public enum AttendanceDecoder {
  public static func decode(_ data: Data) throws -> AttendanceBook {
    struct Wire: Decodable {
      struct Absences: Decodable {
        struct Absence: Decodable {
          struct Periods: Decodable {
            struct Period: Decodable {
              let _Number: String
              let _Name: String
              let _Reason: String
              let _Course: String
            }
            let entries: [Period]?
            enum CodingKeys: String, CodingKey { case entries = "Period" }
          }
          let _AbsenceDate: String
          let _Reason: String
          let _Note: String
          let periods: Periods
          enum CodingKeys: String, CodingKey {
            case _AbsenceDate, _Reason, _Note
            case periods = "Periods"
          }
        }
        let entries: [Absence]?
        enum CodingKeys: String, CodingKey { case entries = "Absence" }
      }
      struct Daily: Decodable {
        let date: String
        let status: String
        let reason: String
        enum CodingKeys: String, CodingKey {
          case date = "Date"
          case status = "Status"
          case reason = "Reason"
        }
      }
      let absences: Absences
      let dailyRecords: [Daily]?
      let courseTotals: [AttendanceCourseTotal]?
      let _SchoolName: String?
      enum CodingKeys: String, CodingKey {
        case absences = "Absences"
        case dailyRecords = "DailyRecords"
        case courseTotals = "CourseTotals"
        case _SchoolName
      }
    }
    guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else {
      throw APIError.invalidResponse
    }
    var byDate: [SchoolDate: AttendanceRecord] = [:]
    for day in wire.dailyRecords ?? [] {
      guard let date = SchoolDate(iso: day.date) else { throw APIError.invalidResponse }
      byDate[date] = AttendanceRecord(
        date: date, status: .classify(day.status + " " + day.reason), reason: day.reason,
        periods: [])
    }
    for absence in wire.absences.entries ?? [] {
      guard let date = SchoolDate(iso: absence._AbsenceDate) else { throw APIError.invalidResponse }
      let periods = (absence.periods.entries ?? []).map {
        AttendancePeriod(
          number: $0._Number, course: $0._Course, status: $0._Name, reason: $0._Reason)
      }
      let statuses = periods.map { AttendanceStatus.classify($0.status + " " + $0.reason) }
      let status = statuses.max(by: { $0.priority < $1.priority }) ?? .classify(absence._Reason)
      byDate[date] = AttendanceRecord(
        date: date, status: status, reason: absence._Note.isEmpty ? absence._Reason : absence._Note,
        periods: periods)
    }
    let totals = wire.courseTotals ?? []
    guard
      totals.allSatisfy({ total in
        [total.present, total.tardy, total.absent, total.excused, total.unexcused].compactMap { $0 }
          .allSatisfy { $0 >= 0 }
      })
    else { throw APIError.invalidResponse }
    return AttendanceBook(
      schoolName: wire._SchoolName ?? "", records: byDate.values.sorted { $0.date > $1.date },
      courseTotals: totals)
  }
}

public struct CalendarEvent: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let type: String
  public let date: SchoolDate
  public let time: String
  public let description: String
  public let details: String
}
public struct SchoolCalendar: Equatable, Sendable {
  public let month: SchoolMonth
  public let startDate: SchoolDate?
  public let endDate: SchoolDate?
  public let events: [CalendarEvent]
}
public enum CalendarDecoder {
  public static func decode(_ data: Data, month: SchoolMonth) throws -> SchoolCalendar {
    struct Wire: Decodable {
      struct Event: Decodable {
        let id: String
        let title: String
        let type: String
        let date: String
        let time: String
        let description: String
        let details: String
      }
      let startDate: String
      let endDate: String
      let events: [Event]
    }
    guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else {
      throw APIError.invalidResponse
    }
    let events = try wire.events.enumerated().compactMap { index, item -> CalendarEvent? in
      guard let date = SchoolDate(iso: item.date) else { throw APIError.invalidResponse }
      guard month.contains(date) else { return nil }
      // An event's upstream ID may be empty or repeated; occurrences still need distinct list IDs.
      return CalendarEvent(
        id: "\(item.id)|\(date.iso)|\(index)", title: item.title, type: item.type, date: date,
        time: item.time, description: item.description, details: item.details)
    }.sorted { $0.date == $1.date ? $0.time < $1.time : $0.date < $1.date }
    return SchoolCalendar(
      month: month, startDate: SchoolDate(iso: wire.startDate),
      endDate: SchoolDate(iso: wire.endDate), events: events)
  }
}

public struct ScheduleClass: Decodable, Equatable, Sendable {
  public let period: String
  public let courseTitle: String
  public let teacher: String
  public let room: String
  public let startTime: String
  public let endTime: String
  public let schoolName: String
  public let date: String
}
public struct SchoolSchedule: Decodable, Equatable, Sendable {
  public let date: String
  public let classes: [ScheduleClass]
}
public struct StudentProfile: Decodable, Equatable, Sendable {
  public let name: String
  public let permId: String
  public let grade: String
  public let fields: [String: String]
}
