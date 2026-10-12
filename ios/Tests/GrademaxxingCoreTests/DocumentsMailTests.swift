import Foundation
import GrademaxxingCore

func resourceFixture(_ name: String) throws -> Data {
  try Data(contentsOf: require(Bundle.module.url(forResource: name, withExtension: "json")))
}
enum DocumentsMailTests {
  static func documentsMatchActualAdapterAndHandleEmptyLists() throws {
    let rows = try DocumentsDecoder.decode(resourceFixture("documents"))
    try expect(rows.count == 1)
    try expect(rows.first?.id == DocumentsMailDemo.documentID)
    try expect(rows.first?.category == "Report")
    try expect(try DocumentsDecoder.decode(Data("{\"StudentDocumentDatas\":{}}".utf8)).isEmpty)
  }
  static func mailboxPreservesFolderAndUnreadFlags() throws {
    let box = try MailDecoder.mailbox(resourceFixture("mailbox"))
    try expect(box.folders.map(\.name) == ["Inbox", "Sent"])
    try expect(box.messages.first?.messageID == DocumentsMailDemo.messageID)
    try expect(box.messages.first?.folderKey == box.folders.first?.id)
    try expect(box.messages.first?.isRead == false)
    let detail = try MailDecoder.message(
      resourceFixture("message"), id: DocumentsMailDemo.messageID, isSystem: false)
    try expect(detail.attachments.first?.id == DocumentsMailDemo.attachmentID)
    try expect(detail.body.text.contains("guide & checklist"))
    try expect(detail.body.links.first?.host == "example.edu")
    try expect(box.messages.first?.isRead == false)
  }
  static func invalidMessageIDsStayVisibleButCannotBeOpened() throws {
    let data = Data(
      "{\"folders\":[],\"messages\":[{\"messagePersonId\":\"synthetic-invalid\",\"mailRead\":\"false\",\"isSystemMessage\":\"false\"}]}"
        .utf8)
    let message = try require(MailDecoder.mailbox(data).messages.first)
    try expect(message.messageID == nil)
    try expect(!message.isRead && !message.isSystem)
  }
  static func nativeTextRemovesActiveHTMLAndExposesOnlySafeLinks() throws {
    let body = try MessageText.render(
      """
      <style>secret-style</style><p>Hello &amp; welcome &#x1F600;.</p>
      <script>synthetic-danger()</script><iframe src="https://tracker.example">remote-frame</iframe>
      <a href="https://example.edu/a?x=1&amp;y=2">Safe project</a>
      <a href="javascript:synthetic()">Unsafe link</a><a href="https://user:pass@example.edu">Credentials</a>
      <img src="https://tracker.example/image.png"><ul><li>First step</li></ul>
      """)
    try expect(body.text.contains("Hello & welcome 😀."))
    try expect(
      !body.text.contains("synthetic-danger") && !body.text.contains("remote-frame")
        && !body.text.contains("secret-style"))
    try expect(body.text.contains("• First step"))
    try expect(body.links.count == 1)
    try expect(body.links.first?.absoluteString == "https://example.edu/a?x=1&y=2")
    try expect(body.hasImages)
  }
  static func bodyBoundsAndUnclosedScriptsAreHandled() throws {
    let text = try MessageText.render(
      "A &quot;quote&quot; &#39;apostrophe&#39;<script>truncated-script")
    try expect(text.text == "A \"quote\" 'apostrophe'")
    let long = try MessageText.render(String(repeating: "a", count: 100_100))
    try expect(long.wasShortened && long.text.count == 100_001)
    try expectThrows(APIError.invalidResponse) {
      try MessageText.render(String(repeating: "a", count: 2 * 1_024 * 1_024 + 1))
    }
  }
  static func syntheticPDFValidatesAndUntrustedFilenameIsContained() throws {
    let file = try DocumentsMailDemo.file()
    try expect(file.kind == .pdf)
    let renamed = try PreviewFileDecoder.validate(
      base64: file.data.base64EncodedString(), name: "../private\\folder/Unsafe\u{0}.exe",
      mime: "application/octet-stream")
    try expect(renamed.name == "Unsafe.pdf")
    try expectThrows(APIError.invalidFile) {
      try PreviewFileDecoder.validate(
        base64: file.data.base64EncodedString(), name: "File.pdf", mime: "text/html")
    }
  }
  static func base64AndActiveContentRejection() throws {
    try expectThrows(APIError.invalidFile) {
      try PreviewFileDecoder.validate(
        base64: "not-base64!", name: "File.pdf", mime: "application/pdf")
    }
    try expectThrows(APIError.invalidFile) {
      try PreviewFileDecoder.validate(base64: "", name: "File.pdf", mime: "application/pdf")
    }
    let html = Data("<html><script>synthetic()</script></html>".utf8).base64EncodedString()
    try expectThrows(APIError.unsupportedFile) {
      try PreviewFileDecoder.validate(base64: html, name: "File.pdf", mime: "application/pdf")
    }
    let oversized = String(
      repeating: "A", count: ((PreviewFileDecoder.maximumDecodedBytes + 2) / 3) * 4 + 4)
    try expectThrows(APIError.invalidFile) {
      try PreviewFileDecoder.validate(base64: oversized, name: "File.pdf", mime: "application/pdf")
    }
  }
  static func pngSignatureAndDimensionsAreValidated() throws {
    let encoded =
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aFO0AAAAASUVORK5CYII="
    let file = try PreviewFileDecoder.validate(
      base64: encoded, name: "Pixel.png", mime: "image/png")
    try expect(file.kind == .png && file.name == "Pixel.png")
    try expectThrows(APIError.invalidFile) {
      try PreviewFileDecoder.validate(base64: encoded, name: "Pixel.jpg", mime: "image/jpeg")
    }
  }
}

