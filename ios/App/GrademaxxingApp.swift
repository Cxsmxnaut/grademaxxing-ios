import SwiftUI

@main
struct GrademaxxingApp: App {
  @State private var model = AppModel()
  init() { Theme.registerFonts() }
  var body: some Scene {
    WindowGroup {
      RootView(model: model)
        .tint(Theme.accent)
        .font(Theme.body())
        .foregroundStyle(Theme.foreground)
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
        AppShell(model: model).privacySensitive()
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

private enum AppSection: String, CaseIterable {
  case grades, attendance, documents, mail, planner, school, account
  var title: String {
    switch self {
    case .grades: "Grades"
    case .attendance: "Attendance"
    case .documents: "Documents"
    case .mail: "Mail"
    case .planner: "GPA calculator"
    case .school: "School records"
    case .account: "Account"
    }
  }
  var symbol: String {
    switch self {
    case .grades: "book.fill"
    case .attendance: "calendar.badge.checkmark"
    case .documents: "doc.on.doc.fill"
    case .mail: "envelope.fill"
    case .planner: "plus.forwardslash.minus"
    case .school: "building.2"
    case .account: "person.crop.circle"
    }
  }
}

/// Each primary destination owns its navigation history. System tab and navigation bars
/// adopt the current iOS material, accessibility settings, and safe-area behavior.
enum AppRoute: Hashable {
  case course(String)
  case planner, school, account
}

private struct AppShell: View {
  @Bindable var model: AppModel
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var section = AppSection.grades
  @State private var showMenu = false
  @State private var paths: [AppSection: [AppRoute]] = [:]
  private let primary: [AppSection] = [.grades, .attendance, .documents, .mail]
  var body: some View {
    TabView(selection: $section) {
      ForEach(primary, id: \.self) { item in
        NavigationStack(path: navigationPath(for: item)) {
          destination(item)
            .largeRootTitle()
            .toolbar {
              ToolbarItem(placement: .principal) { brand }
              ToolbarItem(placement: .primaryAction) {
                Button {
                  showMenu = true
                } label: {
                  Label("Navigation", systemImage: "ellipsis")
                }.accessibilityLabel("Open navigation menu").accessibilityIdentifier("app.menu")
              }
            }
            .navigationDestination(for: AppRoute.self) { route in
              switch route {
              case .course(let id):
                if let book = model.gradebook,
                  let course = book.courses.first(where: { $0.wireID == id })
                {
                  CourseView(course: course, detailed: book.detailed, isDemo: model.isDemo)
                }
              case .planner: PlannerView(model: model)
              case .school: SchoolView(model: model)
              case .account: AccountView(model: model)
              }
            }
        }
        .tabItem { Label(item.title, systemImage: item.symbol) }
        .tag(item)
      }
    }.tint(Theme.accent).readableBottomEdge()
      .sheet(isPresented: $showMenu) { menu.privacyShield() }
  }
  private func navigationPath(for item: AppSection) -> Binding<[AppRoute]> {
    Binding(get: { paths[item] ?? [] }, set: { paths[item] = $0 })
  }
  @ViewBuilder private func destination(_ item: AppSection) -> some View {
    switch item {
    case .grades:
      GradesView(model: model, openPlanner: { paths[.grades, default: []].append(.planner) })
    case .attendance: AttendanceView(model: model, isAppRoot: true)
    case .documents: DocumentsView(model: model, isAppRoot: true)
    case .mail: MailView(model: model, isAppRoot: true)
    default: EmptyView()
    }
  }
  private func select(_ next: AppSection) {
    switch next {
    case .planner: paths[section, default: []].append(.planner)
    case .school: paths[section, default: []].append(.school)
    case .account: paths[section, default: []].append(.account)
    default: section = next
    }
    showMenu = false
  }
  private var brand: some View {
    HStack(spacing: 7) {
      Image("BrandMark").resizable().scaledToFit().frame(width: 24, height: 24)
        .accessibilityHidden(true)
      if !dynamicTypeSize.isAccessibilitySize {
        Text("Grademaxxing").font(.custom("OutfitThin-Bold", size: 16, relativeTo: .headline))
      }
      if model.isDemo {
        Text("Demo").font(.caption2).foregroundStyle(Theme.muted)
      }
    }.accessibilityElement(children: .ignore)
      .accessibilityLabel(model.isDemo ? "Grademaxxing, synthetic demo" : "Grademaxxing")
  }
  private var menu: some View {
    NavigationStack {
      List {
        Section("Navigate") {
          ForEach(AppSection.allCases, id: \.self) { item in
            Button {
              select(item)
            } label: {
              Label(item.title, systemImage: item.symbol)
            }.accessibilityIdentifier("menu.\(item.rawValue)")
          }
        }.listRowBackground(Theme.surface)
        if let courses = model.gradebook?.courses, !courses.isEmpty {
          Section("Classes") {
            ForEach(courses) { course in
              Button {
                section = .grades
                paths[.grades] = [.course(course.wireID)]
                showMenu = false
              } label: {
                HStack {
                  Text(course.title).foregroundStyle(.primary)
                  Spacer()
                  Text(course.officialMark).foregroundStyle(
                    Theme.gradeColor(course.officialPercent))
                }
              }.accessibilityIdentifier("menu.course.\(course.wireID)")
            }
          }.listRowBackground(Theme.surface)
        }
      }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Navigation")
        .inlineTitle()
        .toolbar {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { showMenu = false } }
        }
    }.presentationDetents([.large]).presentationDragIndicator(.visible)
  }
}
