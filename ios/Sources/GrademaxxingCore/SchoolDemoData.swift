import Foundation

/// Invented records only. Each demo resource goes through the production decoder.
public enum SchoolDemoData {
  public static func attendance() throws -> AttendanceBook {
    try AttendanceDecoder.decode(
      Data(
        """
        {
          "_SchoolName": "Synthetic High School",
          "Absences": {"Absence": [
            {"_AbsenceDate":"2026-10-08","_Reason":"Appointment","_Note":"Synthetic excused appointment",
             "Periods":{"Period":[{"_Number":"2","_Name":"Excused","_Reason":"Medical","_Course":"English Honors"}]}},
            {"_AbsenceDate":"2026-10-06","_Reason":"Late arrival","_Note":"Synthetic tardy record",
             "Periods":{"Period":[{"_Number":"1","_Name":"Tardy","_Reason":"Late arrival","_Course":"AP Calculus"}]}}
          ]},
          "DailyRecords":[
            {"Date":"2026-10-09","Status":"present","Reason":"Present"},
            {"Date":"2026-10-08","Status":"excused","Reason":"Medical"},
            {"Date":"2026-10-07","Status":"present","Reason":"Present"},
            {"Date":"2026-10-06","Status":"tardy","Reason":"Late arrival"},
            {"Date":"2026-10-05","Status":"present","Reason":"Present"}
          ],
          "CourseTotals":[
            {"Course":"AP Calculus","Present":28,"Tardy":1,"Absent":0,"Excused":0,"Unexcused":0},
            {"Course":"English Honors","Present":28,"Tardy":0,"Absent":1,"Excused":1,"Unexcused":0}
          ]
        }
        """.utf8))
  }
  public static func calendar(month: SchoolMonth) throws -> SchoolCalendar {
    let events: [[String: String]] = [
      [
        "id": "synthetic-review", "title": "Unit review", "type": "Assignment",
        "date": date(month, day: 7), "time": "", "description": "Invented calendar assignment.",
        "details": "AP Calculus",
      ],
      [
        "id": "synthetic-event", "title": "School showcase", "type": "School event",
        "date": date(month, day: 15), "time": "6:00 PM",
        "description": "A synthetic evening event for the demo.", "details": "Demo auditorium",
      ],
      [
        "id": "synthetic-project", "title": "Upcoming project", "type": "Assignment",
        "date": date(month, day: 16), "time": "", "description": "Invented project deadline.",
        "details": "English Honors",
      ],
    ]
    let data = try JSONSerialization.data(withJSONObject: [
      "startDate": date(month, day: 1), "endDate": month.days.last!.iso, "events": events,
    ])
    return try CalendarDecoder.decode(data, month: month)
  }
  public static func schedule() throws -> SchoolSchedule {
    let classes = DemoData.gradebook().courses.enumerated().map { index, course in
      [
        "period": course.period, "courseTitle": course.title, "teacher": course.teacher,
        "room": "Demo room",
        "startTime": "\(8 + index):00 \(8 + index >= 12 ? "PM" : "AM")",
        "endTime": "\(8 + index):50 \(8 + index >= 12 ? "PM" : "AM")",
        "schoolName": "Synthetic High School", "date": "2026-10-09",
      ]
    }
    return try JSONDecoder().decode(
      SchoolSchedule.self,
      from: JSONSerialization.data(withJSONObject: ["date": "2026-10-09", "classes": classes]))
  }
  public static func profile() throws -> StudentProfile {
    let values: [String: Any] = [
      "name": "Demo Student", "permId": "SYNTHETIC", "grade": "11",
      "fields": [
        "Student Name": "Demo Student", "Grade": "11", "School": "Synthetic High School",
        "Counselor": "Ms. Example",
      ],
    ]
    return try JSONDecoder().decode(
      StudentProfile.self, from: JSONSerialization.data(withJSONObject: values))
  }
  private static func date(_ month: SchoolMonth, day: Int) -> String {
    String(format: "%04d-%02d-%02d", month.year, month.month, day)
  }
}
