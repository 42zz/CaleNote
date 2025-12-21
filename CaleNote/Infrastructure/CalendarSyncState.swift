import Foundation

enum CalendarSyncState {
  private static func key(calendarId: String) -> String {
    "calendarSyncToken:\(calendarId)"
  }

  static func loadSyncToken(calendarId: String) -> String? {
    UserDefaults.standard.string(forKey: key(calendarId: calendarId))
  }

  static func saveSyncToken(_ token: String?, calendarId: String) {
    let k = key(calendarId: calendarId)
    if let token {
      UserDefaults.standard.set(token, forKey: k)
    } else {
      UserDefaults.standard.removeObject(forKey: k)
    }
  }
}
