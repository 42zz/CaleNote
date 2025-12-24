import Foundation

enum JournalWriteSettings {
  private static let writeCalendarIdKey = "journalWriteCalendarId"
  private static let eventDurationMinutesKey = "journalEventDurationMinutes"

  static func loadWriteCalendarId() -> String? {
    UserDefaults.standard.string(forKey: writeCalendarIdKey)
  }

  static func saveWriteCalendarId(_ calendarId: String?) {
    if let calendarId {
      UserDefaults.standard.set(calendarId, forKey: writeCalendarIdKey)
    } else {
      UserDefaults.standard.removeObject(forKey: writeCalendarIdKey)
    }
  }

  static let defaultEventDurationMinutes = 30

  static func eventDurationMinutes() -> Int {
    let v = UserDefaults.standard.integer(forKey: eventDurationMinutesKey)
    return v == 0 ? defaultEventDurationMinutes : v
  }

  static func saveEventDurationMinutes(_ minutes: Int) {
    UserDefaults.standard.set(max(1, minutes), forKey: eventDurationMinutesKey)
  }
}
