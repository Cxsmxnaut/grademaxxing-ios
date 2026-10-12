import Foundation
import GrademaxxingCore

private let origin = URL(string: "https://synthetic-service.example")!
private let identity = SessionIdentity(
  username: "synthetic-user", domain: "https://synthetic-district.example",
  sessionId: "synthetic-session")
private func savedSession() -> SavedSession {
  SavedSession(
    origin: origin.absoluteString, identity: identity, cookie: "synthetic-cookie",
    expires: .distantFuture)
}
private func json(_ string: String, status: Int = 200, cookie: String? = nil) -> HTTPResult {
  HTTPResult(
    data: Data(string.utf8), status: status,
    headers: cookie.map {
      ["Set-Cookie": "grademaxxing_session=\($0); Path=/; Secure; HttpOnly; Max-Age=43200"]
    } ?? [:])
}
private func loginReply() throws -> HTTPResult {
  HTTPResult(
    data: try JSONEncoder().encode(identity), status: 200,
    headers: [
      "Set-Cookie": "grademaxxing_session=synthetic-cookie; Path=/; Secure; HttpOnly; Max-Age=43200"
    ])
}
private actor ScriptedTransport: HTTPTransport {
  var replies: [HTTPResult]
  var requests: [URLRequest] = []
  var active = 0
  var maximumActive = 0
  let delay: Bool
  init(_ replies: [HTTPResult], delay: Bool = false) {
    self.replies = replies
    self.delay = delay
  }
  func send(_ request: URLRequest) async throws -> HTTPResult {
    requests.append(request)
    active += 1
    maximumActive = max(maximumActive, active)
    defer { active -= 1 }
    guard !replies.isEmpty else { throw APIError.network }
    let reply = replies.removeFirst()
    if delay { try await Task.sleep(for: .milliseconds(30)) }
    return reply
  }
}

private actor SignaledVault: SessionVault {
  private var saved: SavedSession?
  private var cleared = false
  private var watcher: CheckedContinuation<Void, Never>?
  func load() -> SavedSession? { saved }
  func save(_ value: SavedSession) { saved = value }
  func clear() {
    saved = nil
    cleared = true
    watcher?.resume()
    watcher = nil
  }
  func waitForClear() async { if !cleared { await withCheckedContinuation { watcher = $0 } } }
}

private actor GatedTransport: HTTPTransport {
  private let path: String
  private let reply: HTTPResult
  private var started = false
  private var watcher: CheckedContinuation<Void, Never>?
  private var pending: CheckedContinuation<HTTPResult, Never>?
  init(path: String, reply: HTTPResult) {
    self.path = path
    self.reply = reply
  }
  func send(_ request: URLRequest) async throws -> HTTPResult {
    if request.url?.path == path && request.httpMethod != "DELETE" {
      started = true
      watcher?.resume()
      watcher = nil
      return await withCheckedContinuation { pending = $0 }
    }
    if request.httpMethod == "POST" { return try loginReply() }
    return HTTPResult(data: Data(), status: 204)
  }
  func waitForStart() async { if !started { await withCheckedContinuation { watcher = $0 } } }
  func complete() {
    pending?.resume(returning: reply)
    pending = nil
  }
}
private func client(
  _ transport: ScriptedTransport, vault: MemorySessionVault = MemorySessionVault()
) throws -> APIClient {
  APIClient(
    configuration: try ServiceConfiguration(origin: origin), transport: transport, vault: vault)
}

