import SwiftUI

struct SignInView: View {
  @Bindable var model: AppModel
  @State private var domain = "https://ca-pleas-psv.edupoint.com"
  @State private var showDistrictPicker = false
  @State private var username = ""
  @State private var password = ""
  @FocusState private var focused: Field?
  private enum Field { case username, password }
  private var canSubmit: Bool {
    !domain.isEmpty && !username.isEmpty && !password.isEmpty && !model.isWorking
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          HStack(spacing: 10) {
            Image("BrandMark").resizable().scaledToFit().frame(width: 36, height: 36)
              .accessibilityHidden(true)
            Text("Grademaxxing").font(Theme.heading(26)).tracking(-0.6)
          }.padding(.bottom, 20)
          VStack(alignment: .leading, spacing: 8) {
            Text("Your grades.\nYour next move.").font(.largeTitle.bold())
            Text("Sign in with your StudentVUE account.")
              .font(.body).foregroundStyle(Theme.muted)
          }
          VStack(alignment: .leading, spacing: 18) {
            field("School district") {
              Button {
                focused = nil
                showDistrictPicker = true
              } label: {
                HStack(spacing: 12) {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(SchoolDistrict.selected(for: domain)?.name ?? domain)
                      .foregroundStyle(Theme.foreground).multilineTextAlignment(.leading)
                    if let district = SchoolDistrict.selected(for: domain) {
                      Text(district.state).font(.caption).foregroundStyle(Theme.muted)
                    }
                  }.frame(maxWidth: .infinity, alignment: .leading)
                  Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent).accessibilityHidden(true)
                }.frame(minHeight: 44).contentShape(Rectangle())
              }.buttonStyle(.plain)
                .accessibilityLabel("School district")
                .accessibilityValue(
                  "\(SchoolDistrict.selected(for: domain)?.name ?? "Custom portal"), \(domain)"
                )
                .accessibilityIdentifier("login.district")
            }
            field("Username") {
              TextField("StudentVUE username", text: $username)
                .loginInput().textContentType(.username).focused($focused, equals: .username)
                .submitLabel(.next).onSubmit { focused = .password }.accessibilityIdentifier(
                  "login.username")
            }
            field("Password") {
              SecureField("StudentVUE password", text: $password)
                .textContentType(.password).focused($focused, equals: .password)
                .submitLabel(.go).onSubmit { submit() }.accessibilityIdentifier("login.password")
            }
          }.disabled(model.isWorking)
          if let message = model.message {
            NoticeView(text: message, symbol: "exclamationmark.circle")
          }
          if let error = model.preview.error, !model.preview.isPresented {
            NoticeView(text: error, symbol: "exclamationmark.circle")
            Button("Clear temporary previews") { model.preview.close() }
          }
          Button(action: submit) {
            HStack {
              if model.isWorking { ProgressView() }
              Text(model.isWorking ? "Connecting to StudentVUE…" : "Sign in").fontWeight(.semibold)
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
          }.buttonStyle(.borderedProminent).disabled(!canSubmit)
            .accessibilityIdentifier(
              "login.submit")
          Button("Explore the demo") {
            password = ""
            focused = nil
            model.enterDemo()
          }
          .frame(maxWidth: .infinity).buttonStyle(.bordered).disabled(model.isWorking)
          .accessibilityIdentifier(
            "login.demo")
          Text(
            "Your district, username, and password are sent over HTTPS to Grademaxxing to sign in to StudentVUE. Your password is not saved. Grademaxxing reads school records; it does not change them."
          )
          .font(.footnote).foregroundStyle(Theme.muted)
          NavigationLink("Data and privacy") { PrivacyDetailsView() }
            .font(.footnote).frame(minHeight: 44).accessibilityIdentifier("login.privacy")
          Link("Privacy policy", destination: AppInformation.privacyURL)
            .font(.footnote).frame(minHeight: 44)
          Text(
            "Independent companion. Not affiliated with Edupoint or your district. StudentVUE is a trademark of Edupoint."
          )
          .font(.caption).foregroundStyle(Theme.muted)
        }.font(.body).padding(24).padding(.top, 32).frame(maxWidth: 520)
          .frame(maxWidth: .infinity)
      }
      .background(Theme.background).navigationTitle("Grademaxxing").navigationChromeHidden()
      .sheet(isPresented: $showDistrictPicker) {
        DistrictPicker(domain: $domain).privacyShield()
      }
    }
  }
  private func submit() {
    guard canSubmit else { return }
    focused = nil
    let secret = password
    password = ""
    Task { await model.signIn(domain: domain, username: username, password: secret) }
  }
  private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
      content().font(.body).padding(14)
        .background(Theme.secondarySurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border, lineWidth: 1))
    }
  }
}

