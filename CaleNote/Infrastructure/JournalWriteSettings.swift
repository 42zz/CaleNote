import Foundation

enum JournalWriteSettings {
  private static let writeCalendarIdKey = "journalWriteCalendarId"

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
}
