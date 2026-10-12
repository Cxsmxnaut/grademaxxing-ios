import Foundation

public struct ServiceConfiguration: Sendable, Equatable {
  public let origin: URL
  public init(origin: URL) throws {
    guard origin.scheme?.lowercased() == "https", origin.host != nil,
      origin.user == nil, origin.password == nil, origin.query == nil, origin.fragment == nil,
      origin.path.isEmpty || origin.path == "/"
    else { throw APIError.invalidConfiguration }
    self.origin = origin
  }
}

public struct SessionIdentity: Codable, Equatable, Sendable {
  public let username: String
  public let domain: String
  public let sessionId: String
  public init(username: String, domain: String, sessionId: String) {
    self.username = username
    self.domain = domain
    self.sessionId = sessionId
  }
}

public struct SavedSession: Codable, Equatable, Sendable {
  public let origin: String
  public let identity: SessionIdentity
  public let cookie: String
  public let expires: Date
  public init(origin: String, identity: SessionIdentity, cookie: String, expires: Date) {
    self.origin = origin
    self.identity = identity
    self.cookie = cookie
    self.expires = expires
  }
}

public protocol SessionVault: Sendable {
  func load() async throws -> SavedSession?
  func save(_ session: SavedSession) async throws
  func clear() async throws
}

public actor MemorySessionVault: SessionVault {
  private var value: SavedSession?
  public init(_ value: SavedSession? = nil) { self.value = value }
  public func load() -> SavedSession? { value }
  public func save(_ session: SavedSession) { value = session }
  public func clear() { value = nil }
}