private actor SuspendedFile {
  private var started = false
  private var watcher: CheckedContinuation<Void, Never>?
  private var pending: CheckedContinuation<PreviewFile, Never>?
  func fetch() async -> PreviewFile {
    started = true
    watcher?.resume()
    watcher = nil
    return await withCheckedContinuation { pending = $0 }
  }
  func waitForStart() async { if !started { await withCheckedContinuation { watcher = $0 } } }
  func complete(_ file: PreviewFile) {
    pending?.resume(returning: file)
    pending = nil
  }
}

@MainActor enum PreviewLifecycleTests {
  static func cleanupFailureRemainsVisibleAndDoesNotFollowSymlinks() async throws {
    let root = directory()
    let backup = directory()
    let target = directory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: backup)
      try? FileManager.default.removeItem(at: target)
    }
    let session = PreviewSession(storage: try TemporaryPreviewFiles(directory: root))
    await session.open(
      name: "Synthetic", fetch: { try DocumentsMailDemo.file() }, onFailure: { _ in })
    try expect(session.url != nil)
    try FileManager.default.moveItem(at: root, to: backup)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: root, withDestinationURL: target)
    session.close()
    try expect(session.url == nil && !session.isPresented)
    try expect(session.error == APIError.fileStorage.errorDescription)
    try expect(FileManager.default.fileExists(atPath: target.path))
    try expect(!(try FileManager.default.contentsOfDirectory(atPath: backup.path)).isEmpty)
  }
  private static func directory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
      "grademaxxing-preview-" + UUID().uuidString, isDirectory: true)
  }
  static func previewCopiesArePrivateAndReplacedCopiesAreRemoved() throws {
    let root = directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = try TemporaryPreviewFiles(directory: root)
    let file = try DocumentsMailDemo.file()
    let first = try storage.write(file)
    let attributes = try FileManager.default.attributesOfItem(atPath: first.path)
    try expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    let second = try storage.write(file)
    try expect(!FileManager.default.fileExists(atPath: first.path))
    try expect(FileManager.default.fileExists(atPath: second.path))
    try storage.clear()
    try expect(!FileManager.default.fileExists(atPath: second.path))
  }
  static func relaunchPurgesOrphanedPreviewFiles() throws {
    let root = directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = try TemporaryPreviewFiles(directory: root)
    let url = try storage.write(DocumentsMailDemo.file())
    _ = try TemporaryPreviewFiles(directory: root)
    try expect(!FileManager.default.fileExists(atPath: url.path))
  }
  static func arbitraryDirectoriesAndSymlinkRootsAreRejected() throws {
    try expectThrows(APIError.fileStorage) {
      try TemporaryPreviewFiles(directory: FileManager.default.temporaryDirectory)
    }
    let root = directory()
    let target = directory()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: target)
    }
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: root, withDestinationURL: target)
    try expectThrows(APIError.fileStorage) { try TemporaryPreviewFiles(directory: root) }
    try expect(FileManager.default.fileExists(atPath: target.path))
  }
  static func dismissedDownloadCannotCreateAPreviewCopy() async throws {
    let root = directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = try TemporaryPreviewFiles(directory: root)
    let session = PreviewSession(storage: storage)
    let suspended = SuspendedFile()
    let task = Task {
      await session.open(name: "Synthetic", fetch: { await suspended.fetch() }, onFailure: { _ in })
    }
    await suspended.waitForStart()
    session.close()
    await suspended.complete(try DocumentsMailDemo.file())
    await task.value
    try expect(session.url == nil && !session.isPresented && !session.isLoading)
    try expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
  }
  static func closeDeletesAnOpenedPreviewAndDropsItsName() async throws {
    let root = directory()
    defer { try? FileManager.default.removeItem(at: root) }
    let session = PreviewSession(storage: try TemporaryPreviewFiles(directory: root))
    await session.open(
      name: "Synthetic", fetch: { try DocumentsMailDemo.file() }, onFailure: { _ in })
    let url = try require(session.url)
    try expect(session.isPresented && session.kind == .pdf)
    session.close()
    try expect(!FileManager.default.fileExists(atPath: url.path))
    try expect(session.name == "Document" && session.url == nil)
  }
}