/// Uses the same public, offline district snapshot as the web app. No school requests occur here.
private struct SchoolDistrict: Decodable, Identifiable {
  let state: String
  let name: String
  let domain: String
  var id: String { name + "\n" + domain }
  static let all: [SchoolDistrict] = {
    guard let data = NSDataAsset(name: "DistrictCatalog")?.data else { return [] }
    return (try? JSONDecoder().decode([SchoolDistrict].self, from: data)) ?? []
  }()
  static func selected(for domain: String) -> SchoolDistrict? {
    guard let selectedTarget = target(domain) else { return nil }
    return all.first { $0.domain == selectedTarget }
  }
  static func target(_ input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
      let host = url.host
    else { return nil }
    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    return host.lowercased() + (path.isEmpty ? "" : "/" + path)
  }
  func searchScore(_ query: String) -> Int? {
    let name = name.lowercased()
    if name == query { return 0 }
    if name.hasPrefix(query) { return 1 }
    if name.split(whereSeparator: \.isWhitespace).contains(where: { $0.hasPrefix(query) }) {
      return 2
    }
    if name.contains(query) { return 3 }
    if state.lowercased().hasPrefix(query) { return 4 }
    if domain.lowercased().contains(query) { return 5 }
    return nil
  }
  static func matching(_ text: String) -> [SchoolDistrict] {
    let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return all }
    return all.enumerated().compactMap { index, district -> (Int, Int, SchoolDistrict)? in
      district.searchScore(query).map { ($0, index, district) }
    }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }.map { $0.2 }
  }
}

private struct DistrictPicker: View {
  @Binding var domain: String
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var showCustomPortal = false
  @State private var customPortal = ""
  private var validCustomPortal: Bool {
    guard let url = URL(string: customPortal.trimmingCharacters(in: .whitespacesAndNewlines)),
      url.scheme == "https", let host = url.host, !host.isEmpty,
      url.user == nil, url.password == nil
    else { return false }
    return customPortal.count <= 2048
  }
  var body: some View {
    NavigationStack {
      List {
        let selected = SchoolDistrict.selected(for: domain)
        Section {
          Button {
            showCustomPortal.toggle()
          } label: {
            HStack {
              Text("Enter a portal URL")
              Spacer()
              Image(systemName: showCustomPortal ? "chevron.down" : "chevron.right")
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }.frame(minHeight: 44).contentShape(Rectangle())
          }.buttonStyle(.plain).accessibilityIdentifier("district.custom")
            .accessibilityValue(showCustomPortal ? "Expanded" : "Collapsed")
          if showCustomPortal {
            TextField("https://your-district.studentvue.org", text: $customPortal)
              .urlInput().loginInput().accessibilityLabel("District portal URL")
              .accessibilityIdentifier("district.customPortal")
            Button("Use this portal") {
              domain = customPortal.trimmingCharacters(in: .whitespacesAndNewlines)
              dismiss()
            }.disabled(!validCustomPortal).accessibilityIdentifier("district.useCustom")
          }
        }.listRowBackground(Theme.surface)
        if query.isEmpty, let selected {
          Section("Selected district") { option(selected) }.listRowBackground(Theme.surface)
        }
        Section(query.isEmpty ? "All districts" : "Matching districts") {
          let matches = SchoolDistrict.matching(query)
          if matches.isEmpty {
            Text(
              SchoolDistrict.all.isEmpty
                ? "District list unavailable. Enter your portal URL above."
                : "No matching school districts"
            )
            .foregroundStyle(Theme.muted).accessibilityIdentifier("district.empty")
          }
          ForEach(
            matches.filter { !query.isEmpty || $0.id != selected?.id }
          ) { district in
            option(district)
          }
        }.listRowBackground(Theme.surface)
      }.scrollContentBackground(.hidden).background(Theme.background)
        .navigationTitle("School district").inlineTitle()
        .alwaysVisibleSearch(text: $query, prompt: "District, state, or portal")
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.accessibilityIdentifier("district.cancel")
          }
        }
    }.presentationDetents([.large])
  }
  private func option(_ district: SchoolDistrict) -> some View {
    Button {
      domain = "https://" + district.domain
      dismiss()
    } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text(district.name).font(.body.weight(.medium)).foregroundStyle(Theme.foreground)
          Text(district.state + " · " + district.domain).font(.caption).foregroundStyle(Theme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if SchoolDistrict.target(domain) == district.domain {
          Image(systemName: "checkmark").foregroundStyle(Theme.accent).accessibilityHidden(true)
        }
      }.padding(.vertical, 6).contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier("district.option.\(district.name)")
      .accessibilityAddTraits(SchoolDistrict.target(domain) == district.domain ? .isSelected : [])
  }
}
