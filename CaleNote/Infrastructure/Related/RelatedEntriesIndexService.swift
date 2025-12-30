import Combine
import Foundation
import SwiftData

/// 関連エントリー用のインデックスサービス
@MainActor
final class RelatedEntriesIndexService: ObservableObject {
    struct RelatedSections {
        let sameMonthDay: [ScheduleEntry]
        let sameWeekdayInWeek: [ScheduleEntry]
        let sameHoliday: (holiday: Holiday, entries: [ScheduleEntry])?

        var isEmpty: Bool {
            sameMonthDay.isEmpty && sameWeekdayInWeek.isEmpty && sameHoliday == nil
        }
    }

    private struct EntryKeys {
        let monthDay: String
        let weekDay: String
        let holiday: String?
    }

    @Published private(set) var isReady = false

    private var monthDayIndex: [String: Set<ObjectIdentifier>] = [:]
    private var weekDayIndex: [String: Set<ObjectIdentifier>] = [:]
    private var holidayIndex: [String: Set<ObjectIdentifier>] = [:]
    private var entryCache: [ObjectIdentifier: ScheduleEntry] = [:]
    private var entryKeys: [ObjectIdentifier: EntryKeys] = [:]

    private let holidayCalendar = HolidayCalendar()

    func rebuildIndex(modelContext: ModelContext) {
        do {
            let descriptor = FetchDescriptor<ScheduleEntry>()
            let entries = try modelContext.fetch(descriptor)
            rebuildIndex(entries: entries)
        } catch {
            isReady = false
        }
    }

    func rebuildIndex(entries: [ScheduleEntry]) {
        monthDayIndex.removeAll()
        weekDayIndex.removeAll()
        holidayIndex.removeAll()
        entryCache.removeAll()
        entryKeys.removeAll()

        for entry in entries {
            indexEntry(entry)
        }
        isReady = true
    }

    func indexEntry(_ entry: ScheduleEntry) {
        let id = ObjectIdentifier(entry)
        entryCache[id] = entry

        let keys = buildKeys(for: entry)
        entryKeys[id] = keys

        monthDayIndex[keys.monthDay, default: []].insert(id)
        weekDayIndex[keys.weekDay, default: []].insert(id)
        if let holidayKey = keys.holiday {
            holidayIndex[holidayKey, default: []].insert(id)
        }
    }

    func updateEntry(_ entry: ScheduleEntry) {
        let id = ObjectIdentifier(entry)
        if let oldKeys = entryKeys[id] {
            removeFromIndex(id: id, keys: oldKeys)
        }
        indexEntry(entry)
    }

    func removeEntry(_ entry: ScheduleEntry) {
        let id = ObjectIdentifier(entry)
        if let oldKeys = entryKeys[id] {
            removeFromIndex(id: id, keys: oldKeys)
        }
        entryCache.removeValue(forKey: id)
        entryKeys.removeValue(forKey: id)
    }

    func relatedEntries(for entry: ScheduleEntry) -> RelatedSections {
        let id = ObjectIdentifier(entry)
        let keys = buildKeys(for: entry)

        let sameMonthDay = entries(for: keys.monthDay, in: monthDayIndex, excluding: id)
        let sameWeekday = entries(for: keys.weekDay, in: weekDayIndex, excluding: id)

        let holiday: Holiday? = {
            guard let holidayKey = keys.holiday else { return nil }
            return holidayCalendar.holiday(for: entry.startAt)
        }()
        let sameHolidayEntries: [ScheduleEntry] = {
            guard let holidayKey = keys.holiday else { return [] }
            return entries(for: holidayKey, in: holidayIndex, excluding: id)
        }()

        let holidaySection: (holiday: Holiday, entries: [ScheduleEntry])? = {
            guard let holiday, !sameHolidayEntries.isEmpty else { return nil }
            return (holiday: holiday, entries: sameHolidayEntries)
        }()

        return RelatedSections(
            sameMonthDay: sortedEntries(sameMonthDay),
            sameWeekdayInWeek: sortedEntries(sameWeekday),
            sameHoliday: holidaySection
        )
    }

    // MARK: - Helpers

    private func buildKeys(for entry: ScheduleEntry) -> EntryKeys {
        let monthDay = monthDayKey(for: entry.startAt)
        let weekDay = weekDayKey(for: entry.startAt)
        let holidayKey = holidayCalendar.holiday(for: entry.startAt)?.id
        return EntryKeys(monthDay: monthDay, weekDay: weekDay, holiday: holidayKey)
    }

    private func monthDayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.month, .day], from: date)
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%02d%02d", month, day)
    }

    private func weekDayKey(for date: Date, calendar: Calendar = .current) -> String {
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let weekday = calendar.component(.weekday, from: date)
        return String(format: "%02d-%d", weekOfYear, weekday)
    }

    private func entries(
        for key: String,
        in index: [String: Set<ObjectIdentifier>],
        excluding excludedId: ObjectIdentifier
    ) -> [ScheduleEntry] {
        guard let ids = index[key] else { return [] }
        return ids.compactMap { id in
            guard id != excludedId else { return nil }
            return entryCache[id]
        }
    }

    private func removeFromIndex(id: ObjectIdentifier, keys: EntryKeys) {
        monthDayIndex[keys.monthDay]?.remove(id)
        weekDayIndex[keys.weekDay]?.remove(id)
        if let holidayKey = keys.holiday {
            holidayIndex[holidayKey]?.remove(id)
        }
    }

    private func sortedEntries(_ entries: [ScheduleEntry]) -> [ScheduleEntry] {
        entries.sorted { $0.startAt > $1.startAt }
    }
}
