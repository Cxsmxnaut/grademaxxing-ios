import SwiftUI

struct AccountView: View {
  @Bindable var model: AppModel
  @State private var showReconnect = false
  @State private var confirmSignOut = false
  var body: some View {
    Form {
      Section("Session") {
        if model.isDemo {
          Label("Synthetic demo", systemImage: "sparkles")
          Text("You are exploring invented grades. No school account is connected.")
            .foregroundStyle(.secondary)
        } else if let account = model.identity {
          LabeledContent("Username", value: account.username)
          LabeledContent("District", value: URL(string: account.domain)?.host ?? "StudentVUE")
          LabeledContent(
            "Connection", value: model.needsReconnect ? "Reconnect needed" : "Signed in")
          if model.needsReconnect { Button("Reconnect to StudentVUE") { showReconnect = true } }
        }
      }
      Section("On this device") {
        if let error = model.preview.error, !model.preview.isPresented {
          NoticeView(text: error, symbol: "exclamationmark.circle")
          Button("Clear temporary previews") { model.preview.close() }
        }
        Label("Session protected by Keychain", systemImage: "lock.shield")
        Text(
          "Your StudentVUE password is not saved. School records remain in memory and are cleared when you sign out. File previews use temporary protected copies that are removed when closed or on sign-out. The app session expires when the service or district requires a new sign-in."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
      Section("About") {
        LabeledContent("Grademaxxing for iOS", value: "0.1 · Native preview")
        Link("Privacy policy", destination: URL(string: "https://grademaxxing.app/privacy")!)
        Text(
          "Independent, read-only companion. Not affiliated with Edupoint or your school district. StudentVUE is a trademark of Edupoint."
        )
        .font(.footnote).foregroundStyle(.secondary)
      }
      Section {
        Button(model.isDemo ? "Leave demo" : "Sign out", role: .destructive) {
          confirmSignOut = true
        }
        .accessibilityIdentifier("account.signout")
      }
    }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Account")
      .confirmationDialog(
        model.isDemo ? "Leave the demo?" : "Sign out and clear this session?",
        isPresented: $confirmSignOut, titleVisibility: .visible
      ) {
        Button(model.isDemo ? "Leave demo" : "Sign out", role: .destructive) {
          Task { await model.signOut() }
        }
      }
      .sheet(isPresented: $showReconnect) { ReconnectView(model: model) }
  }
}
