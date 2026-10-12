import GrademaxxingCore
import SwiftUI

#if os(iOS)
  import QuickLook
  import UIKit
#else
  import AppKit
  import PDFKit
#endif

struct FilePreviewView: View {
  @Bindable var model: AppModel
  var body: some View {
    NavigationStack {
      Group {
        if let url = model.preview.url {
          #if os(iOS)
            NativeFilePreview(url: url)
          #else
            if model.preview.kind == .pdf {
              DesktopPDFPreview(url: url)
            } else if let image = NSImage(contentsOf: url) {
              Image(nsImage: image).resizable().scaledToFit().padding()
            } else {
              ContentUnavailableView("Preview unavailable", systemImage: "doc")
            }
          #endif
        } else if model.preview.isLoading {
          LoadingView(title: "Opening document", detail: "Downloading the file from StudentVUE")
        } else {
          ContentUnavailableView {
            Label("Preview unavailable", systemImage: "doc")
          } description: {
            Text(model.preview.error ?? "The file could not be opened.")
          } actions: {
            if let portal = model.portalURL {
              Link("Open StudentVUE", destination: portal).buttonStyle(.borderedProminent)
            }
          }
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
        .navigationTitle(model.preview.name).inlineTitle()
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Close") { model.preview.close() }.accessibilityIdentifier("preview.close")
          }
        }
    }.privacyShield().onDisappear { model.preview.close() }
  }
}

#if os(iOS)
  private struct NativeFilePreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
      let controller = QLPreviewController()
      controller.dataSource = context.coordinator
      controller.delegate = context.coordinator
      return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
      if context.coordinator.url != url {
        context.coordinator.url = url
        controller.reloadData()
      }
    }
    @MainActor
    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
      var url: URL
      init(url: URL) { self.url = url }
      func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
      func previewController(_ controller: QLPreviewController, previewItemAt index: Int)
        -> any QLPreviewItem
      { url as NSURL }
      nonisolated func previewController(
        _ controller: QLPreviewController, shouldOpen url: URL, for item: any QLPreviewItem
      ) -> Bool { false }
      nonisolated func previewController(
        _ controller: QLPreviewController, editingModeFor previewItem: any QLPreviewItem
      ) -> QLPreviewItemEditingMode { .disabled }
    }
  }
#else
  private struct DesktopPDFPreview: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
      let view = PDFView()
      view.autoScales = true
      view.document = PDFDocument(url: url)
      return view
    }
    func updateNSView(_ view: PDFView, context: Context) {
      if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
  }
#endif
