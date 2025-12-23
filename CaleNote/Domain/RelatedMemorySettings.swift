import Foundation

struct RelatedMemorySettings {
    var sameDayEnabled: Bool = true        // 同じ日（MMDD一致）
    var sameWeekdayEnabled: Bool = false   // 同じ週の同じ曜日
    var sameHolidayEnabled: Bool = false   // 同じ祝日
    var holidayRegion: String = "JP"       // 祝日判定の地域

    private static let sameDayKey = "RelatedMemory.SameDay"
    private static let sameWeekdayKey = "RelatedMemory.SameWeekday"
    private static let sameHolidayKey = "RelatedMemory.SameHoliday"
    private static let holidayRegionKey = "RelatedMemory.HolidayRegion"

    static func load() -> RelatedMemorySettings {
        let defaults = UserDefaults.standard
        return RelatedMemorySettings(
            sameDayEnabled: defaults.object(forKey: sameDayKey) as? Bool ?? true,
            sameWeekdayEnabled: defaults.bool(forKey: sameWeekdayKey),
            sameHolidayEnabled: defaults.bool(forKey: sameHolidayKey),
            holidayRegion: defaults.string(forKey: holidayRegionKey) ?? "JP"
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(sameDayEnabled, forKey: Self.sameDayKey)
        defaults.set(sameWeekdayEnabled, forKey: Self.sameWeekdayKey)
        defaults.set(sameHolidayEnabled, forKey: Self.sameHolidayKey)
        defaults.set(holidayRegion, forKey: Self.holidayRegionKey)
    }

    var enabledConditionsText: String {
        var conditions: [String] = []
        if sameDayEnabled { conditions.append("同日") }
        if sameWeekdayEnabled { conditions.append("同週同曜") }
        if sameHolidayEnabled { conditions.append("同祝日") }
        return conditions.isEmpty ? "なし" : conditions.joined(separator: "・")
    }

    var hasAnyEnabled: Bool {
        sameDayEnabled || sameWeekdayEnabled || sameHolidayEnabled
    }
}
