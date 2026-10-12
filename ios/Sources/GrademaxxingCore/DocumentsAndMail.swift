import CoreFoundation
import Foundation

public struct SchoolDocument: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let date: String
  public let category: String
}
public enum DocumentsDecoder {
  public static func decode(_ data: Data) throws -> [SchoolDocument] {
    struct Wire: Decodable {
      struct Rows: Decodable {
        struct Row: Decodable {
          let id: String
          let title: String
          let date: String
          let category: String
          enum CodingKeys: String, CodingKey {
            case id = "_DocumentGU"
            case title = "_DocumentFileName"
            case date = "_DocumentDate"
            case category = "_DocumentType"
          }
        }
        let rows: [Row]?
        enum CodingKeys: String, CodingKey { case rows = "StudentDocumentData" }
      }
      let rows: Rows
      enum CodingKeys: String, CodingKey { case rows = "StudentDocumentDatas" }
    }
    guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else {
      throw APIError.invalidResponse
    }
    let rows = wire.rows.rows ?? []
    guard rows.count <= 10_000, rows.allSatisfy({ !$0.id.isEmpty && $0.id.count <= 4_096 }),
      Set(rows.map(\.id)).count == rows.count
    else { throw APIError.invalidResponse }
    return rows.map {
      SchoolDocument(id: $0.id, title: $0.title, date: $0.date, category: $0.category)
    }
  }
}

public struct MailFolder: Identifiable, Equatable, Sendable {
  public var id: String { "\(type)|\(wireID ?? "")" }
  public let wireID: String?
  public let type: Int
  public let name: String
}
public struct MailAttachment: Identifiable, Equatable, Sendable {
  public let id: String
  public let name: String
}
public struct MailPreview: Identifiable, Equatable, Sendable {
  public let id: String
  public let messageID: String?
  public let subject: String
  public let sender: String
  public let date: String
  public let folderKey: String
  public let folderName: String
  public let isRead: Bool
  public let isSystem: Bool
}
public struct Mailbox: Equatable, Sendable {
  public let folders: [MailFolder]
  public let messages: [MailPreview]
}
public struct ReadableMessage: Equatable, Sendable {
  public let messageID: String
  public let isSystem: Bool
  public let subject: String
  public let sender: String
  public let date: String
  public let body: MessageText
  public let attachments: [MailAttachment]
}

public enum MailDecoder {
  public static func mailbox(_ data: Data) throws -> Mailbox {
    let root = try object(data)
    guard let folders = root["folders"] as? [[String: Any]],
      let messages = root["messages"] as? [[String: Any]],
      folders.count <= 100, messages.count <= 10_000
    else { throw APIError.invalidResponse }
    let normalized = try folders.map { item -> MailFolder in
      guard let type = integer(item["folderType"]), type >= 0 else {
        throw APIError.invalidResponse
      }
      return MailFolder(
        wireID: optionalText(item["folderId"]), type: type, name: text(item["name"]))
    }
    guard Set(normalized.map(\.id)).count == normalized.count else {
      throw APIError.invalidResponse
    }
    let previews = messages.enumerated().map { index, item in
      let rawID =
        text(item["messagePersonId"]).isEmpty
        ? text(item["messageId"]) : text(item["messagePersonId"])
      let key =
        "\(integer(item["portalFolderType"]) ?? 0)|\(optionalText(item["portalFolderId"]) ?? "")"
      return MailPreview(
        id: "\(key)|\(rawID)|\(index)", messageID: UUID(uuidString: rawID) == nil ? nil : rawID,
        subject: text(item["subject"]), sender: sender(item), date: messageDate(item),
        folderKey: key,
        folderName: text(item["portalFolderName"]), isRead: boolean(item["mailRead"]),
        isSystem: boolean(item["isSystemMessage"]))
    }
    return Mailbox(folders: normalized, messages: previews)
  }

  public static func message(_ data: Data, id: String, isSystem: Bool) throws -> ReadableMessage {
    let root = try object(data)
    guard let html = root["messageText"] as? String else { throw APIError.invalidResponse }
    let rows = root["attachments"] as? [[String: Any]] ?? []
    let attachments = rows.compactMap { item -> MailAttachment? in
      let id = text(item["attachmentId"])
      guard UUID(uuidString: id) != nil else { return nil }
      return MailAttachment(id: id, name: text(item["name"]))
    }
    guard Set(attachments.map(\.id)).count == attachments.count else {
      throw APIError.invalidResponse
    }
    return ReadableMessage(
      messageID: id, isSystem: isSystem, subject: text(root["subject"]), sender: sender(root),
      date: messageDate(root), body: try MessageText.render(html), attachments: attachments)
  }

