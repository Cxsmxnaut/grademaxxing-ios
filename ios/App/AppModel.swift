import GrademaxxingCore
import Observation
import SwiftUI

@MainActor @Observable
final class AppModel {
  enum Phase { case starting, signedOut, signedIn }
  var phase: Phase = .starting
  var identity: SessionIdentity?
  var gradebook: Gradebook?
  var isDemo = false
  var isWorking = false
  var message: String?
  var needsReconnect = false
  var lastUpdated: Date?
  var planner: [GPAEntry] = []
  var attendance = RecordStore<AttendanceBook>()
  var calendar = RecordStore<SchoolCalendar>()
  var schedule = RecordStore<SchoolSchedule>()
  var profile = RecordStore<StudentProfile>()
  var documents = RecordStore<[SchoolDocument]>()
  var mailbox = RecordStore<Mailbox>()
  var messageDetail = RecordStore<ReadableMessage>()
  var preview = PreviewSession()
  var portalURL: URL? {
    guard let domain = identity?.domain,
      let url = URL(string: domain.hasPrefix("https://") ? domain : "https://" + domain),
      url.scheme == "https", url.host != nil, url.user == nil, url.password == nil
    else { return nil }
    return url
  }
  var schoolSessionKey: String { isDemo ? "synthetic-demo" : identity?.sessionId ?? "signed-out" }
  let serviceOrigin: URL
  @ObservationIgnored private let api: APIClient?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private var lastKeepAlive = Date.distantPast
  @ObservationIgnored private let gradebooks = GradebookRepository()
  @ObservationIgnored private var plannerSeeds: [GPAEntry] = []

  init() {
    let configured = Bundle.main.object(forInfoDictionaryKey: "GrademaxxingAPIOrigin") as? String
    // Keep the first native build pointed at pre-production. Change Info.plist deliberately for release.
    let candidate = URL(string: configured ?? "https://dev.grademaxxing.app")
    let configuration = candidate.flatMap { try? ServiceConfiguration(origin: $0) }
    serviceOrigin = configuration?.origin ?? URL(string: "https://dev.grademaxxing.app")!
    api = configuration.map {
      APIClient(
        configuration: $0,
        vault: KeychainSessionVault(
          service: "app.grademaxxing.native.\($0.origin.host ?? "beta")"))
    }
    if configuration == nil {
      phase = .signedOut
      message = APIError.invalidConfiguration.errorDescription
    }
    if CommandLine.arguments.contains("--demo") { enterDemo() }
  }

  func restore() async {
    guard phase == .starting else { return }
    let version = generation
    do {
      let restored = try await requireAPI().restore()
      guard generation == version else { return }
      identity = restored
      phase = restored == nil ? .signedOut : .signedIn
      if restored != nil { await refresh() }
    } catch {
      guard generation == version else { return }
      phase = .signedOut
      message = friendly(error)
    }
  }

  func signIn(domain: String, username: String, password: String) async {
    guard !isWorking else { return }
    let version = generation
    isWorking = true
    message = nil
    defer { if generation == version { isWorking = false } }
    do {
      let result = try await requireAPI().login(
        domain: domain, username: username, password: password)
      guard generation == version else { return }
      identity = result
      phase = .signedIn
      isDemo = false
      needsReconnect = false
      gradebook = nil
      planner = []
      plannerSeeds = []
      lastUpdated = nil
      gradebooks.clear()
      clearSchoolRecords()
      try await loadGradebook(period: nil, version: version)
    } catch { if generation == version { handle(error) } }
  }

  func refresh(period: Int? = nil) async {
    guard !isWorking else { return }
    if isDemo {
      apply(DemoData.gradebook(period: period ?? gradebook?.selectedPeriod.index ?? 0))
      return
    }
    guard identity != nil, !needsReconnect else { return }
    let version = generation
    isWorking = true
    message = nil
    defer { if generation == version { isWorking = false } }
    do {
      try await loadGradebook(period: period ?? gradebook?.selectedPeriod.index, version: version)
    } catch { if generation == version { handle(error) } }
  }

