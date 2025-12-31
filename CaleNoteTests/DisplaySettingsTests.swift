import Foundation
import Testing
@testable import CaleNote

struct DisplaySettingsTests {
    private let key = "displayWeekStartDay"

    @Test func weekStartDayDefaultsToMondayWhenUnset() {
        UserDefaults.standard.removeObject(forKey: key)
        #expect(DisplaySettings.weekStartDay() == DisplaySettings.defaultWeekStartDay)
    }

    @Test func weekStartDayPersistsValue() {
        UserDefaults.standard.removeObject(forKey: key)
        DisplaySettings.saveWeekStartDay(0)
        #expect(DisplaySettings.weekStartDay() == 0)
    }

    @Test func weekStartDayNameUsesKnownLabels() {
        #expect(DisplaySettings.weekStartDayName(0) == "日曜日")
        #expect(DisplaySettings.weekStartDayName(1) == "月曜日")
    }
}
