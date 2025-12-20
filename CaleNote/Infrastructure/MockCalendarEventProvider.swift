import Foundation

struct MockCalendarEvent {
  let id: String
  let title: String
  let startDate: Date
}

enum MockCalendarEventProvider {
  static func fetch() -> [MockCalendarEvent] {
    [
      MockCalendarEvent(
        id: "event-1",
        title: "チームMTG",
        startDate: Date().addingTimeInterval(-3600)
      ),
      MockCalendarEvent(
        id: "event-2",
        title: "設計レビュー",
        startDate: Date().addingTimeInterval(7200)
      ),
    ]
  }
}