  func reconnect(password: String) async {
    guard let account = identity, !isWorking, !isDemo else { return }
    let version = generation
    isWorking = true
    message = nil
    defer { if generation == version { isWorking = false } }
    do {
      let result = try await requireAPI().login(
        domain: account.domain, username: account.username, password: password)
      guard generation == version else { return }
      identity = result
      needsReconnect = false
      gradebooks.clear()
      clearSchoolRecords()
      try await loadGradebook(period: gradebook?.selectedPeriod.index, version: version)
    } catch { if generation == version { handle(error) } }
  }

  func resume() async {
    guard phase == .signedIn, !isDemo, !isWorking, !needsReconnect else { return }
    let period = gradebook?.selectedPeriod.index
    let fullRead =
      period.flatMap { gradebooks.cached(owner: schoolSessionKey, period: $0)?.fullReadAt }
      ?? .distantPast
    let needsFullRead =
      period != nil
      && Date().timeIntervalSince(fullRead) >= GradebookRepository.completeRefreshInterval
    guard needsFullRead || Date().timeIntervalSince(lastKeepAlive) > 240 else { return }
    let version = generation
    isWorking = true
    defer { if generation == version { isWorking = false } }
    do {
      if needsFullRead, let period {
        try await loadGradebook(period: period, version: version, resetPlanner: false)
      } else {
        try await requireAPI().keepAlive()
        if generation == version { lastKeepAlive = Date() }
      }
    } catch { if generation == version { handle(error) } }
  }

  func enterDemo() {
    generation += 1
    isDemo = true
    isWorking = false
    needsReconnect = false
    message = nil
    identity = nil
    phase = .signedIn
    clearSchoolRecords()
    gradebooks.clear()
    apply(DemoData.gradebook())
  }

  func signOut() async {
    let wasDemo = isDemo
    generation += 1
    gradebook = nil
    planner = []
    plannerSeeds = []
    identity = nil
    lastUpdated = nil
    gradebooks.clear()
    clearSchoolRecords()
    needsReconnect = false
    isDemo = false
    isWorking = true
    message = nil
    phase = .signedOut
    defer { isWorking = false }
    // Leaving the demo does not touch a previously saved real session.
    if !wasDemo {
      do { try await requireAPI().logout() } catch { message = friendly(error) }
    }
  }