enum APITests {
  static func summaryReadHasNoFreshOverride() async throws {
    let transport = ScriptedTransport([
      try loginReply(), HTTPResult(data: try contractFixture(), status: 200),
    ])
    let api = try client(transport)
    _ = try await api.login(
      domain: identity.domain, username: identity.username, password: "synthetic-password")
    _ = try await api.gradebook(period: 2, mode: .summary)
    let request = try require(await transport.requests.last)
    try expect(request.url?.query?.contains("summary=true") == true)
    try expect(request.url?.query?.contains("fresh=") == false)
  }
  static func documentsAndMailUseReadOnlyRoutesAndEncodedIdentifiers() async throws {
    let file = try DocumentsMailDemo.file()
    let document = try JSONSerialization.data(withJSONObject: [
      "Base64Code": file.data.base64EncodedString(), "_FileName": "Synthetic.pdf",
      "_DocType": "application/pdf",
    ])
    let attachment = try JSONSerialization.data(withJSONObject: [
      "Base64Code": file.data.base64EncodedString(), "_DocumentName": "Synthetic.pdf",
      "_MimeType": "application/pdf",
    ])
    let transport = ScriptedTransport([
      try loginReply(), HTTPResult(data: try resourceFixture("documents"), status: 200),
      HTTPResult(data: document, status: 200),
      HTTPResult(data: try resourceFixture("mailbox"), status: 200),
      HTTPResult(data: try resourceFixture("message"), status: 200),
      HTTPResult(data: attachment, status: 200),
    ])
    let api = try client(transport)
    _ = try await api.login(
      domain: identity.domain, username: identity.username, password: "synthetic-password")
    _ = try await api.documents()
    _ = try await api.document(id: "synthetic+opaque/=")
    _ = try await api.mailbox()
    _ = try await api.message(id: DocumentsMailDemo.messageID, isSystem: true)
    _ = try await api.attachment(id: DocumentsMailDemo.attachmentID)
    let requests = await transport.requests
    try expect(requests.dropFirst().allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    try expect(
      requests.dropFirst().map { $0.url?.path } == [
        "/api/studentvue/documents", "/api/studentvue/document", "/api/studentvue/mailbox",
        "/api/studentvue/message", "/api/studentvue/attachment",
      ])
    try expect(requests[2].url?.query?.contains("%2B") == true)
    let id = URLComponents(url: requests[2].url!, resolvingAgainstBaseURL: false)?.queryItems?
      .first?.value
    try expect(id == "synthetic+opaque/=")
    try expect(requests[4].url?.query?.contains("system=true") == true)
    try expect(
      requests.dropFirst().allSatisfy {
        $0.value(forHTTPHeaderField: "x-grademaxxing-session") == identity.sessionId
      })
  }
  static func malformedMessageAndAttachmentIDsNeverReachTheTransport() async throws {
    let transport = ScriptedTransport([try loginReply()])
    let api = try client(transport)
    _ = try await api.login(
      domain: identity.domain, username: identity.username, password: "synthetic-password")
    try await expectThrows(APIError.invalidInput) { try await api.message(id: "invalid") }
    try await expectThrows(APIError.invalidInput) { try await api.attachment(id: "invalid") }
    try expect(await transport.requests.count == 1)
  }
  static func logoutDeletesSessionBeforeAnInFlightReadFinishes() async throws {
    let vault = SignaledVault()
    let transport = GatedTransport(
      path: "/api/studentvue/gradebook",
      reply: HTTPResult(
        data: try contractFixture(), status: 200,
        headers: [
          "Set-Cookie":
            "grademaxxing_session=synthetic-late-rotation; Path=/; Secure; HttpOnly; Max-Age=43200"
        ]))
    let api = APIClient(
      configuration: try ServiceConfiguration(origin: origin), transport: transport, vault: vault)
    _ = try await api.login(
      domain: identity.domain, username: identity.username, password: "synthetic-password")
    let read = Task { try await api.gradebook() }
    await transport.waitForStart()
    let logout = Task { try await api.logout() }
    await vault.waitForClear()
    try expect(await vault.load() == nil)
    await transport.complete()
    do {
      _ = try await read.value
      throw CheckFailure(description: "Old read should be invalidated")
    } catch is CancellationError {}
    try await logout.value
    try expect(await vault.load() == nil)
  }
  static func aLateLoginCannotRestoreSessionAfterLogout() async throws {
    let vault = SignaledVault()
    let transport = GatedTransport(path: "/api/session", reply: try loginReply())
    let api = APIClient(
      configuration: try ServiceConfiguration(origin: origin), transport: transport, vault: vault)
    let login = Task {
      try await api.login(
        domain: identity.domain, username: identity.username, password: "synthetic-password")
    }
    await transport.waitForStart()
    let logout = Task { try await api.logout() }
    await vault.waitForClear()
    await transport.complete()
    do {
      _ = try await login.value
      throw CheckFailure(description: "Old login should be invalidated")
    } catch is CancellationError {}
    try await logout.value
    try expect(await vault.load() == nil)
  }
  static func schoolResourcesUseAuthenticatedReadOnlyRoutes() async throws {
    let calendar = Data(
      "{\"startDate\":\"2026-10-01\",\"endDate\":\"2026-10-31\",\"events\":[]}".utf8)
    let schedule = Data("{\"date\":\"2026-10-09\",\"classes\":[]}".utf8)
    let profile = Data(
      "{\"name\":\"Synthetic Student\",\"permId\":\"SYNTHETIC\",\"grade\":\"11\",\"fields\":{}}"
        .utf8)
    let transport = ScriptedTransport([
      try loginReply(), HTTPResult(data: try attendanceFixture(), status: 200),
      HTTPResult(data: calendar, status: 200), HTTPResult(data: schedule, status: 200),
      HTTPResult(data: profile, status: 200),
    ])
    let api = try client(transport)
    _ = try await api.login(
      domain: identity.domain, username: identity.username, password: "synthetic-password")
    try expect(try await api.attendance().records.count == 3)
    try expect(
      try await api.calendar(month: require(SchoolMonth(year: 2026, month: 10))).events.isEmpty)
    try expect(try await api.schedule().classes.isEmpty)
    try expect(try await api.profile().grade == "11")
    let requests = await transport.requests
    try expect(requests.dropFirst().map(\.httpMethod) == ["GET", "GET", "GET", "GET"])
    try expect(
      requests.dropFirst().map { $0.url?.path } == [
        "/api/studentvue/attendance", "/api/studentvue/calendar", "/api/studentvue/schedule",
        "/api/studentvue/student-profile",
      ])
    try expect(
      requests.dropFirst().allSatisfy {
        $0.value(forHTTPHeaderField: "x-grademaxxing-session") == identity.sessionId
      })
    let query = URLComponents(url: requests[2].url!, resolvingAgainstBaseURL: false)?.queryItems
    try expect(query?.contains(URLQueryItem(name: "month", value: "10")) == true)
    try expect(query?.contains(URLQueryItem(name: "year", value: "2026")) == true)
  }
  static func loginAndRotatedCookieUseExactBackendHeaders() async throws {
    let transport = ScriptedTransport([
      try loginReply(), json("{\"signedIn\":true}", cookie: "synthetic-rotated"),
      HTTPResult(data: try contractFixture(), status: 200),
    ])
    let vault = MemorySessionVault()
    let api = try client(transport, vault: vault)
    let result = try await api.login(
      domain: identity.domain, username: identity.username, password: "synthetic-password")
    try expect(result == identity)
    try await api.keepAlive()
    _ = try await api.gradebook(period: 2)
    let requests = await transport.requests
    try expect(requests[0].httpMethod == "POST")
    try expect(requests[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
    try expect(
      requests[1].value(forHTTPHeaderField: "x-grademaxxing-session") == identity.sessionId)
    try expect(
      requests[2].value(forHTTPHeaderField: "Cookie") == "grademaxxing_session=synthetic-rotated")
    try expect(requests[2].url?.query?.contains("reportPeriod=2") == true)
    try expect(requests[2].url?.query?.contains("fresh=true") == true)
    let saved = try require(await vault.load())
    try expect(saved.cookie == "synthetic-rotated")
    let persisted = String(decoding: try JSONEncoder().encode(saved), as: UTF8.self)
    try expect(!persisted.contains("synthetic-password"))
  }
  static func restoresAndClearsInvalidSession() async throws {
    let vault = MemorySessionVault(savedSession())
    let transport = ScriptedTransport([json("{\"signedIn\":false}")])
    try expect(try await client(transport, vault: vault).restore() == nil)
    try expect(await vault.load() == nil)
  }
  static func distinguishesDistrictExpiryFromAppExpiry() async throws {
    let vault = MemorySessionVault(savedSession())
    let transport = ScriptedTransport([
      json("{\"signedIn\":true}"),
      json("{\"code\":\"UPSTREAM_SESSION_EXPIRED\"}", status: 401),
      json("{\"message\":\"Synthetic invalid session\"}", status: 401),
    ])
    let api = try client(transport, vault: vault)
    _ = try await api.restore()
    try await expectThrows(APIError.reconnectRequired) { try await api.keepAlive() }
    try expect(await vault.load() != nil)
    try await expectThrows(APIError.sessionInvalid) { try await api.keepAlive() }
    try expect(await vault.load() == nil)
  }
  static func logoutClearsVaultEvenWhenRemoteServiceFails() async throws {
    let vault = MemorySessionVault(savedSession())
    let transport = ScriptedTransport([json("{\"signedIn\":true}"), json("{}", status: 503)])
    let api = try client(transport, vault: vault)
    _ = try await api.restore()
    try await api.logout()
    try expect(await vault.load() == nil)
    try expect(await transport.requests.last?.httpMethod == "DELETE")
    try await expectThrows(APIError.sessionInvalid) { try await api.gradebook() }
  }
  static func concurrentPeriodRequestsStaySerializedAcrossAwaits() async throws {
    let fixture = try contractFixture()
    let transport = ScriptedTransport(
      [
        try loginReply(), HTTPResult(data: fixture, status: 200),
        HTTPResult(data: fixture, status: 200),
      ], delay: true)
    let api = try client(transport)
    _ = try await api.login(
      domain: identity.domain, username: identity.username, password: "synthetic-password")
    async let first = api.gradebook(period: 0)
    async let second = api.gradebook(period: 1)
    _ = try await (first, second)
    try expect(await transport.maximumActive == 1)
  }
  static func doesNotReuseSessionAcrossServiceOrigins() async throws {
    let vault = MemorySessionVault(
      SavedSession(
        origin: "https://other-service.example", identity: identity, cookie: "synthetic",
        expires: .distantFuture))
    let transport = ScriptedTransport([])
    try expect(try await client(transport, vault: vault).restore() == nil)
    try expect(await transport.requests.isEmpty)
    try expect(await vault.load() == nil)
  }
  static func rejectsUnsafeServiceConfiguration(_ value: String) throws {
    try expectThrows(APIError.invalidConfiguration) {
      try ServiceConfiguration(origin: URL(string: value)!)
    }
  }
  static func failedReauthenticationPreservesCurrentSession() async throws {
    let vault = MemorySessionVault(savedSession())
    let transport = ScriptedTransport([json("{\"signedIn\":true}"), json("{}", status: 401)])
    let api = try client(transport, vault: vault)
    _ = try await api.restore()
    try await expectThrows(APIError.authenticationFailed) {
      try await api.login(
        domain: identity.domain, username: identity.username, password: "synthetic-wrong-password")
    }
    try expect(await vault.load() == savedSession())
  }
  static func rejectsRedirectAndDoesNotPersistInsecureCookie() async throws {
    let redirect = ScriptedTransport([json("{}", status: 302)])
    try await expectThrows(APIError.http(302)) {
      try await client(redirect).login(
        domain: identity.domain, username: identity.username, password: "synthetic-password")
    }
    let insecure = ScriptedTransport([
      HTTPResult(
        data: try JSONEncoder().encode(identity), status: 200,
        headers: ["Set-Cookie": "grademaxxing_session=synthetic; Path=/"])
    ])
    let vault = MemorySessionVault()
    try await expectThrows(APIError.invalidResponse) {
      try await client(insecure, vault: vault).login(
        domain: identity.domain, username: identity.username, password: "synthetic-password")
    }
    try expect(await vault.load() == nil)
  }
}
