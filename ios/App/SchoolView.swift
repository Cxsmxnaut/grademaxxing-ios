import GrademaxxingCore
import SwiftUI

struct SchoolView: View {
  @Bindable var model: AppModel
  var body: some View {
    List {
      if model.isDemo {
        Section { NoticeView(text: "Demo · All school records are invented.", symbol: "sparkles") }
      }
      Section("School records") {
        NavigationLink {
          DocumentsView(model: model)
        } label: {
          Label("Documents", systemImage: "doc.text")
        }
        .accessibilityIdentifier("school.documents")
        NavigationLink {
          MailView(model: model)
        } label: {
          Label("Mail", systemImage: "envelope")
        }
        .accessibilityIdentifier("school.mail")
        NavigationLink {
          AttendanceView(model: model)
        } label: {
          Label("Attendance", systemImage: "checkmark.circle")
        }
        .accessibilityIdentifier("school.attendance")
        NavigationLink {
          SchoolCalendarView(model: model)
        } label: {
          Label("Calendar", systemImage: "calendar")
        }
        .accessibilityIdentifier("school.calendar")
        NavigationLink {
          ScheduleView(model: model)
        } label: {
          Label("Schedule", systemImage: "clock")
        }
        .accessibilityIdentifier("school.schedule")
        NavigationLink {
          ProfileView(model: model)
        } label: {
          Label("Student profile", systemImage: "person.text.rectangle")
        }
        .accessibilityIdentifier("school.profile")
      }
      Section {
        Text("School records are read-only. Contact your school if a record needs to be corrected.")
          .font(.footnote).foregroundStyle(.secondary)
      }
    }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("School")
  }
}

struct RecordScreen<Value: Sendable, Content: View>: View {
  let model: AppModel
  let store: RecordStore<Value>
  let emptyTitle: String
  let reload: () async -> Void
  @ViewBuilder let content: (Value) -> Content
  @State private var showReconnect = false
  var body: some View {
    VStack(spacing: 0) {
      if model.isDemo { NoticeView(text: "Synthetic demo records", symbol: "sparkles").padding(12) }
      if model.needsReconnect {
        Button("Reconnect to StudentVUE") { showReconnect = true }.buttonStyle(.borderedProminent)
          .padding(12)
      }
      if let error = store.error {
        NoticeView(
          text: error + (store.value == nil ? "" : " Showing your last successful refresh."),
          symbol: "exclamationmark.circle"
        )
        .padding(.horizontal, 12).padding(.bottom, 8)
      }
      if let value = store.value {
        content(value)
      } else if store.isLoading {
        LoadingView(
          title: "Loading school records", detail: "Retrieving the records available in StudentVUE."
        )
      } else {
        ContentUnavailableView {
          Label(emptyTitle, systemImage: "doc.text.magnifyingglass")
        } description: {
          Text(
            model.needsReconnect
              ? "Reconnect to load school records." : "Try loading your records again.")
        } actions: {
          Button(model.needsReconnect ? "Reconnect" : "Try again") {
            if model.needsReconnect { showReconnect = true } else { Task { await reload() } }
          }.buttonStyle(.borderedProminent)
        }
      }
    }.background(Theme.background).refreshable { await reload() }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            Task { await reload() }
          } label: {
            if store.isLoading {
              ProgressView().accessibilityLabel("Loading records")
            } else {
              Label("Refresh records", systemImage: "arrow.clockwise")
            }
          }.disabled(store.isLoading || model.needsReconnect)
        }
      }.sheet(isPresented: $showReconnect) { ReconnectView(model: model) }
  }
}

struct ScheduleView: View {
  @Bindable var model: AppModel
  var body: some View {
    RecordScreen(
      model: model, store: model.schedule, emptyTitle: "Schedule could not load",
      reload: { await model.loadSchedule(force: true) }
    ) { schedule in
      List {
        Section {
          if let date = SchoolDate(iso: schedule.date) {
            Text(date.localDate.formatted(date: .complete, time: .omitted)).font(.headline)
          } else {
            Text("Schedule date not available").foregroundStyle(.secondary)
          }
          if schedule.classes.isEmpty {
            Text("No classes are listed for this date.").foregroundStyle(.secondary)
          }
        }
        ForEach(Array(schedule.classes.enumerated()), id: \.offset) { _, item in
          Section(item.period.isEmpty ? "Class" : "Period \(item.period)") {
            Text(item.courseTitle).font(.headline)
            if !item.teacher.isEmpty { Label(item.teacher, systemImage: "person") }
            if !item.room.isEmpty { Label(item.room, systemImage: "mappin.and.ellipse") }
            if !item.startTime.isEmpty || !item.endTime.isEmpty {
              Label(
                [item.startTime, item.endTime].filter { !$0.isEmpty }.joined(separator: " – "),
                systemImage: "clock")
            }
            if !item.schoolName.isEmpty {
              Text(item.schoolName).font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }.scrollContentBackground(.hidden)
    }.navigationTitle("Schedule").inlineTitle()
      .task(id: model.schoolSessionKey) { await model.loadSchedule() }
  }
}

struct ProfileView: View {
  @Bindable var model: AppModel
  var body: some View {
    RecordScreen(
      model: model, store: model.profile, emptyTitle: "Profile could not load",
      reload: { await model.loadProfile(force: true) }
    ) { profile in
      Form {
        Section {
          Text(profile.name.isEmpty ? "Student profile" : profile.name).font(.title2.bold())
          if !profile.grade.isEmpty { LabeledContent("Grade", value: profile.grade) }
          if !profile.permId.isEmpty { LabeledContent("Student ID", value: profile.permId) }
        }
        Section("StudentVUE information") {
          if profile.fields.isEmpty {
            Text("No additional information is available.").foregroundStyle(.secondary)
          }
          ForEach(profile.fields.keys.sorted(), id: \.self) { field in
            LabeledContent(field) {
              Text(profile.fields[field] ?? "").multilineTextAlignment(.trailing).textSelection(
                .enabled)
            }
          }
        }
      }.scrollContentBackground(.hidden)
    }.navigationTitle("Student profile").inlineTitle()
      .task(id: model.schoolSessionKey) { await model.loadProfile() }
  }
}
