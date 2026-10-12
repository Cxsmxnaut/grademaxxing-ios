import CoreGraphics
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

public struct PreviewFile: Sendable, Equatable {
  public enum Kind: String, Sendable { case pdf, png, jpeg, gif, webp }
  public let data: Data
  public let name: String
  public let kind: Kind
}
public enum PreviewFileDecoder {
  public static let maximumDecodedBytes = 25 * 1_024 * 1_024
  public static let maximumResponseBytes = 36 * 1_024 * 1_024
  public static func decode(_ data: Data, attachment: Bool = false) throws -> PreviewFile {
    guard data.count <= maximumResponseBytes,
      let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let encoded = root["Base64Code"] as? String,
      let name = root[attachment ? "_DocumentName" : "_FileName"] as? String,
      let mime = root[attachment ? "_MimeType" : "_DocType"] as? String
    else { throw APIError.invalidResponse }
    return try validate(base64: encoded, name: name, mime: mime)
  }
  public static func validate(base64: String, name: String, mime: String) throws -> PreviewFile {
    guard !base64.isEmpty, base64.utf8.count <= ((maximumDecodedBytes + 2) / 3) * 4,
      let bytes = Data(base64Encoded: base64), !bytes.isEmpty, bytes.count <= maximumDecodedBytes
    else { throw APIError.invalidFile }
    let declared =
      mime.split(separator: ";", maxSplits: 1).first?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ).lowercased() ?? ""
    let kind: PreviewFile.Kind
    let detected: String
    if bytes.starts(with: Data("%PDF-".utf8)) {
      guard let provider = CGDataProvider(data: bytes as CFData),
        let document = CGPDFDocument(provider), document.numberOfPages > 0
      else { throw APIError.invalidFile }
      kind = .pdf
      detected = "application/pdf"
    } else if let source = CGImageSourceCreateWithData(bytes as CFData, nil),
      let type = CGImageSourceGetType(source)
    {
      let mimeType = UTType(type as String)?.preferredMIMEType
      switch mimeType {
      case "image/png": kind = .png
      case "image/jpeg": kind = .jpeg
      case "image/gif": kind = .gif
      case "image/webp": kind = .webp
      default: throw APIError.unsupportedFile
      }
      detected = mimeType!
      let count = CGImageSourceGetCount(source)
      guard (1...200).contains(count), CGImageSourceGetStatus(source) == .statusComplete else {
        throw APIError.invalidFile
      }
      var pixels = 0
      for index in 0..<count {
        guard
          let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
            as? [String: Any],
          let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
          let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
          (1...10_000).contains(width), (1...10_000).contains(height)
        else { throw APIError.invalidFile }
        pixels += width * height
        guard pixels <= 40_000_000 else { throw APIError.invalidFile }
      }
    } else {
      throw APIError.unsupportedFile
    }
    guard
      declared == detected || declared == "application/octet-stream"
        || (declared == "image/jpg" && kind == .jpeg)
    else { throw APIError.invalidFile }
    let safeName = safeName(name, kind: kind)
    return PreviewFile(data: bytes, name: safeName, kind: kind)
  }
  private static func safeName(_ name: String, kind: PreviewFile.Kind) -> String {
    let basename =
      name.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init)
      ?? "Document"
    let cleaned = basename.unicodeScalars.filter {
      !CharacterSet.controlCharacters.contains($0) && $0.value != 0x202E
    }
    var stem = (String(String.UnicodeScalarView(cleaned)) as NSString).deletingPathExtension
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if stem.isEmpty || stem == "." || stem == ".." { stem = "Document" }
    return String(stem.prefix(100)) + "." + (kind == .jpeg ? "jpg" : kind.rawValue)
  }
}

/// Owns only app-created preview copies, never originals or arbitrary user paths.
@MainActor public final class TemporaryPreviewFiles {
  public let directory: URL
  public init(directory: URL? = nil) throws {
    self.directory =
      directory
      ?? FileManager.default.temporaryDirectory.appendingPathComponent(
        "grademaxxing-native-previews", isDirectory: true)
    let temporaryRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
      .standardizedFileURL
    guard self.directory.isFileURL,
      self.directory.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
        == temporaryRoot,
      self.directory.lastPathComponent == "grademaxxing-native-previews"
        || self.directory.lastPathComponent.hasPrefix("grademaxxing-preview-"),
      (try? FileManager.default.destinationOfSymbolicLink(atPath: self.directory.path)) == nil
    else { throw APIError.fileStorage }
    do {
      try FileManager.default.createDirectory(
        at: self.directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: self.directory.path)
      try clear()
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var root = self.directory
      try root.setResourceValues(values)
    } catch { throw APIError.fileStorage }
  }
  public func write(_ file: PreviewFile) throws -> URL {
    do {
      try clear()
      let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
      try FileManager.default.createDirectory(
        at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
      let url = folder.appendingPathComponent(file.name)
      #if os(iOS)
        try file.data.write(to: url, options: [.atomic, .completeFileProtection])
      #else
        try file.data.write(to: url, options: .atomic)
      #endif
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      var storedURL = url
      try storedURL.setResourceValues(values)
      return url
    } catch {
      try? clear()
      throw APIError.fileStorage
    }
  }
  public func clear() throws {
    do {
      guard (try? FileManager.default.destinationOfSymbolicLink(atPath: directory.path)) == nil
      else { throw APIError.fileStorage }
      for url in try FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
      {
        try FileManager.default.removeItem(at: url)
      }
    } catch { throw APIError.fileStorage }
  }
}

@MainActor @Observable
public final class PreviewSession {
  public var isPresented = false
  public var isLoading = false
  public var url: URL?
  public var name = "Document"
  public var kind: PreviewFile.Kind?
  public var error: String?
  @ObservationIgnored private var generation = 0
  @ObservationIgnored private let storage: TemporaryPreviewFiles?
  public init(storage: TemporaryPreviewFiles? = nil) {
    self.storage = storage ?? (try? TemporaryPreviewFiles())
  }
  public func open(name: String, fetch: () async throws -> PreviewFile, onFailure: (Error) -> Void)
    async
  {
    close()
    let version = generation
    self.name = name
    isPresented = true
    isLoading = true
    error = nil
    defer { if generation == version { isLoading = false } }
    do {
      let file = try await fetch()
      try Task.checkCancellation()
      guard generation == version else { return }
      guard let storage else { throw APIError.fileStorage }
      url = try storage.write(file)
      kind = file.kind
      self.name = file.name
    } catch {
      guard generation == version, !(error is CancellationError) else { return }
      self.error =
        (error as? APIError)?.errorDescription ?? "The file could not be opened. Try again."
      onFailure(error)
    }
  }
  public func close() {
    generation += 1
    url = nil
    kind = nil
    isLoading = false
    isPresented = false
    name = "Document"
    error = nil
    do { try storage?.clear() } catch { self.error = APIError.fileStorage.errorDescription }
  }
}
