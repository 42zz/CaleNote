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
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        let symbols = formatter.weekdaySymbols
        guard !symbols.isEmpty else { return L10n.tr("weekday.monday") }
        let index = min(max(day, 0), symbols.count - 1)
        return symbols[index]
    }
}
