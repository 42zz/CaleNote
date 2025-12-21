import Foundation

enum SyncSettings {
  private static let pastDaysKey = "syncWindowPastDays"
  private static let futureDaysKey = "syncWindowFutureDays"

  static let defaultPastDays = 30
  static let defaultFutureDays = 30

  static func pastDays() -> Int {
    let v = UserDefaults.standard.integer(forKey: pastDaysKey)
    return v == 0 ? defaultPastDays : v
  }

  static func futureDays() -> Int {
    let v = UserDefaults.standard.integer(forKey: futureDaysKey)
    return v == 0 ? defaultFutureDays : v
  }

  static func save(pastDays: Int, futureDays: Int) {
    UserDefaults.standard.set(max(1, pastDays), forKey: pastDaysKey)
    UserDefaults.standard.set(max(1, futureDays), forKey: futureDaysKey)
  }

  static func windowDates(from now: Date = Date()) -> (timeMin: Date, timeMax: Date) {
    let cal = Calendar.current
    let timeMin = cal.date(byAdding: .day, value: -pastDays(), to: now) ?? now
    let timeMax = cal.date(byAdding: .day, value: futureDays(), to: now) ?? now
    return (timeMin, timeMax)
  }
}