public struct HTTPResult: Sendable {
  public let data: Data
  public let status: Int
  public let headers: [String: String]
  public init(data: Data, status: Int, headers: [String: String] = [:]) {
    self.data = data
    self.status = status
    self.headers = Dictionary(
      headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
  }
}

public protocol HTTPTransport: Sendable {
  func send(_ request: URLRequest) async throws -> HTTPResult
  func send(_ request: URLRequest, maximumBytes: Int) async throws -> HTTPResult
}
extension HTTPTransport {
  public func send(_ request: URLRequest, maximumBytes: Int) async throws -> HTTPResult {
    let result = try await send(request)
    guard result.data.count <= maximumBytes else { throw APIError.responseTooLarge }
    return result
  }
}

/// Ephemeral networking: no shared browser cookies, record cache, disk persistence, or redirects.
public final class URLSessionTransport: HTTPTransport, Sendable {
  private let session: URLSession
  public init(protocolClasses: [AnyClass] = []) {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false
    config.httpCookieStorage = nil
    config.urlCache = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    config.timeoutIntervalForRequest = 120
    config.timeoutIntervalForResource = 180
    if !protocolClasses.isEmpty { config.protocolClasses = protocolClasses }
    session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
  }
  public func send(_ request: URLRequest) async throws -> HTTPResult {
    try await send(request, maximumBytes: 20 * 1_024 * 1_024)
  }
  public func send(_ request: URLRequest, maximumBytes: Int) async throws -> HTTPResult {
    guard maximumBytes > 0 else { throw APIError.invalidInput }
    let (bytes, response) = try await session.bytes(for: request)
    defer { bytes.task.cancel() }
    guard let response = response as? HTTPURLResponse else { throw APIError.invalidResponse }
    guard response.expectedContentLength <= Int64(maximumBytes) else {
      throw APIError.responseTooLarge
    }
    let data = try await withTaskCancellationHandler {
      var data = Data()
      var chunk: [UInt8] = []
      chunk.reserveCapacity(65_536)
      for try await byte in bytes {
        guard data.count + chunk.count < maximumBytes else { throw APIError.responseTooLarge }
        chunk.append(byte)
        if chunk.count == 65_536 {
          data.append(contentsOf: chunk)
          chunk.removeAll(keepingCapacity: true)
        }
      }
      data.append(contentsOf: chunk)
      return data
    } onCancel: {
      bytes.task.cancel()
    }
    let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
      if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
    }
    return HTTPResult(data: data, status: response.statusCode, headers: headers)
  }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

/// A continuation gate keeps entire operations serialized across actor suspension points.
/// An actor alone would allow two requests to interleave while awaiting URLSession.
public actor APIClient {
  private let configuration: ServiceConfiguration
  private let transport: any HTTPTransport
  private let vault: any SessionVault
  private var stored: SavedSession?
  private var sessionGeneration = 0
  private var busy = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  public init(
    configuration: ServiceConfiguration, transport: any HTTPTransport = URLSessionTransport(),
    vault: any SessionVault
  ) {
    self.configuration = configuration
    self.transport = transport
    self.vault = vault
  }

  public func login(domain: String, username: String, password: String) async throws
    -> SessionIdentity
  {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    let version = sessionGeneration
    let domain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
    let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let portal = URL(string: domain), portal.scheme?.lowercased() == "https",
      portal.host != nil,
      portal.user == nil, portal.password == nil, !username.isEmpty, username.count <= 254,
      !password.isEmpty, password.count <= 1_024, domain.count <= 253
    else { throw APIError.invalidInput }
    struct Credentials: Encodable {
      let domain: String
      let username: String
      let password: String
    }
    let body = try JSONEncoder().encode(
      Credentials(domain: domain, username: username, password: password))
    let result = try await perform(
      path: "/api/session", method: "POST", body: body, authenticated: false)
    guard let identity = try? JSONDecoder().decode(SessionIdentity.self, from: result.data),
      !identity.sessionId.isEmpty,
      let cookie = sessionCookie(in: result)
    else { throw APIError.invalidResponse }
    let saved = SavedSession(
      origin: configuration.origin.absoluteString, identity: identity, cookie: cookie.value,
      expires: cookie.expiresDate ?? Date().addingTimeInterval(12 * 3_600))
    try await persist(saved, version: version)
    return identity
  }

  public func restore() async throws -> SessionIdentity? {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    let version = sessionGeneration
    let loaded: SavedSession?
    do { loaded = try await vault.load() } catch { throw APIError.secureStorage }
    guard version == sessionGeneration else { throw CancellationError() }
    stored = loaded
    guard let saved = stored else { return nil }
    guard saved.origin == configuration.origin.absoluteString, saved.expires > Date() else {
      try await clearSession()
      return nil
    }
    let result = try await perform(path: "/api/session/status")
    struct Status: Decodable { let signedIn: Bool }
    guard let status = try? JSONDecoder().decode(Status.self, from: result.data) else {
      throw APIError.invalidResponse
    }
    guard status.signedIn else {
      try await clearSession()
      return nil
    }
    return stored?.identity
  }

  public func gradebook(period: Int? = nil, mode: GradebookReadMode = .fresh) async throws
    -> Gradebook
  {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    if let period, !(0...999).contains(period) { throw APIError.invalidInput }
    var query = [URLQueryItem(name: mode == .fresh ? "fresh" : "summary", value: "true")]
    if let period { query.append(URLQueryItem(name: "reportPeriod", value: String(period))) }
    return try GradebookDecoder.decode(
      try await perform(path: "/api/studentvue/gradebook", query: query).data)
  }

  public func keepAlive() async throws {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    _ = try await perform(path: "/api/session/keepalive")
  }

  public func attendance() async throws -> AttendanceBook {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    return try AttendanceDecoder.decode(try await perform(path: "/api/studentvue/attendance").data)
  }

  public func calendar(month: SchoolMonth) async throws -> SchoolCalendar {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    let query = [
      URLQueryItem(name: "month", value: String(month.month)),
      URLQueryItem(name: "year", value: String(month.year)),
    ]
    return try CalendarDecoder.decode(
      try await perform(path: "/api/studentvue/calendar", query: query).data, month: month)
  }

  public func schedule() async throws -> SchoolSchedule {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    return try decodeJSON(try await perform(path: "/api/studentvue/schedule").data)
  }

  public func profile() async throws -> StudentProfile {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    return try decodeJSON(try await perform(path: "/api/studentvue/student-profile").data)
  }

  public func documents() async throws -> [SchoolDocument] {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    return try DocumentsDecoder.decode(try await perform(path: "/api/studentvue/documents").data)
  }
  public func document(id: String) async throws -> PreviewFile {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    guard !id.isEmpty, id.utf8.count <= 4_096 else { throw APIError.invalidInput }
    let result = try await perform(
      path: "/api/studentvue/document", query: [URLQueryItem(name: "id", value: id)],
      maximumBytes: PreviewFileDecoder.maximumResponseBytes)
    return try PreviewFileDecoder.decode(result.data)
  }
  public func mailbox() async throws -> Mailbox {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    return try MailDecoder.mailbox(try await perform(path: "/api/studentvue/mailbox").data)
  }
  public func message(id: String, isSystem: Bool = false) async throws -> ReadableMessage {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    guard UUID(uuidString: id) != nil else { throw APIError.invalidInput }
    let query = [
      URLQueryItem(name: "id", value: id),
      URLQueryItem(name: "system", value: isSystem ? "true" : "false"),
    ]
    return try MailDecoder.message(
      try await perform(path: "/api/studentvue/message", query: query).data, id: id,
      isSystem: isSystem)
  }
  public func attachment(id: String) async throws -> PreviewFile {
    try await acquire()
    defer { release() }
    try Task.checkCancellation()
    guard UUID(uuidString: id) != nil else { throw APIError.invalidInput }
    let result = try await perform(
      path: "/api/studentvue/attachment", query: [URLQueryItem(name: "id", value: id)],
      maximumBytes: PreviewFileDecoder.maximumResponseBytes)
    return try PreviewFileDecoder.decode(result.data, attachment: true)
  }

  /// Local session removal is mandatory even when remote revocation cannot be reached.
  public func logout() async throws {
    let previous = stored
    sessionGeneration += 1
    var clearError: APIError?
    do { try await clearSession() } catch { clearError = .secureStorage }
    // Local deletion happens before waiting for any current StudentVUE request.
    // Older operations cannot persist a rotated or newly authenticated session.
    try await acquire()
    defer { release() }
    if let previous {
      _ = try? await perform(
        path: "/api/session", method: "DELETE", authenticated: false, sessionOverride: previous)
    }
    if let clearError { throw clearError }
  }

  private func perform(
    path: String, method: String = "GET", query: [URLQueryItem] = [], body: Data? = nil,
    authenticated: Bool = true, sessionOverride: SavedSession? = nil,
    maximumBytes: Int = 20 * 1_024 * 1_024
  ) async throws -> HTTPResult {
    let version = sessionGeneration
    if authenticated && stored == nil { throw APIError.sessionInvalid }
    var components = URLComponents(url: configuration.origin, resolvingAgainstBaseURL: false)!
    components.path = path
    components.queryItems = query.isEmpty ? nil : query
    // The backend uses form-style query parsing, where an unescaped '+' means space.
    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(
      of: "+", with: "%2B")
    guard let url = components.url else { throw APIError.invalidConfiguration }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
    if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    if let saved = sessionOverride ?? stored {
      request.setValue("grademaxxing_session=\(saved.cookie)", forHTTPHeaderField: "Cookie")
      request.setValue(saved.identity.sessionId, forHTTPHeaderField: "x-grademaxxing-session")
    }
    let result: HTTPResult
    do {
      result = try await transport.send(request, maximumBytes: maximumBytes)
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch let error as APIError { throw error } catch { throw APIError.network }
    guard version == sessionGeneration else { throw CancellationError() }
    guard (200...299).contains(result.status) else {
      if result.status == 401 {
        if !authenticated { throw APIError.authenticationFailed }
        struct Failure: Decodable { let code: String? }
        let code = (try? JSONDecoder().decode(Failure.self, from: result.data))?.code
        if code == "UPSTREAM_SESSION_EXPIRED" { throw APIError.reconnectRequired }
        try await clearSession()
        throw APIError.sessionInvalid
      }
      if result.status == 429 { throw APIError.rateLimited }
      if result.status >= 500 { throw APIError.unavailable }
      throw APIError.http(result.status)
    }
    if authenticated, method != "DELETE", let saved = stored, let cookie = sessionCookie(in: result)
    {
      let updated = SavedSession(
        origin: saved.origin, identity: saved.identity, cookie: cookie.value,
        expires: cookie.expiresDate ?? saved.expires)
      try await persist(updated, version: version)
    }
    return result
  }

  private func sessionCookie(in result: HTTPResult) -> HTTPCookie? {
    guard let header = result.headers["set-cookie"] else { return nil }
    return HTTPCookie.cookies(
      withResponseHeaderFields: ["Set-Cookie": header], for: configuration.origin
    ).first {
      $0.name == "grademaxxing_session" && $0.path == "/" && !$0.value.isEmpty
        && $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
          == configuration.origin.host?.lowercased()
        && $0.isSecure && ($0.expiresDate ?? .distantFuture) > Date()
    }
  }
  private func clearSession() async throws {
    stored = nil
    do { try await vault.clear() } catch { throw APIError.secureStorage }
  }
  private func persist(_ session: SavedSession, version: Int) async throws {
    guard version == sessionGeneration else { throw CancellationError() }
    do { try await vault.save(session) } catch { throw APIError.secureStorage }
    guard version == sessionGeneration else {
      // The vault may have finished saving after sign-out's deletion. The request
      // gate still excludes any newer login, so clearing that late save is safe.
      do { try await vault.clear() } catch { throw APIError.secureStorage }
      throw CancellationError()
    }
    stored = session
  }
  private func decodeJSON<T: Decodable>(_ data: Data) throws -> T {
    guard let value = try? JSONDecoder().decode(T.self, from: data) else {
      throw APIError.invalidResponse
    }
    return value
  }
  private func acquire() async throws {
    let version = sessionGeneration
    if !busy {
      busy = true
    } else {
      await withCheckedContinuation { waiters.append($0) }
    }
    guard version == sessionGeneration else {
      release()
      throw CancellationError()
    }
  }
  private func release() {
    if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
  }
}
