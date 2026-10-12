import GrademaxxingCore
import SwiftUI

struct MailView: View {
  @Bindable var model: AppModel
  @State private var query = ""
  @State private var folder = "all"
  @State private var unreadOnly = false
  var body: some View {
    RecordScreen(
      model: model, store: model.mailbox, emptyTitle: "Mail could not load",
      reload: { await model.loadMailbox(force: true) }
    ) { mailbox in
      List {
        Section {
          Picker("Folder", selection: $folder) {
            Text("All folders").tag("all")
            ForEach(mailbox.folders) { Text($0.name.isEmpty ? "Folder" : $0.name).tag($0.id) }
          }.pickerStyle(.menu).accessibilityIdentifier("mail.folder")
          Toggle("Unread in StudentVUE", isOn: $unreadOnly)
          Text("Reading here does not mark a message as read in StudentVUE.").font(.footnote)
            .foregroundStyle(.secondary)
        }
        let messages = mailbox.messages.filter { item in
          (folder == "all" || item.folderKey == folder) && (!unreadOnly || !item.isRead)
            && (query.isEmpty || item.subject.localizedCaseInsensitiveContains(query)
              || item.sender.localizedCaseInsensitiveContains(query))
        }
        Section("Messages") {
          if messages.isEmpty {
            Text("No messages match this selection.").foregroundStyle(.secondary)
          }
          ForEach(messages) { message in
            NavigationLink {
              MessageReadView(model: model, preview: message)
            } label: {
              HStack(alignment: .top, spacing: 12) {
                Circle().fill(message.isRead ? .clear : Theme.accent).frame(width: 8, height: 8)
                  .padding(.top, 6).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                  Text(message.subject.isEmpty ? "No subject" : message.subject).font(.headline)
                  Text(
                    [message.sender, message.date].filter { !$0.isEmpty }.joined(separator: " · ")
                  ).font(.caption).foregroundStyle(.secondary)
                  if !message.folderName.isEmpty {
                    Text(message.folderName).font(.caption2).foregroundStyle(.tertiary)
                  }
                  if message.messageID == nil {
                    Text("Message details are unavailable.").font(.caption).foregroundStyle(
                      .secondary)
                  }
                }
              }.padding(.vertical, 4)
            }.disabled(message.messageID == nil).accessibilityIdentifier(
              "mail.message.\(message.messageID ?? message.id)"
            )
            .accessibilityValue(message.isRead ? "Read in StudentVUE" : "Unread in StudentVUE")
          }
        }
        if mailbox.messages.filter({ folder == "all" || $0.folderKey == folder }).count >= 500 {
          Section {
            Text("More messages may be available in StudentVUE.").font(.footnote).foregroundStyle(
              .secondary)
          }
        }
      }.scrollContentBackground(.hidden)
    }.navigationTitle("Mail").inlineTitle().searchable(text: $query, prompt: "Search messages")
      .task(id: model.schoolSessionKey) { await model.loadMailbox() }
  }
}

struct MessageReadView: View {
  @Bindable var model: AppModel
  let preview: MailPreview
  var body: some View {
    RecordScreen(
      model: model, store: model.messageDetail, emptyTitle: "Message could not load",
      reload: { await model.loadMessage(preview, force: true) }
    ) { message in
      if message.messageID != preview.messageID || message.isSystem != preview.isSystem {
        LoadingView(title: "Loading message", detail: "Opening the selected message")
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
              Text(
                message.subject.isEmpty
                  ? (preview.subject.isEmpty ? "No subject" : preview.subject) : message.subject
              ).font(.title2.bold())
              Text(message.sender.isEmpty ? preview.sender : message.sender).font(.headline)
              Text(message.date.isEmpty ? preview.date : message.date).font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(message.body.text.isEmpty ? "No message text was provided." : message.body.text)
              .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
              .accessibilityIdentifier("mail.body")
            if message.body.wasShortened {
              NoticeView(
                text:
                  "This long message is shortened for display. Open StudentVUE to read the full message."
              )
            }
            if message.body.hasImages {
              NoticeView(
                text: "This message includes images. Open StudentVUE to view the complete message.",
                symbol: "photo")
            }
            if !message.body.links.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Text("Links").font(.headline)
                ForEach(message.body.links, id: \.absoluteString) { url in
                  Link(destination: url) {
                    Label(url.host ?? "Open link", systemImage: "link").frame(
                      minHeight: 44, alignment: .leading)
                  }
                }
              }
            }
            if !message.attachments.isEmpty {
              VStack(alignment: .leading, spacing: 12) {
                Text("Attachments").font(.headline)
                ForEach(message.attachments) { attachment in
                  Button {
                    Task { await model.openAttachment(attachment) }
                  } label: {
                    Label(
                      attachment.name.isEmpty ? "Attachment" : attachment.name,
                      systemImage: "paperclip"
                    ).frame(minHeight: 44, alignment: .leading)
                  }.disabled(model.preview.isLoading || model.needsReconnect)
                    .accessibilityIdentifier("attachment.\(attachment.id)")
                }
              }
            }
            if let portal = model.portalURL {
              Link("Open StudentVUE", destination: portal).font(.footnote)
            }
          }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
      }
    }.navigationTitle("Message").inlineTitle()
      .task(id: "\(model.schoolSessionKey)|\(preview.id)") { await model.loadMessage(preview) }
  }
}
