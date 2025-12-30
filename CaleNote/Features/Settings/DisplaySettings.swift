import Foundation

enum DisplaySettings {
    private static let weekStartDayKey = "displayWeekStartDay"

    // 0 = Sunday, 1 = Monday (default)
    static let defaultWeekStartDay = 1

    static func weekStartDay() -> Int {
        let v = UserDefaults.standard.integer(forKey: weekStartDayKey)
        // 未設定時は0が返るが、日曜日開始も0なので初回チェックが必要
        if UserDefaults.standard.object(forKey: weekStartDayKey) == nil {
            return defaultWeekStartDay
        }
        return v
    }

    static func saveWeekStartDay(_ day: Int) {
        UserDefaults.standard.set(day, forKey: weekStartDayKey)
    }

    static func weekStartDayName(_ day: Int) -> String {
        switch day {
        case 0: return "日曜日"
        case 1: return "月曜日"
        default: return "月曜日"
        }
    }
}
