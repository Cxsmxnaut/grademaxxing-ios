import SwiftUI

enum AppInformation {
  static let privacyURL = URL(string: "https://grademaxxing.app/privacy")!
  static let sourceURL = URL(string: "https://github.com/Cxsmxnaut/grademaxxing-ios")!
  static var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    let version = info["CFBundleShortVersionString"] as? String ?? "Development"
    let build = info["CFBundleVersion"] as? String
    return build.map { "\(version) (\($0))" } ?? version
  }
}

struct PrivacyDetailsView: View {
  var body: some View {
    List {
      Section("Connecting to your school") {
        Text(
          "Grademaxxing sends your district, username, and password over HTTPS to its service, which signs in to your district's StudentVUE portal. The password is used for that sign-in and is not saved by the native app."
        )
        Text(
          "Grades, attendance, schedule, profile, documents, and mail pass through the service when you request them. The app is read-only. Official school records stay separate from local grade and GPA estimates."
        )
      }.listRowBackground(Theme.surface)
      Section("On your iPhone") {
        Text(
          "Only your district, username, and opaque session are saved in device-only Keychain. School records and grade plans stay in memory. Document and attachment previews use protected temporary files, removed when closed, on sign-out, and at the next launch."
        )
        Text(
          "Sign out from Account to remove the saved session and clear in-memory records and temporary previews. This does not delete your school's StudentVUE account or records, or the service's usage history."
        )
      }.listRowBackground(Theme.surface)
      Section("Service usage") {
        Text(
          "The service counts sign-ins and active days using a protected identifier derived from your district and username. It may associate your district's state with those counts. This is account-linked usage information, even though the usage database does not contain your raw username."
        )
        Text(
          "The native app has no advertising or third-party analytics SDK. It does not request location, contacts, photos, camera, or microphone access. Your district's state comes from the district catalog, not your phone's location."
        )
      }.listRowBackground(Theme.surface)
      Section("Learn more") {
        Link("Privacy policy", destination: AppInformation.privacyURL)
        Text(
          "The privacy policy also describes website features. The native app does not include Max conversations, referrals, browser password storage, or synced assignment read history."
        ).font(.footnote).foregroundStyle(Theme.muted)
      }.listRowBackground(Theme.surface)
    }.scrollContentBackground(.hidden).background(Theme.background)
      .navigationTitle("Data and privacy").inlineTitle().navigationChromeVisible()
      .accessibilityIdentifier("privacy.details")
  }
}

struct LicensesView: View {
  var body: some View {
    List {
      Section("Grademaxxing") {
        Text(
          "Grademaxxing is derived from GradeCompass and distributed under the GNU Affero General Public License, version 3. StudentVUE is a trademark of Edupoint Educational Systems LLC. Grademaxxing is independent of Edupoint and school districts."
        )
        Link("Corresponding source code", destination: AppInformation.sourceURL)
        NavigationLink("AGPL license and project notices") {
          LicenseTextView(title: "AGPL and notices", asset: "OpenSourceNotices")
        }.accessibilityIdentifier("licenses.agpl")
      }.listRowBackground(Theme.surface)
      Section("Fonts") {
        Text("Manrope, Outfit, and JetBrains Mono are bundled under the SIL Open Font License.")
        NavigationLink("Font licenses") {
          LicenseTextView(title: "Font licenses", asset: "FontLicenses")
        }.accessibilityIdentifier("licenses.fonts")
      }.listRowBackground(Theme.surface)
    }.scrollContentBackground(.hidden).background(Theme.background)
      .navigationTitle("Licenses").inlineTitle().navigationChromeVisible()
  }
}

private struct LicenseTextView: View {
  let title: String
  let asset: String
  private var text: String {
    guard let data = NSDataAsset(name: asset)?.data,
      let text = String(data: data, encoding: .utf8)
    else {
      return "License text is unavailable in this development preview. See the source repository."
    }
    return text
  }
  var body: some View {
    ScrollView {
      Text(text).font(.footnote).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading).padding()
        .accessibilityIdentifier("licenses.text")
    }.background(Theme.background).navigationTitle(title).inlineTitle().navigationChromeVisible()
  }
}
