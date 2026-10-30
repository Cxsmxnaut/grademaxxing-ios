import GrademaxxingCore
import SwiftUI

struct GradesView: View {
  @Bindable var model: AppModel
  var openPlanner: () -> Void = {}
  @State private var showReconnect = false
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var body: some View {
    Group {
      if let book = model.gradebook {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 18) {
            let controls =
              dynamicTypeSize.isAccessibilitySize
              ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
              : AnyLayout(HStackLayout(spacing: 16))
            controls {
              Menu {
                ForEach(book.periods) { period in
                  Button(period.name) { Task { await model.selectPeriod(period.index) } }
                }
              } label: {
                HStack(spacing: 8) {
                  Text(book.selectedPeriod.name).font(.headline)
                  Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
              }.buttonStyle(.plain).disabled(model.isWorking || model.needsReconnect)
                .accessibilityLabel("Reporting period, " + book.selectedPeriod.name)
                .accessibilityIdentifier("grades.period")
              if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
              Button(action: openPlanner) {
                Label("GPA calculator", systemImage: "plus.forwardslash.minus")
                  .font(.subheadline).frame(minWidth: 44, minHeight: 44)
                  .contentShape(Rectangle())
              }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                .accessibilityIdentifier("grades.gpa")
            }
            gpaSummary(book)
            Text("Your classes").font(.title3.bold()).accessibilityAddTraits(.isHeader)
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
              NavigationLink(value: AppRoute.course(course.wireID)) {
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
    }.background(Theme.background).navigationTitle("Gradebook").largeRootTitle()
      .navigationChromeVisible()
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
  private func gpaSummary(_ book: Gradebook) -> some View {
    let entries = GPAPlanning.entries(
      for: book.courses, gradeLevel: Int(model.profile.value?.grade ?? "") ?? 9)
    let summary = GPAPlanning.summary(entries)
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
    return VStack(alignment: .leading, spacing: 16) {
      layout {
        gpaMetric(
          "Unweighted GPA", GPAPlanning.displayValue(summary.unweighted),
          identifier: "grades.unweighted", color: Theme.success)
        gpaMetric(
          "Weighted GPA", GPAPlanning.displayValue(summary.weighted),
          identifier: "grades.weighted", color: Theme.foreground)
      }
      Text("Current-course estimate · Not a transcript GPA")
        .font(.caption).foregroundStyle(Theme.muted)
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
  private func gpaMetric(_ title: String, _ value: String, identifier: String, color: Color)
    -> some View
  {
    VStack(alignment: .leading, spacing: 8) {
      Text(title).font(.subheadline).foregroundStyle(Theme.muted)
      Text(value).font(.largeTitle.bold().monospacedDigit()).foregroundStyle(color)
        .accessibilityIdentifier(identifier)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

}

private struct CourseRow: View {
  let course: Course
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if dynamicTypeSize.isAccessibilitySize {
        HStack(alignment: .firstTextBaseline) {
          grade
          Spacer(minLength: 8)
          percentage
        }
        details
      } else {
        HStack(spacing: 14) {
          grade.frame(width: 42, alignment: .leading)
          details.frame(maxWidth: .infinity, alignment: .leading)
          VStack(alignment: .trailing, spacing: 8) {
            percentage
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
              .foregroundStyle(Theme.tertiary).accessibilityHidden(true)
          }
        }
      }
      if let percent = course.officialPercent { GradeMeter(percent: percent) }
    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .accessibilityElement(children: .ignore).accessibilityLabel(spokenSummary)
  }
  private var grade: some View {
    Text(course.officialMark.isEmpty ? "—" : course.officialMark)
      .font(.title.bold()).foregroundStyle(Theme.gradeColor(course.officialPercent))
  }
  private var percentage: some View {
    Group {
      if let percent = course.officialPercent {
        Text("\(percent.formatted(.number.precision(.fractionLength(0...2))))%")
          .font(.subheadline.weight(.semibold).monospacedDigit())
          .foregroundStyle(Theme.gradeColor(percent))
      } else {
        Text("Not graded").font(.caption).foregroundStyle(Theme.muted)
      }
    }.fixedSize(horizontal: false, vertical: true)
  }
  private var details: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(course.title).font(.headline).foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
      Text(
        [
          course.period.isEmpty ? nil : "Period \(course.period)",
          course.room.isEmpty ? nil : "Room \(course.room)",
        ].compactMap { $0 }.joined(separator: " · ")
      )
      .font(.caption).foregroundStyle(Theme.muted)
      if !course.teacher.isEmpty {
        Text(course.teacher).font(.caption).foregroundStyle(Theme.muted)
      }
    }
  }
  private var spokenSummary: String {
    let grade = course.officialPercent.map { "\($0.formatted()) percent" } ?? "not graded"
    return [
      course.title, "Official grade \(course.officialMark), \(grade)",
      course.period.isEmpty ? nil : "Period \(course.period)",
      course.room.isEmpty ? nil : "Room \(course.room)",
      course.teacher.isEmpty ? nil : course.teacher,
    ].compactMap { $0 }.joined(separator: ", ")
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
          .foregroundStyle(Theme.muted)
          SecureField("StudentVUE password", text: $password).textContentType(.password)
            .accessibilityIdentifier("reconnect.password")
        }.listRowBackground(Theme.surface)
        if let message = model.message {
          Section { Text(message).foregroundStyle(Theme.muted) }.listRowBackground(Theme.surface)
        }
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
        }.disabled(password.isEmpty || model.isWorking).listRowBackground(Theme.surface)
      }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Reconnect")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }.presentationDetents([.medium, .large]).privacyShield()
  }
}
