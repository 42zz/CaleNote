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
        modelContext: ModelContext
    ) throws -> [RelatedMemoryItem] {

        guard settings.hasAnyEnabled else { return [] }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)

        guard let currentYear = components.year,
              let currentMonth = components.month,
              let currentDay = components.day else {
            return []
        }

        var matchedEvents: [String: (ArchivedCalendarEvent, Set<RelatedMemoryItem.MatchReason>)] = [:]

        // 1. 同じ日（MMDD一致）
        if settings.sameDayEnabled {
            let monthDayKey = currentMonth * 100 + currentDay
            let sameDayEvents = try fetchEventsByMonthDay(
                monthDayKey: monthDayKey,
                currentYear: currentYear,
                modelContext: modelContext
            )

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
                modelContext: modelContext
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
                    modelContext: modelContext
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
        modelContext: ModelContext
    ) throws -> [ArchivedCalendarEvent] {
        // startMonthDayKeyがオプショナルになったため、nilの値も含めて検索
        // その後、computedMonthDayKeyでフィルタリング
        let descriptor = FetchDescriptor<ArchivedCalendarEvent>()
        let allEvents = try modelContext.fetch(descriptor)

        // 同じ年月日を除外し、monthDayKeyに一致するものをフィルタ
        let calendar = Calendar.current
        return allEvents.filter { event in
            // computedMonthDayKeyを使用して比較
            guard event.computedMonthDayKey == monthDayKey else { return false }

            // 年が異なる場合のみ含める（同じ年の同じ月日は除外）
            let eventYear = calendar.component(.year, from: event.start)
            return eventYear != currentYear
        }
    }

    private func fetchEventsBySameWeekday(
        date: Date,
        currentYear: Int,
        modelContext: ModelContext
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
            results.append(contentsOf: events)
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
            results.append(contentsOf: events)
        }

        return results
    }

    private func fetchEventsByHoliday(
        holidayId: String,
        currentYear: Int,
        modelContext: ModelContext
    ) throws -> [ArchivedCalendarEvent] {
        let predicate = #Predicate<ArchivedCalendarEvent> { event in
            event.holidayId == holidayId
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        let allEvents = try modelContext.fetch(descriptor)

        // 同じ年を除外（同じ祝日で年が異なる場合のみ含める）
        let calendar = Calendar.current
        return allEvents.filter { event in
            let eventYear = calendar.component(.year, from: event.start)
            return eventYear != currentYear
        }
    }
}
