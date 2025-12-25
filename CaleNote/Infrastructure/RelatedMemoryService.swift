import Foundation
import SwiftData

struct RelatedMemoryItem {
    let event: ArchivedCalendarEvent
    let matchReasons: Set<MatchReason>
    let yearsDifference: Int  // 負の値=過去、正の値=未来、0=今年

    enum MatchReason: String {
        case sameDay = "同日"
        case sameWeekday = "同週同曜"
        case sameHoliday = "同祝日"
    }

    var matchReasonsText: String {
        matchReasons.map { $0.rawValue }.sorted().joined(separator: "・")
    }

    var displayYearText: String {
        if yearsDifference == 0 {
            return "今年"
        } else if yearsDifference < 0 {
            return "\(abs(yearsDifference))年前"
        } else {
            return "\(yearsDifference)年後"
        }
    }
}

@MainActor
final class RelatedMemoryService {

    func findRelatedMemories(
        for date: Date,
        settings: RelatedMemorySettings,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String> = Set()  // 空の場合は全カレンダーを対象
    ) throws -> [RelatedMemoryItem] {

        print("🔍 RelatedMemoryService.findRelatedMemories: 開始 date=\(date) enabledCalendarIds件数=\(enabledCalendarIds.count)")

        guard settings.hasAnyEnabled else {
            print("⚠️ RelatedMemoryService: settings無効")
            return []
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard let currentYear = components.year,
              let currentMonth = components.month,
              let currentDay = components.day else {
            print("⚠️ RelatedMemoryService: 日付コンポーネント取得失敗")
            return []
        }

        print("📅 RelatedMemoryService: targetDate=\(currentYear)/\(currentMonth)/\(currentDay)")
        print("📅 RelatedMemoryService: settings - 同日:\(settings.sameDayEnabled) 同週同曜:\(settings.sameWeekdayEnabled) 同祝日:\(settings.sameHolidayEnabled)")

        var matchedEvents: [String: (ArchivedCalendarEvent, Set<RelatedMemoryItem.MatchReason>)] = [:]

        // 1. 同じ日（MMDD一致）
        if settings.sameDayEnabled {
            let monthDayKey = currentMonth * 100 + currentDay
            print("🔍 RelatedMemoryService: 同日検索開始 monthDayKey=\(monthDayKey)")
            let sameDayEvents = try fetchEventsByMonthDay(
                monthDayKey: monthDayKey,
                currentYear: currentYear,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )
            print("📊 RelatedMemoryService: 同日検索結果 件数=\(sameDayEvents.count)")

            for event in sameDayEvents {
                if var existing = matchedEvents[event.uid] {
                    existing.1.insert(.sameDay)
                    matchedEvents[event.uid] = existing
                } else {
                    matchedEvents[event.uid] = (event, [.sameDay])
                }
            }
        }

        // 2. 同じ週の同じ曜日（ISO週番号）
        if settings.sameWeekdayEnabled {
            let sameWeekdayEvents = try fetchEventsBySameWeekday(
                date: date,
                currentYear: currentYear,
                modelContext: modelContext,
                enabledCalendarIds: enabledCalendarIds
            )

            for event in sameWeekdayEvents {
                if var existing = matchedEvents[event.uid] {
                    existing.1.insert(.sameWeekday)
                    matchedEvents[event.uid] = existing
                } else {
                    matchedEvents[event.uid] = (event, [.sameWeekday])
                }
            }
        }

        // 3. 同じ祝日
        if settings.sameHolidayEnabled {
            let holidayProvider = HolidayProviderFactory.provider(for: settings.holidayRegion)
            if let holidayInfo = holidayProvider.holiday(for: date) {
                let sameHolidayEvents = try fetchEventsByHoliday(
                    holidayId: holidayInfo.holidayId,
                    currentYear: currentYear,
                    modelContext: modelContext,
                    enabledCalendarIds: enabledCalendarIds
                )

                for event in sameHolidayEvents {
                    if var existing = matchedEvents[event.uid] {
                        existing.1.insert(.sameHoliday)
                        matchedEvents[event.uid] = existing
                    } else {
                        matchedEvents[event.uid] = (event, [.sameHoliday])
                    }
                }
            }
        }

        // 変換してソート
        let items = matchedEvents.map { (uid: String, value: (ArchivedCalendarEvent, Set<RelatedMemoryItem.MatchReason>)) in
            let (event, reasons) = value
            let eventYear = calendar.component(.year, from: event.start)
            let yearsDifference = eventYear - currentYear  // 負=過去、正=未来

            return RelatedMemoryItem(
                event: event,
                matchReasons: reasons,
                yearsDifference: yearsDifference
            )
        }

        // 年数でソート（過去の近い順 → 過去の遠い順 → 未来の近い順 → 未来の遠い順）
        return items.sorted { item1, item2 in
            let abs1 = abs(item1.yearsDifference)
            let abs2 = abs(item2.yearsDifference)

            // まず絶対値（距離）でソート
            if abs1 != abs2 {
                return abs1 < abs2
            }
            // 距離が同じなら過去を優先
            return item1.yearsDifference < item2.yearsDifference
        }
    }

    private func fetchEventsByMonthDay(
        monthDayKey: Int,
        currentYear: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) throws -> [ArchivedCalendarEvent] {
        print("🔍 fetchEventsByMonthDay: monthDayKey=\(monthDayKey) currentYear=\(currentYear) enabledCalendarIds件数=\(enabledCalendarIds.count)")

        // 過去20年 + 未来5年の範囲で検索（必要に応じて調整）
        let searchYears = (-20...5).compactMap { offset -> Int? in
            let year = currentYear + offset
            guard year > 0, year != currentYear else { return nil }
            return year
        }

        print("📅 fetchEventsByMonthDay: 検索対象年数=\(searchYears.count)")

        var results: [ArchivedCalendarEvent] = []
        var totalFetched = 0
        var totalFiltered = 0

        for year in searchYears {
            let dayKey = year * 10000 + monthDayKey

            let predicate = #Predicate<ArchivedCalendarEvent> { event in
                event.startDayKey == dayKey
            }
            var descriptor = FetchDescriptor(predicate: predicate)
            descriptor.fetchLimit = 100  // 1日あたりの最大件数を制限

            let events = try modelContext.fetch(descriptor)
            totalFetched += events.count

            // 有効なカレンダーのイベントのみをフィルタリング
            let filteredEvents = events.filter { event in
                enabledCalendarIds.isEmpty || enabledCalendarIds.contains(event.calendarId)
            }
            totalFiltered += filteredEvents.count
            results.append(contentsOf: filteredEvents)
        }

        print("📊 fetchEventsByMonthDay: 合計 fetch件数=\(totalFetched) filter後件数=\(totalFiltered)")

        return results
    }

