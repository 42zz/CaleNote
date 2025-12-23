import Foundation

struct HolidayInfo {
    let holidayId: String
    let displayName: String
}

protocol HolidayProvider {
    var region: String { get }
    func holiday(for date: Date) -> HolidayInfo?
}

// MARK: - Japan Holiday Provider

final class JapanHolidayProvider: HolidayProvider {
    let region = "JP"

    func holiday(for date: Date) -> HolidayInfo? {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }

        // 固定祝日
        if let fixedHoliday = fixedHolidays(month: month, day: day) {
            return fixedHoliday
        }

        // 移動祝日（ハッピーマンデーなど）
        if let movableHoliday = movableHolidays(year: year, month: month, day: day, date: date) {
            return movableHoliday
        }

        // 春分の日・秋分の日（簡易計算）
        if let equinox = equinoxHoliday(year: year, month: month, day: day) {
            return equinox
        }

        return nil
    }

    private func fixedHolidays(month: Int, day: Int) -> HolidayInfo? {
        switch (month, day) {
        case (1, 1):
            return HolidayInfo(holidayId: "JP:NEW_YEAR", displayName: "元日")
        case (2, 11):
            return HolidayInfo(holidayId: "JP:FOUNDATION_DAY", displayName: "建国記念の日")
        case (2, 23):
            return HolidayInfo(holidayId: "JP:EMPEROR_BIRTHDAY", displayName: "天皇誕生日")
        case (4, 29):
            return HolidayInfo(holidayId: "JP:SHOWA_DAY", displayName: "昭和の日")
        case (5, 3):
            return HolidayInfo(holidayId: "JP:CONSTITUTION_DAY", displayName: "憲法記念日")
        case (5, 4):
            return HolidayInfo(holidayId: "JP:GREENERY_DAY", displayName: "みどりの日")
        case (5, 5):
            return HolidayInfo(holidayId: "JP:CHILDREN_DAY", displayName: "こどもの日")
        case (8, 11):
            return HolidayInfo(holidayId: "JP:MOUNTAIN_DAY", displayName: "山の日")
        case (11, 3):
            return HolidayInfo(holidayId: "JP:CULTURE_DAY", displayName: "文化の日")
        case (11, 23):
            return HolidayInfo(holidayId: "JP:LABOR_DAY", displayName: "勤労感謝の日")
        default:
            return nil
        }
    }

    private func movableHolidays(year: Int, month: Int, day: Int, date: Date) -> HolidayInfo? {
        let calendar = Calendar(identifier: .gregorian)
        let weekday = calendar.component(.weekday, from: date)

        // 成人の日（1月第2月曜）
        if month == 1 && weekday == 2 {
            if let nth = nthWeekday(date: date) {
                if nth == 2 {
                    return HolidayInfo(holidayId: "JP:COMING_OF_AGE_DAY", displayName: "成人の日")
                }
            }
        }

        // 海の日（7月第3月曜）
        if month == 7 && weekday == 2 {
            if let nth = nthWeekday(date: date) {
                if nth == 3 {
                    return HolidayInfo(holidayId: "JP:MARINE_DAY", displayName: "海の日")
                }
            }
        }

        // 敬老の日（9月第3月曜）
        if month == 9 && weekday == 2 {
            if let nth = nthWeekday(date: date) {
                if nth == 3 {
                    return HolidayInfo(holidayId: "JP:RESPECT_FOR_AGED_DAY", displayName: "敬老の日")
                }
            }
        }

        // 体育の日→スポーツの日（10月第2月曜）
        if month == 10 && weekday == 2 {
            if let nth = nthWeekday(date: date) {
                if nth == 2 {
                    return HolidayInfo(holidayId: "JP:SPORTS_DAY", displayName: "スポーツの日")
                }
            }
        }

        return nil
    }

    private func equinoxHoliday(year: Int, month: Int, day: Int) -> HolidayInfo? {
        // 春分の日（簡易計算、2000-2099年対応）
        if month == 3 {
            let vernalEquinox = Int(20.8431 + 0.242194 * Double(year - 1980) - Double((year - 1980) / 4))
            if day == vernalEquinox {
                return HolidayInfo(holidayId: "JP:VERNAL_EQUINOX", displayName: "春分の日")
            }
        }

        // 秋分の日（簡易計算、2000-2099年対応）
        if month == 9 {
            let autumnalEquinox = Int(23.2488 + 0.242194 * Double(year - 1980) - Double((year - 1980) / 4))
            if day == autumnalEquinox {
                return HolidayInfo(holidayId: "JP:AUTUMNAL_EQUINOX", displayName: "秋分の日")
            }
        }

        return nil
    }

    private func nthWeekday(date: Date) -> Int? {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.component(.day, from: date)
        return (day - 1) / 7 + 1
    }
}

// MARK: - Holiday Provider Factory

final class HolidayProviderFactory {
    static func provider(for region: String) -> HolidayProvider {
        switch region {
        case "JP":
            return JapanHolidayProvider()
        default:
            // デフォルトはJP
            return JapanHolidayProvider()
        }
    }
}
