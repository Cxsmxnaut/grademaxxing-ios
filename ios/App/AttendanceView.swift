import GrademaxxingCore
import SwiftUI

struct AttendanceView: View {
  @Bindable var model: AppModel
  @State private var filter = "All"
  var body: some View {
    RecordScreen(
      model: model, store: model.attendance, emptyTitle: "Attendance could not load",
      reload: { await model.loadAttendance(force: true) }
    ) { book in
      List {
        Section {
          if !book.schoolName.isEmpty { Text(book.schoolName).font(.headline) }
          Picker("Attendance status", selection: $filter) {
            Text("All recorded days").tag("All")
            ForEach(AttendanceStatus.allCases, id: \.rawValue) {
              Text($0.rawValue).tag($0.rawValue)
            }
          }.pickerStyle(.menu).accessibilityIdentifier("attendance.filter")
          Text("Only days reported by StudentVUE appear here. An unlisted day is not an absence.")
            .font(.footnote).foregroundStyle(.secondary)
        }
        Section("Recorded days") {
          let records = book.records.filter { filter == "All" || $0.status.rawValue == filter }
          if records.isEmpty { Text("No records match this filter.").foregroundStyle(.secondary) }
          ForEach(records) { record in
            NavigationLink {
              AttendanceDetailView(record: record)
            } label: {
              HStack(alignment: .top, spacing: 12) {
                Image(systemName: record.status.symbol).foregroundStyle(record.status.tone)
                  .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                  Text(record.date.localDate.formatted(date: .abbreviated, time: .omitted)).font(
                    .headline)
                  Text(record.reason.isEmpty ? record.status.rawValue : record.reason).font(
                    .caption
                  ).foregroundStyle(.secondary)
                }
                Spacer()
                Text(record.status.rawValue).font(.caption.weight(.semibold)).foregroundStyle(
                  record.status.tone)
              }.padding(.vertical, 4)
            }.accessibilityIdentifier("attendance.record.\(record.date.iso)")
          }
        }
        if !book.courseTotals.isEmpty {
          Section("Official course totals") {
            ForEach(Array(book.courseTotals.enumerated()), id: \.offset) { _, total in
              DisclosureGroup(total.course) {
                totalRow("Present", total.present)
                totalRow("Tardy", total.tardy)
                totalRow("Absent", total.absent)
                totalRow("Excused", total.excused)
                totalRow("Unexcused", total.unexcused)
              }
            }
          }
        }
      }.scrollContentBackground(.hidden)
    }.navigationTitle("Attendance").inlineTitle()
      .task(id: model.schoolSessionKey) { await model.loadAttendance() }
  }
  private func totalRow(_ label: String, _ count: Int?) -> some View {
    LabeledContent(label, value: count.map(String.init) ?? "Unavailable")
  }
}

private struct AttendanceDetailView: View {
  let record: AttendanceRecord
  var body: some View {
    Form {
      Section {
        Text(record.date.localDate.formatted(date: .complete, time: .omitted)).font(.headline)
        Label(record.status.rawValue, systemImage: record.status.symbol).foregroundStyle(
          record.status.tone)
        if !record.reason.isEmpty { Text(record.reason) }
      }
      Section("Period records") {
        if record.periods.isEmpty {
          Text("StudentVUE provided a daily record without period details.").foregroundStyle(
            .secondary)
        }
        ForEach(Array(record.periods.enumerated()), id: \.offset) { _, period in
          VStack(alignment: .leading, spacing: 8) {
            Text(
              period.course.isEmpty
                ? (period.number.isEmpty ? "School day" : "Period \(period.number)") : period.course
            ).font(.headline)
            if !period.status.isEmpty { Text(period.status) }
            if !period.reason.isEmpty {
              Text(period.reason).font(.subheadline).foregroundStyle(.secondary)
            }
          }.padding(.vertical, 4)
        }
      }
    }.navigationTitle("Attendance record").inlineTitle()
  }
}

extension AttendanceStatus {
  var symbol: String {
    switch self {
    case .present: "checkmark.circle.fill"
    case .absent: "xmark.circle.fill"
    case .tardy: "clock.fill"
    case .excused: "checkmark.shield.fill"
    case .activity: "figure.walk"
    case .unknown: "questionmark.circle"
    }
  }
  var tone: Color {
    switch self {
    case .present: Theme.success
    case .absent, .tardy: Theme.warning
    case .excused, .activity: Theme.accent
    case .unknown: .secondary
    }
  }
}
