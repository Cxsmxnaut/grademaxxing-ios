// Hallmark · existing Grademaxxing design · workbench · navy / green / gold
import CoreText
import SwiftUI

#if os(iOS)
  import UIKit
#else
  import AppKit
#endif

enum Theme {
  // Branded content colors adapt to the system appearance; system chrome remains unstyled.
  static let background = adaptive(light: 0xF2F4F7, dark: 0x151E28)
  static let surface = adaptive(light: 0xFFFFFF, dark: 0x1A2737)
  static let secondarySurface = adaptive(light: 0xE8EDF2, dark: 0x202D38)
  static let foreground = Color.primary
  static let muted = adaptive(light: 0x4B5B6B, dark: 0xA9B7C7, increasedContrast: true)
  // Small metadata needs readable contrast, so use secondary rather than tertiary label color.
  static let tertiary = adaptive(light: 0x4B5B6B, dark: 0x93A4B8, increasedContrast: true)
  static let border = Color.primary.opacity(0.08)
  static let accent = adaptive(light: 0x245B8C, dark: 0x6EA8DC, increasedContrast: true)
  static let success = adaptive(light: 0x007456, dark: 0x04DFA7, increasedContrast: true)
  static let warning = adaptive(light: 0x805500, dark: 0xE7BD62, increasedContrast: true)
  static let simulation = adaptive(light: 0x70409C, dark: 0xC2A7E8, increasedContrast: true)
  static let risk = adaptive(light: 0xB3261E, dark: 0xF08078, increasedContrast: true)
  private static func adaptive(light: UInt32, dark: UInt32, increasedContrast: Bool = false)
    -> Color
  {
    #if os(iOS)
      return Color(
        uiColor: UIColor { traits in
          let value = traits.userInterfaceStyle == .dark ? dark : light
          let high = increasedContrast && traits.accessibilityContrast == .high
          func component(_ shift: UInt32) -> Double {
            let base = Double((value >> shift) & 255) / 255
            return !high
              ? base : traits.userInterfaceStyle == .dark ? base + (1 - base) * 0.2 : base * 0.75
          }
          return UIColor(red: component(16), green: component(8), blue: component(0), alpha: 1)
        })
    #else
      return Color(
        nsColor: NSColor(name: nil) { appearance in
          let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
          return NSColor(
            srgbRed: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        })
    #endif
  }
  static let pageInset: CGFloat = 20
  static let cardRadius: CGFloat = 16
  static func body(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font {
    let style: Font.TextStyle
    switch size {
    case ...11: style = .caption2
    case ...12: style = .caption
    case ...13: style = .footnote
    case ...15: style = .subheadline
    case ...17: style = .body
    case ...20: style = .title3
    case ...24: style = .title2
    case ...28: style = .title
    default: style = .largeTitle
    }
    return .system(style).weight(weight)
  }
  static func metric(_ style: Font.TextStyle = .title) -> Font {
    .system(style, design: .rounded).weight(.semibold).monospacedDigit()
  }
  static func heading(_ size: CGFloat = 24) -> Font {
    body(size, weight: .bold)
  }
  static func mono(_ size: CGFloat = 13, bold: Bool = false) -> Font {
    .custom(
      bold ? "JetBrainsMono-SemiBold" : "JetBrainsMono-Regular", size: max(size, 11),
      relativeTo: .caption)
  }
  /// Font bytes live in the existing asset catalog, so Xcode and the native app use the same fonts
  /// without a download, a web view, or machine-specific resource paths. The OFL texts are bundled.
  @MainActor static func registerFonts() {
    for name in [
      "ManropeRegular", "ManropeMedium", "ManropeSemibold", "ManropeExtraBold", "OutfitSemibold",
      "OutfitBold",
      "JetBrainsRegular", "JetBrainsSemibold",
    ] {
      guard let data = NSDataAsset(name: name)?.data,
        let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider)
      else { continue }
      CTFontManagerRegisterGraphicsFont(font, nil)
    }

  }
  static func gradeColor(_ percent: Double?) -> Color {
    guard let percent else { return muted }
    return percent > 100 ? simulation : percent >= 90 ? success : percent >= 80 ? warning : risk
  }
}

struct ProductButtonStyle: ButtonStyle {
  var primary = false
  var compact = false
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(Theme.body(15, weight: .semibold))
      .padding(.horizontal, 16).padding(.vertical, 4)
      .frame(minHeight: compact ? 44 : 50)
      .foregroundStyle(primary ? Theme.background : Theme.foreground)
      .background(
        primary ? Theme.accent : Theme.secondarySurface,
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .strokeBorder(primary ? Theme.accent : Theme.border, lineWidth: 1)
      }
      .frame(minHeight: 44).contentShape(Rectangle())
      .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
  }
}

struct CardButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? 0.82 : 1)
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct MetadataPill: View {
  let text: String
  let symbol: String
  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: symbol).font(.system(size: 12))
      Text(text).font(Theme.body(11.5, weight: .medium)).tracking(0.46).lineLimit(1)
    }.foregroundStyle(Theme.muted)
      .padding(.horizontal, 9).padding(.vertical, 3).frame(minHeight: 21)
      .background(Theme.secondarySurface, in: Capsule())
  }
}

