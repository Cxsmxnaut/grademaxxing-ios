import Charts
import GrademaxxingCore
import SwiftUI

struct CourseView: View {
  let course: Course
  let detailed: Bool
  let isDemo: Bool
  @State private var query = ""
  @State private var filter = "All"
  @State private var showWhatIf = false
  @State private var showAssignmentPlanner = false
  private var assignments: [Assignment] {
    course.assignments.filter { item in
      let matches =
        query.isEmpty || item.title.localizedCaseInsensitiveContains(query)
        || item.category.localizedCaseInsensitiveContains(query)
      let graded = item.isGraded
      return matches && (filter == "All" || (filter == "Graded" ? graded : !graded))
    }
  }
  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 12) {
          Text(isDemo ? "DEMO OFFICIAL MARK" : "OFFICIAL STUDENTVUE MARK").font(
            .caption.weight(.semibold)
          ).foregroundStyle(.secondary)
          HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(course.officialMark.isEmpty ? "—" : course.officialMark).font(.largeTitle.bold())
            if let percent = course.officialPercent {
              Text("\(percent.formatted(.number.precision(.fractionLength(0...2))))%")
                .font(.title.monospacedDigit())
                .accessibilityIdentifier("course.officialPercent")
            }
          }.foregroundStyle(Theme.gradeColor(course.officialPercent))
          Text([course.teacher, course.room].filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
      }.listRowBackground(Theme.surface)
      if !detailed {
        Section {
          Text(
            "This response includes marks only. Refresh the gradebook to load assignment details."
          ).foregroundStyle(.secondary)
        }
      }
      if !course.categories.isEmpty {
        Section("Categories") {
          ForEach(Array(course.categories.enumerated()), id: \.offset) { _, category in
            LabeledContent(category.name) {
              VStack(alignment: .trailing, spacing: 4) {
                if let weight = category.weight { Text("\(weight.formatted())% weight") }
                if let earned = category.earned, let possible = category.possible {
                  Text("\(earned.formatted()) / \(possible.formatted()) points").font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }.listRowBackground(Theme.surface)
          Button {
            showWhatIf = true
          } label: {
            Label("Explore a what-if", systemImage: "slider.horizontal.3")
          }
          .disabled(!detailed).accessibilityIdentifier("course.whatif")
          .listRowBackground(Theme.surface)
        }
      }
      if detailed {
        Section {
          Button("Plan assignment scores", systemImage: "pencil.and.list.clipboard") {
            showAssignmentPlanner = true
          }.accessibilityIdentifier("course.assignmentPlanner")
        }.listRowBackground(Theme.surface)
        let trend = GradeSimulation(course: course).trend
        if !trend.isEmpty {
          Section("Estimated assignment trend") {
            Chart(trend) { point in
              LineMark(
                x: .value("Date", point.date.localDate), y: .value("Percentage", point.percentage)
              )
              .foregroundStyle(Theme.accent)
              PointMark(
                x: .value("Date", point.date.localDate), y: .value("Percentage", point.percentage)
              )
              .foregroundStyle(Theme.accent)
              .accessibilityLabel(point.assignments.joined(separator: ", "))
              .accessibilityValue("\(point.date.iso), \(point.percentage.formatted()) percent")
            }.chartYScale(domain: GradeSimulation.chartDomain(trend.map(\.percentage)))
              .frame(height: 180).accessibilityIdentifier("course.trend")
            Text(
              "Calculated from available assignment dates and anchored to the latest official mark. This is an estimate of past grades."
            )
            .font(.footnote).foregroundStyle(.secondary)
          }.listRowBackground(Theme.surface)
        }
      }
      Section {
        Picker("Assignment filter", selection: $filter) {
          Text("All").tag("All")
          Text("Graded").tag("Graded")
          Text("Ungraded").tag("Ungraded")
        }.pickerStyle(.segmented).listRowBackground(Theme.surface)
        if assignments.isEmpty {
          Text(query.isEmpty ? "No assignments to show." : "No matching assignments.")
            .foregroundStyle(.secondary)
        }
        ForEach(assignments) { assignment in
          NavigationLink {
            AssignmentView(assignment: assignment)
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Text(assignment.title).font(.headline)
              HStack(alignment: .top) {
                Text(
                  [
                    assignment.category,
                    assignment.dueDate.isEmpty ? nil : "Due \(assignment.dueDate)",
                  ]
                  .compactMap { $0 }.joined(separator: " · "))
                Spacer()
                Text(assignment.displayScore.isEmpty ? "No score" : assignment.displayScore)
                  .multilineTextAlignment(.trailing)
              }.font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
          }.listRowBackground(Theme.surface)
            .accessibilityIdentifier("assignment.\(assignment.id)")
        }
      } header: {
        Text("Assignments · \(assignments.count)")
      }
    }.scrollContentBackground(.hidden).background(Theme.background)
      .navigationTitle(course.title).inlineTitle()
      .searchable(text: $query, prompt: "Search assignments")
      .sheet(isPresented: $showWhatIf) { WhatIfView(course: course) }
      .sheet(isPresented: $showAssignmentPlanner) { AssignmentPlannerView(course: course) }
  }
}

