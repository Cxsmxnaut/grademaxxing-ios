import GrademaxxingCore
import SwiftUI

struct DocumentsView: View {
  @Bindable var model: AppModel
  @State private var query = ""
  var body: some View {
    RecordScreen(
      model: model, store: model.documents, emptyTitle: "Documents could not load",
      reload: { await model.loadDocuments(force: true) }
    ) { documents in
      List {
        let visible = documents.filter {
          query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)
            || $0.category.localizedCaseInsensitiveContains(query)
        }
        if visible.isEmpty {
          ContentUnavailableView(
            "No documents", systemImage: "doc",
            description: Text(
              query.isEmpty
                ? "StudentVUE has no documents available." : "No documents match your search."))
        }
        ForEach(visible) { document in
          Button {
            Task { await model.openDocument(document) }
          } label: {
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: "doc.text").foregroundStyle(Theme.accent).accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 8) {
                Text(document.title.isEmpty ? "Document" : document.title).font(.headline)
                  .foregroundStyle(.primary)
                Text(
                  [document.category, document.date].filter { !$0.isEmpty }.joined(separator: " · ")
                ).font(.caption).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            }.padding(.vertical, 6)
          }.buttonStyle(.plain).disabled(model.preview.isLoading || model.needsReconnect)
            .accessibilityIdentifier("document.\(document.id)")
        }
      }.scrollContentBackground(.hidden)
    }.navigationTitle("Documents").inlineTitle()
      .alwaysVisibleSearch(text: $query, prompt: "Search documents")
      .task(id: model.schoolSessionKey) { await model.loadDocuments() }
  }
}
