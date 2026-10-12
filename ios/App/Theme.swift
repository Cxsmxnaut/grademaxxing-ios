import SwiftUI

enum Theme {
  // Semantic native counterparts to src/app.css. System fonts respect Dynamic Type.
  static let background = Color(red: 21 / 255, green: 30 / 255, blue: 40 / 255)
  static let surface = Color(red: 26 / 255, green: 39 / 255, blue: 55 / 255)
  static let accent = Color(red: 110 / 255, green: 168 / 255, blue: 220 / 255)
  static let success = Color(red: 4 / 255, green: 223 / 255, blue: 167 / 255)
  static let warning = Color(red: 231 / 255, green: 189 / 255, blue: 98 / 255)
  static let simulation = Color(red: 194 / 255, green: 167 / 255, blue: 232 / 255)
  static func gradeColor(_ percent: Double?) -> Color {
    guard let percent else { return .secondary }
    return percent >= 90 ? success : percent >= 80 ? accent : warning
  }
}

struct LoadingView: View {
  let title: String
  let detail: String
  var body: some View {
    VStack(spacing: 18) {
      ProgressView().controlSize(.large)
      Text(title).font(.headline)
      Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
  }
}

struct NoticeView: View {
  let text: String
  var symbol = "info.circle"
  var body: some View {
    Label(text, systemImage: symbol)
      .font(.subheadline).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

private struct PrivacyShield: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase
  func body(content: Content) -> some View {
    content.overlay {
      if scenePhase != .active {
        ZStack {
          Theme.background.ignoresSafeArea()
          Label("Grademaxxing", systemImage: "graduationcap.fill").font(.title2.bold())
        }
      }
    }
  }
}

extension View {
  /// Sheets have their own presentation layer, so protect their contents as well as the root.
  func privacyShield() -> some View { modifier(PrivacyShield()) }
  @ViewBuilder func loginInput() -> some View {
    #if os(iOS)
      self.textInputAutocapitalization(.never).autocorrectionDisabled()
    #else
      self.autocorrectionDisabled()
    #endif
  }
  @ViewBuilder func urlInput() -> some View {
    #if os(iOS)
      self.keyboardType(.URL)
    #else
      self
    #endif
  }
  @ViewBuilder func decimalInput() -> some View {
    #if os(iOS)
      self.keyboardType(.decimalPad)
    #else
      self
    #endif
  }
  @ViewBuilder func inlineTitle() -> some View {
    #if os(iOS)
      self.navigationBarTitleDisplayMode(.inline)
    #else
      self
    #endif
  }
  /// Pins the search field so it stays reachable. The iOS default hides the field for an
  /// inline title on iOS 27, which removes the search affordance from the accessibility tree.
  @ViewBuilder func alwaysVisibleSearch(text: Binding<String>, prompt: String) -> some View {
    #if os(iOS)
      self.searchable(
        text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
    #else
      self.searchable(text: text, prompt: prompt)
    #endif
  }
}
