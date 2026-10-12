import Foundation
import GrademaxxingCore

func attendanceFixture() throws -> Data {
  try Data(contentsOf: require(Bundle.module.url(forResource: "attendance", withExtension: "json")))
}

enum SchoolTests {
  static func normalizedAttendanceMatchesBackendAndExcludesNonSchoolDays() throws {
    let book = try AttendanceDecoder.decode(attendanceFixture())
    try expect(book.schoolName == "Synthetic High School")
    try expect(book.records.map(\.date.iso) == ["2026-10-08", "2026-10-06", "2026-10-05"])
    try expect(book.records.map(\.status) == [.excused, .tardy, .present])
    try expect(book.records.first?.periods.first?.course == "Synthetic English")
    try expect(book.courseTotals.first?.present == 28)
  }
  static func authoritativePeriodIncidentOverridesDailyPresence() throws {
    let data = Data(
      """
      {"Absences":{"Absence":[{"_AbsenceDate":"2026-10-06","_Reason":"","_Note":"",
      "Periods":{"Period":[{"_Number":"3","_Name":"Unexcused","_Reason":"","_Course":""}]}}]},
      "DailyRecords":[{"Date":"2026-10-06","Status":"present","Reason":"Present"}]}
      """.utf8)
    let book = try AttendanceDecoder.decode(data)
    try expect(book.records.count == 1)
    try expect(book.records.first?.status == .absent)
    try expect(book.records.first?.periods.first?.number == "3")
    try expect(book.courseTotals.isEmpty)
  }
  static func statusRecognitionPreservesUnknownAndUnexcusedTardy() throws {
    try expect(AttendanceStatus.classify("Unexcused") == .absent)
    try expect(AttendanceStatus.classify("Unexcused Tardy") == .tardy)
    try expect(AttendanceStatus.classify("Field Trip") == .activity)
    try expect(AttendanceStatus.classify("Medical appointment") == .excused)
    try expect(AttendanceStatus.classify("11") == .unknown)
    try expect(AttendanceStatus.classify("Holiday") == .unknown)
  }
  static func rejectsInvalidAttendanceDatesAndNegativeTotals() throws {
    let invalid = Data(
      "{\"Absences\":{},\"DailyRecords\":[{\"Date\":\"2026-02-30\",\"Status\":\"present\",\"Reason\":\"\"}]}"
        .utf8)
    try expectThrows(APIError.invalidResponse) { try AttendanceDecoder.decode(invalid) }
    let negative = Data(
      "{\"Absences\":{},\"CourseTotals\":[{\"Course\":\"Synthetic\",\"Present\":-1}]}".utf8)
    try expectThrows(APIError.invalidResponse) { try AttendanceDecoder.decode(negative) }
  }
  static func schoolDatesHandleLeapYearsAndStrictISO() throws {
    try expect(SchoolDate(iso: "2024-02-29") != nil)
    try expect(SchoolDate(iso: "2026-02-29") == nil)
    try expect(SchoolDate(iso: "2026-02-30") == nil)
    try expect(SchoolDate(iso: "2026-+1-01") == nil)
    try expect(SchoolDate(iso: "2026-1-01") == nil)
    try expect(SchoolDate(iso: "2026-10-11T00:00:00Z") == nil)
    let date = try require(SchoolDate(iso: "2026-10-11"))
    let calendar = Calendar(identifier: .gregorian)
    try expect(calendar.component(.day, from: date.localDate) == 11)
    try expect(date.iso == "2026-10-11")
  }
  static func calendarMonthNavigationHonorsAPIYearLimits() throws {
    let month = try require(SchoolMonth(year: 2024, month: 2))
    try expect(month.days.count == 29)
    try expect(month.offset(-2) == SchoolMonth(year: 2023, month: 12))
    try expect(SchoolMonth(year: 2000, month: 1)?.offset(-1) == nil)
    try expect(SchoolMonth(year: 2200, month: 12)?.offset(1) == nil)
    try expect(month.offset(Int.min) == nil)
    try expect(SchoolMonth(year: 2026, month: 13) == nil)
  }
  static func calendarFiltersMonthAndKeepsDuplicateEventOccurrencesDistinct() throws {
    let month = try require(SchoolMonth(year: 2026, month: 10))
    let event: [String: String] = [
      "id": "", "title": "Synthetic", "type": "Event", "date": "2026-10-08", "time": "",
      "description": "", "details": "",
    ]
    var nextMonth = event
    nextMonth["date"] = "2026-11-01"
    let data = try JSONSerialization.data(withJSONObject: [
      "startDate": "2026-10-01", "endDate": "2026-11-01", "events": [event, event, nextMonth],
    ])
    let calendar = try CalendarDecoder.decode(data, month: month)
    try expect(calendar.events.count == 2)
    try expect(Set(calendar.events.map(\.id)).count == 2)
    try expect(calendar.startDate?.iso == "2026-10-01")
  }
  static func calendarRejectsInvalidEventDates() throws {
    let month = try require(SchoolMonth(year: 2026, month: 10))
    let data = Data(
      """
      {"startDate":"","endDate":"","events":[{"id":"synthetic","title":"Synthetic","type":"Event",
      "date":"2026-13-01","time":"","description":"","details":""}]}
      """.utf8)
    try expectThrows(APIError.invalidResponse) { try CalendarDecoder.decode(data, month: month) }
  }
  static func everySchoolDemoUsesRealDecoders() throws {
    try expect(try SchoolDemoData.attendance().records.count == 5)
    try expect(
      try SchoolDemoData.calendar(month: require(SchoolMonth(year: 2026, month: 10))).events.count
        == 3)
    try expect(try SchoolDemoData.schedule().classes.count == 5)
    try expect(try SchoolDemoData.profile().name == "Demo Student")
  }
}