private struct AssignmentView: View {
  let assignment: Assignment
  var body: some View {
    Form {
      Section("Assignment") {
        Text(assignment.title).font(.headline)
        LabeledContent("Category", value: assignment.category)
        if !assignment.dueDate.isEmpty { LabeledContent("Due", value: assignment.dueDate) }
      }
      Section("Official score") {
        Text(assignment.displayScore.isEmpty ? "No score published" : assignment.displayScore).font(
          .title2.bold())
        if let percent = assignment.publishedPercent {
          LabeledContent("Published percentage", value: "\(percent.formatted())%")
        }
        if let earned = assignment.pointsEarned, let possible = assignment.pointsPossible {
          LabeledContent(
            "Weighted points", value: "\(earned.formatted()) / \(possible.formatted())")
        }
        if assignment.calculationUnavailable {
          Text(
            "StudentVUE has not provided enough information to calculate this assignment's weighted scale."
          ).font(.footnote).foregroundStyle(.secondary)
        }
      }
      if !assignment.notes.isEmpty { Section("Teacher notes") { Text(assignment.notes) } }
      if !assignment.description.isEmpty { Section("Description") { Text(assignment.description) } }
    }.navigationTitle("Assignment").inlineTitle().privacySensitive()
  }
}

struct WhatIfView: View {
  let course: Course
  @Environment(\.dismiss) private var dismiss
  @State private var category = ""
  @State private var earned = "90"
  @State private var possible = "100"
  private var projection: Projection? {
    guard let score = Double(earned), let total = Double(possible) else { return nil }
    return GradePlanning.project(course: course, category: category, earned: score, possible: total)
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Add a hypothetical assignment").font(.headline)
          Text(
            "A local estimate using the current category totals. This does not change your school records."
          )
          .font(.subheadline).foregroundStyle(.secondary)
          Picker("Category", selection: $category) {
            ForEach(Array(course.categories.enumerated()), id: \.offset) { _, item in
              Text(item.name).tag(item.name)
            }
          }
          TextField("Points earned", text: $earned).decimalInput().accessibilityLabel(
            "Points earned"
          )
          .accessibilityIdentifier("whatif.earned")
          TextField("Points possible", text: $possible).decimalInput().accessibilityLabel(
            "Points possible"
          )
          .accessibilityIdentifier("whatif.possible")
        }
        Section("Local what-if estimate") {
          if let result = projection {
            LabeledContent("Projected percentage") {
              Text("\(result.projected.formatted(.number.precision(.fractionLength(2))))%")
                .accessibilityIdentifier("whatif.projectedPercent")
            }
            .font(.title3.bold()).foregroundStyle(Theme.simulation)
            LabeledContent(
              "Change from calculated baseline",
              value:
                "\(result.change.formatted(.number.precision(.fractionLength(2)))) percentage points"
            )
            if let official = course.officialPercent {
              LabeledContent("Official percentage", value: "\(official.formatted())%")
            }
          } else {
            Text(
              "A reliable estimate is unavailable. Enter valid points, or the category totals may not match the official grade closely enough."
            )
            .foregroundStyle(.secondary)
          }
        }
        Section {
          Text(
            "Assumes a new graded assignment and normalized category weights. Teacher rules, rounding, and grading changes can produce a different result."
          )
          .font(.footnote).foregroundStyle(.secondary)
        }
      }.navigationTitle("What-if").inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear { if category.isEmpty { category = course.categories.first?.name ?? "" } }
        .privacyShield()
    }
  }
}
