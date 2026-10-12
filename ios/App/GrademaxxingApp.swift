import SwiftUI

@main
struct GrademaxxingApp: App {
  @State private var model = AppModel()
  var body: some Scene {
    WindowGroup {
      RootView(model: model)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        #if os(macOS)
          .frame(minWidth: 390, minHeight: 750)
        #endif
    }
  }
}

struct RootView: View {
  @Bindable var model: AppModel
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    ZStack {
      Theme.background.ignoresSafeArea()
      switch model.phase {
      case .starting:
        LoadingView(title: "Opening Grademaxxing", detail: "Checking your saved session")
      case .signedOut: SignInView(model: model)
      case .signedIn:
        TabView {
          NavigationStack { GradesView(model: model) }
            .tabItem { Label("Grades", systemImage: "graduationcap.fill") }
          NavigationStack { PlannerView(model: model) }
            .tabItem { Label("Planner", systemImage: "slider.horizontal.3") }
          NavigationStack { SchoolView(model: model) }
            .tabItem { Label("School", systemImage: "building.2") }
          NavigationStack { AccountView(model: model) }
            .tabItem { Label("Account", systemImage: "person.crop.circle") }
        }
        .privacySensitive()
      }
      if scenePhase != .active {
        Theme.background.ignoresSafeArea()
        Label("Grademaxxing", systemImage: "graduationcap.fill").font(.title2.bold())
      }
    }
    .task { await model.restore() }
    .sheet(
      isPresented: Binding(
        get: { model.preview.isPresented }, set: { if !$0 { model.preview.close() } })
    ) {
      FilePreviewView(model: model)
    }
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      await model.resume()
      // Visible-only liveness loop; task cancellation stops it when the app backgrounds.
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(300)) } catch { return }
        await model.resume()
      }
    }
  }
}
