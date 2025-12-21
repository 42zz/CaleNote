import Foundation

enum SyncRateLimiter {
  private static let lastSyncAtKey = "lastSyncAt"
  static let minimumIntervalSeconds: TimeInterval = 5

  static func canSync(now: Date = Date()) -> Bool {
    guard let last = UserDefaults.standard.object(forKey: lastSyncAtKey) as? Date else {
      return true
    }
    return now.timeIntervalSince(last) >= minimumIntervalSeconds
  }

  static func remainingSeconds(now: Date = Date()) -> Int {
    guard let last = UserDefaults.standard.object(forKey: lastSyncAtKey) as? Date else {
      return 0
    }
    let remain = minimumIntervalSeconds - now.timeIntervalSince(last)
    return max(0, Int(ceil(remain)))
  }

  static func markSynced(at date: Date = Date()) {
    UserDefaults.standard.set(date, forKey: lastSyncAtKey)
  }
}
