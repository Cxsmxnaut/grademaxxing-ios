import SwiftUI

struct SignInView: View {
  @Bindable var model: AppModel
  @State private var domain = ""
  @State private var username = ""
  @State private var password = ""
  @FocusState private var focused: Field?
  private enum Field { case domain, username, password }
  private var canSubmit: Bool {
    !domain.isEmpty && !username.isEmpty && !password.isEmpty && !model.isWorking
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Image(systemName: "graduationcap.fill")
            .font(.system(size: 44)).foregroundStyle(Theme.success).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 8) {
            Text("Your grades.\nYour next move.").font(.largeTitle.bold())
            Text("Sign in with your StudentVUE account.").foregroundStyle(.secondary)
          }
          VStack(alignment: .leading, spacing: 18) {
            field("District portal") {
              TextField("https://your-district.studentvue.org", text: $domain)
                .urlInput().loginInput().focused($focused, equals: .domain)
                .textContentType(.URL).submitLabel(.next)
                .onSubmit { focused = .username }.accessibilityIdentifier("login.domain")
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
          }.buttonStyle(.borderedProminent).disabled(!canSubmit).accessibilityIdentifier(
            "login.submit")
          Button("Explore the demo") {
            password = ""
            focused = nil
            model.enterDemo()
          }
          .frame(maxWidth: .infinity).disabled(model.isWorking).accessibilityIdentifier(
            "login.demo")
          Text(
            "Your password is used to sign in and is not saved on this device. Grademaxxing reads school records; it does not change them."
          )
          .font(.footnote).foregroundStyle(.secondary)
          Link("Privacy policy", destination: URL(string: "https://grademaxxing.app/privacy")!)
            .font(.footnote)
          Text(
            "Independent companion. Not affiliated with Edupoint or your district. StudentVUE is a trademark of Edupoint."
          )
          .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: 520)
          .frame(maxWidth: .infinity)
      }
      .background(Theme.background).navigationTitle("Grademaxxing").inlineTitle()
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
      Text(title).font(.subheadline.weight(.medium))
      content().padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
  }
}
