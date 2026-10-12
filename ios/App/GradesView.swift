import GrademaxxingCore
import SwiftUI

struct GradesView: View {
  @Bindable var model: AppModel
  @State private var showReconnect = false
  var body: some View {
    Group {
      if let book = model.gradebook {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 18) {
            if model.isDemo {
              NoticeView(
                text: "Demo · All grades and assignments are invented.", symbol: "sparkles")
            }
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text("OFFICIAL GRADES").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(book.selectedPeriod.name).font(.title2.bold())
              }
              Spacer()
              if model.isWorking { ProgressView().accessibilityLabel("Refreshing grades") }
            }
            if book.periods.count > 1 {
              Picker(
                "Reporting period",
                selection: Binding(
                  get: { book.selectedPeriod.index },
                  set: { value in
                    Task { await model.selectPeriod(value) }
                  })
              ) {
                ForEach(book.periods) { Text($0.name).tag($0.index) }
              }.pickerStyle(.menu).disabled(model.isWorking || model.needsReconnect)
                .accessibilityIdentifier("grades.period")
            }
            if model.needsReconnect {
              NoticeView(
                text: "StudentVUE needs you to reconnect. These grades are from your last refresh.",
                symbol: "wifi.exclamationmark")
              Button("Reconnect to StudentVUE") { showReconnect = true }.buttonStyle(
                .borderedProminent)
            } else if let message = model.message {
              NoticeView(
                text: "\(message) Showing your last successful refresh.",
                symbol: "exclamationmark.circle")
            }
            if book.courses.isEmpty {
              ContentUnavailableView(
                "No grades yet", systemImage: "graduationcap",
                description: Text("There are no courses in this reporting period."))
            }
            ForEach(book.courses) { course in
              NavigationLink {
                CourseView(course: course, detailed: book.detailed, isDemo: model.isDemo)
              } label: {
                CourseRow(course: course)
              }
              .buttonStyle(.plain).accessibilityIdentifier("course.\(course.wireID)")
            }
            if let updated = model.lastUpdated {
              Text(
                "Updated \(updated.formatted(date: .omitted, time: .shortened)) · Pull to refresh"
              )
              .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
          }.padding(20).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }.refreshable { await model.refresh() }
      } else if model.isWorking {
        LoadingView(
          title: "Loading your grades",
          detail: "StudentVUE can take a moment to load complete course details.")
      } else {
        ContentUnavailableView {
          Label("Grades could not load", systemImage: "wifi.exclamationmark")
        } description: {
          Text(model.message ?? "Try refreshing your school records.")
        } actions: {
          Button(model.needsReconnect ? "Reconnect" : "Try again") {
            if model.needsReconnect { showReconnect = true } else { Task { await model.refresh() } }
          }.buttonStyle(.borderedProminent)
        }
      }
    }.background(Theme.background).navigationTitle("Grades")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            Task { await model.refresh() }
          } label: {
            Label("Refresh grades", systemImage: "arrow.clockwise")
          }
          .disabled(model.isWorking || model.needsReconnect).accessibilityIdentifier(
            "grades.refresh")
        }
      }
      .sheet(isPresented: $showReconnect) { ReconnectView(model: model) }
  }
}

private struct CourseRow: View {
  let course: Course
  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        Text(course.title).font(.headline).foregroundStyle(.primary)
        Text(
          [
            course.period.isEmpty ? nil : "Period \(course.period)",
            course.teacher.isEmpty ? nil : course.teacher,
          ]
          .compactMap { $0 }.joined(separator: " · ")
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 4) {
        Text(course.officialMark.isEmpty ? "—" : course.officialMark)
          .font(.title2.bold()).foregroundStyle(Theme.gradeColor(course.officialPercent))
        if let percent = course.officialPercent {
          Text("\(percent.formatted(.number.precision(.fractionLength(0...2))))%")
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
      }
      Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        .accessibilityHidden(true)
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .accessibilityElement(children: .combine)
  }
}

struct ReconnectView: View {
  @Bindable var model: AppModel
  @Environment(\.dismiss) private var dismiss
  @State private var password = ""
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Reconnect to StudentVUE").font(.title2.bold())
          Text(
            "Enter your password to refresh your school records. Your district and username are already saved with your protected session."
          )
          .foregroundStyle(.secondary)
          SecureField("StudentVUE password", text: $password).textContentType(.password)
            .accessibilityIdentifier("reconnect.password")
        }
        if let message = model.message { Section { Text(message).foregroundStyle(.secondary) } }
        Button {
          let secret = password
          password = ""
          Task {
            await model.reconnect(password: secret)
            if !model.needsReconnect { dismiss() }
          }
        } label: {
          HStack {
            if model.isWorking { ProgressView() }
            Text("Reconnect")
          }
        }.disabled(password.isEmpty || model.isWorking)
      }.navigationTitle("Reconnect").inlineTitle()
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }.presentationDetents([.medium, .large]).privacyShield()
  }
}