struct GradeMeter: View {
  let percent: Double
  var body: some View {
    GeometryReader { geometry in
      Capsule().fill(Theme.secondarySurface)
        .overlay(alignment: .leading) {
          Capsule().fill(Theme.gradeColor(percent))
            .frame(width: geometry.size.width * min(max(percent / 100, 0), 1))
        }
    }.frame(height: 5).accessibilityHidden(true)
  }
}

struct ProductSearchField: View {
  @Binding var text: String
  let prompt: String
  let identifier: String
  @FocusState private var focused: Bool
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiary)
      TextField(prompt, text: $text).textFieldStyle(.plain).font(Theme.body(13))
        .focused($focused).submitLabel(.search).onSubmit { focused = false }
        .accessibilityIdentifier(identifier)
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).foregroundStyle(Theme.muted).accessibilityLabel("Clear search")
      }
    }.padding(.horizontal, 12).frame(minHeight: 44)
      .background(Theme.secondarySurface, in: RoundedRectangle(cornerRadius: 8))
  }
}

struct LoadingView: View {
  let title: String
  let detail: String
  var body: some View {
    VStack(spacing: 18) {
      ProgressView().controlSize(.large)
      Text(title).font(.headline)
      Text(detail).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(32)
  }
}

struct NoticeView: View {
  let text: String
  var symbol = "info.circle"
  var body: some View {
    Label(text, systemImage: symbol)
      .font(.subheadline).foregroundStyle(Theme.muted)
      .fixedSize(horizontal: false, vertical: true)
      .padding(14).frame(maxWidth: .infinity, alignment: .leading)
      .productPanel()
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
  func productPanel() -> some View {
    background(
      Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        .strokeBorder(Theme.border, lineWidth: 1)
    }
  }
  @ViewBuilder func largeRootTitle() -> some View {
    #if os(iOS)
      self.navigationBarTitleDisplayMode(.large)
    #else
      self
    #endif
  }
  @ViewBuilder func navigationChromeHidden() -> some View {
    #if os(iOS)
      toolbar(.hidden, for: .navigationBar)
    #else
      self
    #endif
  }
  @ViewBuilder func navigationChromeVisible() -> some View {
    #if os(iOS)
      toolbar(.visible, for: .navigationBar)
    #else
      self
    #endif
  }
  /// Keep record text above the native tab bar readable instead of fading it into its scrim.
  @ViewBuilder func readableBottomEdge() -> some View {
    #if os(iOS)
      if #available(iOS 26.0, *) {
        self.scrollEdgeEffectHidden(true, for: .bottom)
      } else {
        self
      }
    #else
      self
    #endif
  }
  @ViewBuilder func appRootChrome(_ isRoot: Bool) -> some View {
    if isRoot {
      navigationChromeVisible().largeRootTitle()
    } else {
      navigationChromeVisible().inlineTitle()
    }
  }
  /// Sheets have their own presentation layer, so protect their contents as well as the root.
  func privacyShield() -> some View { modifier(PrivacyShield()) }
  @ViewBuilder func keyboardDoneButton() -> some View {
    #if os(iOS)
      self.toolbar {
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button {
            UIApplication.shared.sendAction(
              #selector(UIResponder.resignFirstResponder),
              to: nil, from: nil, for: nil)
          } label: {
            Label("Dismiss keyboard", systemImage: "keyboard.chevron.compact.down")
          }
        }
      }.scrollDismissesKeyboard(.interactively)
    #else
      self
    #endif
  }
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
        text: text, placement: .navigationBarDrawer(displayMode: .always),
        prompt: prompt
      )
      .background {
        ReadableSearchField().frame(width: 0, height: 0).accessibilityHidden(true)
      }
    #else
      self.searchable(text: text, prompt: prompt)
    #endif
  }
}

#if os(iOS)
  /// SwiftUI's searchable prompt drops Text foreground attributes on some iOS versions.
  /// Style the public UISearchBar search field after navigation installs it, retaining its
  /// native search behavior, font, accessible label, and attributed placeholder contents.
  private struct ReadableSearchField: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SearchFieldStyleController {
      SearchFieldStyleController()
    }
    func updateUIViewController(_ controller: SearchFieldStyleController, context: Context) {
      controller.updateSearchFields()
    }
  }

  private final class SearchFieldStyleController: UIViewController {
    override func loadView() {
      view = UIView()
      view.isUserInteractionEnabled = false
    }
    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      updateSearchFields()
    }
    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      updateSearchFields()
    }
    func updateSearchFields() {
      guard let window = viewIfLoaded?.window else { return }
      var pending: [UIView] = [window]
      while let candidate = pending.popLast() {
        pending.append(contentsOf: candidate.subviews)
        guard let bar = candidate as? UISearchBar,
          let placeholder = bar.searchTextField.placeholder, !placeholder.isEmpty
        else { continue }
        let current =
          bar.searchTextField.attributedPlaceholder ?? NSAttributedString(string: placeholder)
        let color = UIColor(Theme.muted).resolvedColor(with: bar.traitCollection)
        let readable = NSMutableAttributedString(attributedString: current)
        readable.addAttribute(
          .foregroundColor, value: color, range: NSRange(location: 0, length: readable.length))
        if !current.isEqual(to: readable) { bar.searchTextField.attributedPlaceholder = readable }
      }
    }
  }
#endif