  func resetPlanner() {
    planner = GPAPlanning.entries(
      for: gradebook?.courses ?? [], gradeLevel: Int(profile.value?.grade ?? "") ?? 9)
    plannerSeeds = planner
  }
  func selectPeriod(_ period: Int) async {
    guard !isWorking, !needsReconnect else { return }
    if isDemo {
      apply(DemoData.gradebook(period: period))
      return
    }
    guard identity != nil else { return }
    let version = generation
    let cached = gradebooks.cached(owner: schoolSessionKey, period: period)
    if let cached {
      apply(cached.book)
      lastUpdated = cached.checkedAt
    }
    isWorking = true
    message = nil
    defer { if generation == version { isWorking = false } }
    do {
      try await loadGradebook(
        period: period, version: version, force: false, resetPlanner: cached == nil)
    } catch { if generation == version { handle(error) } }
  }
  func loadAttendance(force: Bool = false) async {
    guard phase == .signedIn, !needsReconnect else { return }
    await attendance.load(
      force: force, maxAge: 3_600,
      fetch: {
        if self.isDemo { return try SchoolDemoData.attendance() }
        return try await self.requireAPI().attendance()
      }, onFailure: handleSchoolFailure)
  }
  func loadCalendar(month: SchoolMonth, force: Bool = false) async {
    guard phase == .signedIn, !needsReconnect else { return }
    if calendar.value?.month != month { calendar.clear() }
    await calendar.load(
      force: force,
      fetch: {
        if self.isDemo { return try SchoolDemoData.calendar(month: month) }
        return try await self.requireAPI().calendar(month: month)
      }, onFailure: handleSchoolFailure)
  }
  func loadSchedule(force: Bool = false) async {
    guard phase == .signedIn, !needsReconnect else { return }
    await schedule.load(
      force: force,
      fetch: {
        if self.isDemo { return try SchoolDemoData.schedule() }
        return try await self.requireAPI().schedule()
      }, onFailure: handleSchoolFailure)
  }
  func loadProfile(force: Bool = false) async {
    guard phase == .signedIn, !needsReconnect else { return }
    await profile.load(
      force: force, maxAge: 3_600,
      fetch: {
        if self.isDemo { return try SchoolDemoData.profile() }
        return try await self.requireAPI().profile()
      }, onFailure: handleSchoolFailure)
  }
  func loadDocuments(force: Bool = false) async {
    guard phase == .signedIn, !needsReconnect else { return }
    await documents.load(
      force: force,
      fetch: {
        if self.isDemo { return try DocumentsMailDemo.documents() }
        return try await self.requireAPI().documents()
      }, onFailure: handleSchoolFailure)
  }
  func loadMailbox(force: Bool = false) async {
    guard phase == .signedIn, !needsReconnect else { return }
    await mailbox.load(
      force: force, maxAge: 300,
      fetch: {
        if self.isDemo { return try DocumentsMailDemo.mailbox() }
        return try await self.requireAPI().mailbox()
      }, onFailure: handleSchoolFailure)
  }
  func loadMessage(_ message: MailPreview, force: Bool = false) async {
    guard phase == .signedIn, !needsReconnect, let id = message.messageID else { return }
    if messageDetail.value?.messageID != id || messageDetail.value?.isSystem != message.isSystem {
      messageDetail.clear()
    }
    await messageDetail.load(
      force: force,
      fetch: {
        if self.isDemo { return try DocumentsMailDemo.message(id: id) }
        return try await self.requireAPI().message(id: id, isSystem: message.isSystem)
      }, onFailure: handleSchoolFailure)
  }
  func openDocument(_ document: SchoolDocument) async {
    guard phase == .signedIn, !needsReconnect else { return }
    await preview.open(
      name: document.title,
      fetch: {
        if self.isDemo { return try DocumentsMailDemo.file() }
        return try await self.requireAPI().document(id: document.id)
      }, onFailure: handleSchoolFailure)
  }
  func openAttachment(_ attachment: MailAttachment) async {
    guard phase == .signedIn, !needsReconnect else { return }
    await preview.open(
      name: attachment.name,
      fetch: {
        if self.isDemo { return try DocumentsMailDemo.file() }
        return try await self.requireAPI().attachment(id: attachment.id)
      }, onFailure: handleSchoolFailure)
  }
  private func clearSchoolRecords() {
    attendance.clear()
    calendar.clear()
    schedule.clear()
    profile.clear()
    documents.clear()
    mailbox.clear()
    messageDetail.clear()
    preview.close()
  }
  private func handleSchoolFailure(_ error: Error) {
    guard let error = error as? APIError, error == .sessionInvalid || error == .reconnectRequired
    else { return }
    handle(error)
  }
  private func requireAPI() throws -> APIClient {
    guard let api else { throw APIError.invalidConfiguration }
    return api
  }
  private func loadGradebook(
    period: Int?, version: Int, force: Bool = true, resetPlanner: Bool = true
  ) async throws {
    let result = try await gradebooks.load(
      owner: schoolSessionKey, period: period, force: force,
      fetch: { period, mode in
        try await self.requireAPI().gradebook(period: period, mode: mode)
      })
    guard generation == version else { return }
    apply(result.book, resetPlanner: resetPlanner)
    lastUpdated = result.checkedAt
    lastKeepAlive = Date()
  }
  private func apply(_ result: Gradebook, resetPlanner: Bool = true) {
    gradebook = result
    lastUpdated = Date()
    let next = GPAPlanning.entries(
      for: result.courses, gradeLevel: Int(profile.value?.grade ?? "") ?? 9)
    planner =
      resetPlanner ? next : GPAPlanning.rebase(current: planner, original: plannerSeeds, next: next)
    plannerSeeds = next
  }
  private func handle(_ error: Error) {
    if error is CancellationError { return }
    if let error = error as? APIError {
      if error == .reconnectRequired { needsReconnect = true }
      if error == .sessionInvalid {
        identity = nil
        gradebook = nil
        planner = []
        plannerSeeds = []
        lastUpdated = nil
        gradebooks.clear()
        clearSchoolRecords()
        phase = .signedOut
      }
    }
    message = friendly(error)
  }
  private func friendly(_ error: Error) -> String {
    (error as? APIError)?.errorDescription ?? "The request could not be completed. Try again."
  }
}
