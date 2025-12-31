import Foundation

/// 簡易的な祝日判定
/// NOTE: 固定日付の祝日のみ扱う。必要に応じて拡張する。
struct Holiday: Hashable, Identifiable {
    let id: String
    let nameKey: String
    let month: Int
    let day: Int

    var localizedName: String {
        L10n.tr(nameKey)
    }
}

struct HolidayCalendar {
    private let holidays: [Holiday] = [
        Holiday(id: "new_years_day", nameKey: "holiday.new_years_day", month: 1, day: 1),
        Holiday(id: "christmas", nameKey: "holiday.christmas", month: 12, day: 25)
    ]

    func holiday(for date: Date, calendar: Calendar = .current) -> Holiday? {
        let components = calendar.dateComponents([.month, .day], from: date)
        guard let month = components.month, let day = components.day else { return nil }
        return holidays.first { $0.month == month && $0.day == day }
    }
}