    private func fetchEventsBySameWeekday(
        date: Date,
        currentYear: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) throws -> [ArchivedCalendarEvent] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let yearForWeek = calendar.component(.yearForWeekOfYear, from: date)
        let weekOfYear = calendar.component(.weekOfYear, from: date)

        // 同じ年月日を除外するため、targetDateのdayKeyを計算
        let targetDateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let targetDayKey = (targetDateComponents.year ?? 0) * 10000
            + (targetDateComponents.month ?? 0) * 100
            + (targetDateComponents.day ?? 0)

        var results: [ArchivedCalendarEvent] = []

        // 過去10年分をチェック
        for pastYear in 1...10 {
            let targetYear = yearForWeek - pastYear

            // 同じ週番号・曜日の日付を計算
            var targetComponents = DateComponents()
            targetComponents.yearForWeekOfYear = targetYear
            targetComponents.weekOfYear = weekOfYear
            targetComponents.weekday = weekday

            guard let targetDate = calendar.date(from: targetComponents) else {
                // その年に該当する週がない場合はスキップ
                continue
            }

            // targetDateのstartDayKeyを計算
            let targetDateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            guard let year = targetDateComponents.year,
                  let month = targetDateComponents.month,
                  let day = targetDateComponents.day else {
                continue
            }

            let dayKey = year * 10000 + month * 100 + day

            // 同じ年月日は除外
            if dayKey == targetDayKey {
                continue
            }

            // startDayKeyで検索
            let predicate = #Predicate<ArchivedCalendarEvent> { event in
                event.startDayKey == dayKey
            }
            let descriptor = FetchDescriptor(predicate: predicate)
            let events = try modelContext.fetch(descriptor)
            
            // 有効なカレンダーのイベントのみをフィルタリング
            let filteredEvents = events.filter { event in
                enabledCalendarIds.isEmpty || enabledCalendarIds.contains(event.calendarId)
            }
            results.append(contentsOf: filteredEvents)
        }

        // 未来10年分をチェック
        for futureYear in 1...10 {
            let targetYear = yearForWeek + futureYear

            // 同じ週番号・曜日の日付を計算
            var targetComponents = DateComponents()
            targetComponents.yearForWeekOfYear = targetYear
            targetComponents.weekOfYear = weekOfYear
            targetComponents.weekday = weekday

            guard let targetDate = calendar.date(from: targetComponents) else {
                // その年に該当する週がない場合はスキップ
                continue
            }

            // targetDateのstartDayKeyを計算
            let targetDateComponents = calendar.dateComponents([.year, .month, .day], from: targetDate)
            guard let year = targetDateComponents.year,
                  let month = targetDateComponents.month,
                  let day = targetDateComponents.day else {
                continue
            }

            let dayKey = year * 10000 + month * 100 + day

            // 同じ年月日は除外
            if dayKey == targetDayKey {
                continue
            }

            // startDayKeyで検索
            let predicate = #Predicate<ArchivedCalendarEvent> { event in
                event.startDayKey == dayKey
            }
            let descriptor = FetchDescriptor(predicate: predicate)
            let events = try modelContext.fetch(descriptor)
            
            // 有効なカレンダーのイベントのみをフィルタリング
            let filteredEvents = events.filter { event in
                enabledCalendarIds.isEmpty || enabledCalendarIds.contains(event.calendarId)
            }
            results.append(contentsOf: filteredEvents)
        }

        return results
    }

    private func fetchEventsByHoliday(
        holidayId: String,
        currentYear: Int,
        modelContext: ModelContext,
        enabledCalendarIds: Set<String>
    ) throws -> [ArchivedCalendarEvent] {
        let predicate = #Predicate<ArchivedCalendarEvent> { event in
            event.holidayId == holidayId
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let allEvents = try modelContext.fetch(descriptor)

        // 同じ年を除外（同じ祝日で年が異なる場合のみ含める）
        // 有効なカレンダーのイベントのみを対象
        let calendar = Calendar.current
        return allEvents.filter { event in
            // 有効なカレンダーのイベントのみを対象
            if !enabledCalendarIds.isEmpty && !enabledCalendarIds.contains(event.calendarId) {
                return false
            }
            
            let eventYear = calendar.component(.year, from: event.start)
            return eventYear != currentYear
        }
    }
}