private final class BoundedFixtureProtocol: URLProtocol, @unchecked Sendable {
  override class func canInit(with request: URLRequest) -> Bool {
    request.url?.host == "bounded-fixture.example"
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let count = Int(request.value(forHTTPHeaderField: "X-Synthetic-Size") ?? "8") ?? 8
    let headers =
      request.value(forHTTPHeaderField: "X-Synthetic-Length") == "known"
      ? ["Content-Length": String(count)] : [:]
    let response = HTTPURLResponse(
      url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(repeating: 65, count: count))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
enum BoundedTransportTests {
  static func streamedResponsesHonorCapsWithoutContentLength() async throws {
    let transport = URLSessionTransport(protocolClasses: [BoundedFixtureProtocol.self])
    var request = URLRequest(url: URL(string: "https://bounded-fixture.example")!)
    request.setValue("64", forHTTPHeaderField: "X-Synthetic-Size")
    try await expectThrows(APIError.responseTooLarge) {
      try await transport.send(request, maximumBytes: 8)
    }
  }
  static func advertisedOversizeResponsesAreRejected() async throws {
    let transport = URLSessionTransport(protocolClasses: [BoundedFixtureProtocol.self])
    var request = URLRequest(url: URL(string: "https://bounded-fixture.example")!)
    request.setValue("64", forHTTPHeaderField: "X-Synthetic-Size")
    request.setValue("known", forHTTPHeaderField: "X-Synthetic-Length")
    try await expectThrows(APIError.responseTooLarge) {
      try await transport.send(request, maximumBytes: 8)
    }
  }
  static func exactResponseBoundarySucceeds() async throws {
    let transport = URLSessionTransport(protocolClasses: [BoundedFixtureProtocol.self])
    let result = try await transport.send(
      URLRequest(url: URL(string: "https://bounded-fixture.example")!), maximumBytes: 8)
    try expect(result.data.count == 8 && result.status == 200)
  }
}
