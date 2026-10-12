import CoreGraphics
import CoreText
import Foundation

public enum DocumentsMailDemo {
  public static let messageID = "11111111-2222-4333-8444-555555555555"
  public static let attachmentID = "22222222-3333-4444-8555-666666666666"
  public static let documentID = "c3ludGhldGljLWRvY3VtZW50"
  public static func documents() throws -> [SchoolDocument] {
    try DocumentsDecoder.decode(
      Data(
        """
        {"StudentDocumentDatas":{"StudentDocumentData":[{"_DocumentGU":"\(documentID)",
        "_DocumentFileName":"Synthetic progress report.pdf","_DocumentDate":"10/09/2026","_DocumentType":"Report"}]}}
        """.utf8))
  }
  public static func mailbox() throws -> Mailbox {
    let payload: [String: Any] = [
      "folders": [["folderType": 0, "name": "Inbox"], ["folderType": 1, "name": "Sent"]],
      "messages": [
        [
          "messagePersonId": messageID, "subject": "Upcoming project",
          "from": ["contactDetails1": "Ms. Example"],
          "sendDateTimeFormattedLong": "October 9, 2026", "mailRead": false,
          "isSystemMessage": false,
          "portalFolderType": 0, "portalFolderName": "Inbox",
        ]
      ],
    ]
    return try MailDecoder.mailbox(JSONSerialization.data(withJSONObject: payload))
  }
  public static func message(id: String) throws -> ReadableMessage {
    let payload: [String: Any] = [
      "subject": "Upcoming project", "from": ["contactDetails1": "Ms. Example"],
      "sendDateTimeFormattedLong": "October 9, 2026",
      "messageText":
        "<p>This is an invented message for the native demo.</p><p>Review the attached synthetic project guide.</p>",
      "attachments": [["attachmentId": attachmentID, "name": "Synthetic project guide.pdf"]],
    ]
    return try MailDecoder.message(
      JSONSerialization.data(withJSONObject: payload), id: id, isSystem: false)
  }
  /// An original, non-student PDF generated locally through Core Graphics for preview tests.
  public static func file() throws -> PreviewFile {
    let data = NSMutableData()
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &box, nil)
    else { throw APIError.invalidFile }
    context.beginPDFPage(nil)
    for (index, text) in [
      "Grademaxxing", "Synthetic preview document", "This PDF contains invented information only.",
      "No student records or credentials are included.",
    ].enumerated() {
      let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName(
          "Helvetica" as CFString, index == 0 ? 24 : 14, nil)
      ]
      let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: text, attributes: attributes))
      context.textPosition = CGPoint(x: 48, y: 720 - index * 40)
      CTLineDraw(line, context)
    }
    context.endPDFPage()
    context.closePDF()
    return try PreviewFileDecoder.validate(
      base64: (data as Data).base64EncodedString(), name: "Synthetic document.pdf",
      mime: "application/pdf")
  }
}