private actor SuspendedRecord {
  private var started = false
  private var watcher: CheckedContinuation<Void, Never>?
  private var result: CheckedContinuation<String, Never>?
  func fetch() async -> String {
    started = true
    watcher?.resume()
    watcher = nil
    return await withCheckedContinuation { result = $0 }
  }
  func waitForStart() async {
    if !started { await withCheckedContinuation { watcher = $0 } }
  }
  func complete(_ value: String) {
    result?.resume(returning: value)
    result = nil
  }
}

@MainActor enum RecordStoreTests {
  static func invalidationIgnoresInFlightRecordAfterSignOut() async throws {
    let store = RecordStore<String>()
    let suspended = SuspendedRecord()
    let task = Task { await store.load(fetch: { await suspended.fetch() }, onFailure: { _ in }) }
    await suspended.waitForStart()
    try expect(store.isLoading)
    store.clear()
    await suspended.complete("synthetic-old-account")
    await task.value
    try expect(store.value == nil)
    try expect(store.updatedAt == nil)
    try expect(!store.isLoading)
  }
  static func anOldRecordCannotReplaceNewAccountOrMonth() async throws {
    let store = RecordStore<String>()
    let suspended = SuspendedRecord()
    let task = Task { await store.load(fetch: { await suspended.fetch() }, onFailure: { _ in }) }
    await suspended.waitForStart()
    store.clear()
    await store.load(fetch: { "synthetic-new-account" }, onFailure: { _ in })
    await suspended.complete("synthetic-old-account")
    await task.value
    try expect(store.value == "synthetic-new-account")
    try expect(!store.isLoading)
  }
  static func cachedReadsAndForcedRefreshHaveSeparateBehavior() async throws {
    let store = RecordStore<String>()
    var reads = 0
    func fetch() -> String {
      reads += 1
      return "synthetic-\(reads)"
    }
    await store.load(fetch: fetch, onFailure: { _ in })
    await store.load(fetch: fetch, onFailure: { _ in })
    try expect(reads == 1)
    await store.load(force: true, fetch: fetch, onFailure: { _ in })
    try expect(reads == 2)
    await store.load(force: true, fetch: { throw APIError.unavailable }, onFailure: { _ in })
    try expect(store.value == "synthetic-2")
    try expect(store.error == APIError.unavailable.errorDescription)
    try expect(!store.isLoading)
  }
}