  private static func object(_ data: Data) throws -> [String: Any] {
    guard data.count <= 20 * 1_024 * 1_024,
      let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw APIError.invalidResponse }
    return result
  }
  private static func text(_ value: Any?) -> String { value as? String ?? "" }
  private static func optionalText(_ value: Any?) -> String? {
    let result = text(value)
    return result.isEmpty ? nil : result
  }
  private static func integer(_ value: Any?) -> Int? {
    if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
      let number = value.doubleValue
      if number.isFinite, number.rounded() == number, number >= 0, number <= 1_000_000 {
        return Int(number)
      }
    }
    if let value = value as? String { return Int(value) }
    return nil
  }
  private static func boolean(_ value: Any?) -> Bool {
    if let value = value as? NSNumber { return value.boolValue }
    return (value as? String)?.lowercased() == "true"
  }
  private static func sender(_ item: [String: Any]) -> String {
    text((item["from"] as? [String: Any])?["contactDetails1"])
  }
  private static func messageDate(_ item: [String: Any]) -> String {
    for key in ["sendDateTimeFormattedLong", "sendDateTimeFormattedShort", "sendDateTime"] {
      if let result = optionalText(item[key]) { return result }
    }
    return ""
  }
}

public struct MessageText: Equatable, Sendable {
  public let text: String
  public let links: [URL]
  public let wasShortened: Bool
  public let hasImages: Bool
  /// Pure text processing: no WebView, HTML document loading, scripts, or remote media requests.
  public static func render(_ html: String) throws -> MessageText {
    guard html.utf8.count <= 2 * 1_024 * 1_024 else { throw APIError.invalidResponse }
    func replace(_ value: String, _ pattern: String, _ replacement: String) -> String {
      value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    var clean = replace(html, "(?is)<!--.*?-->", "")
    clean = replace(
      clean, "(?is)<(script|style|iframe|object|noscript|head)\\b[^>]*>.*?</\\1\\s*>", "")
    clean = replace(clean, "(?is)<(?:script|style|iframe|object|noscript|head)\\b[^>]*>.*$", "")
    let hasImages = clean.range(of: "(?i)<img\\b", options: .regularExpression) != nil
    var links: [URL] = []
    let expression = try NSRegularExpression(
      pattern: "(?is)<a\\b[^>]*?\\bhref\\s*=\\s*[\"']([^\"']+)[\"']")
    for match in expression.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)) {
      guard let range = Range(match.range(at: 1), in: clean),
        let url = URL(string: entities(String(clean[range]))),
        url.scheme?.lowercased() == "https", url.host != nil, url.user == nil, url.password == nil,
        !links.contains(url)
      else { continue }
      links.append(url)
    }
    clean = replace(clean, "(?i)<li\\b[^>]*>", "\n• ")
    clean = replace(clean, "(?i)<br\\b[^>]*>|</(?:p|div|tr|h[1-6]|li|ul|ol|blockquote)\\s*>", "\n")
    clean = replace(clean, "(?i)</(?:td|th)\\s*>", "\t")
    clean = replace(clean, "(?s)<[^>]*>", "")
    clean = entities(clean)
    clean = replace(clean, "[ \\t]+\\n", "\n")
    clean = replace(clean, "\\n{3,}", "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    let shortened = clean.count > 100_000
    return MessageText(
      text: shortened ? String(clean.prefix(100_000)) + "…" : clean,
      links: Array(links.prefix(100)), wasShortened: shortened, hasImages: hasImages)
  }
  private static func entities(_ input: String) -> String {
    let names = [
      "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "copy": "©",
      "reg": "®", "ndash": "–", "mdash": "—",
    ]
    guard let regex = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
    else { return input }
    var output = input
    for match in regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed()
    {
      guard let bodyRange = Range(match.range(at: 1), in: input),
        let whole = Range(match.range, in: output)
      else { continue }
      let body = String(input[bodyRange])
      var replacement = names[body]
      if body.hasPrefix("#") {
        let hex = body.hasPrefix("#x")
        if let number = UInt32(body.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
          let scalar = UnicodeScalar(number),
          number >= 32 || number == 10 || number == 9
        {
          replacement = String(scalar)
        }
      }
      if let replacement { output.replaceSubrange(whole, with: replacement) }
    }
    return output
  }
}
