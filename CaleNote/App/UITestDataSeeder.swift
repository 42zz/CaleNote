import Foundation
import SwiftData

enum UITestDataSeeder {
    static func seed(modelContext: ModelContext) {
        do {
            let calendarDescriptor = FetchDescriptor<CalendarInfo>()
            let existingCalendars = try modelContext.fetch(calendarDescriptor)
            if existingCalendars.isEmpty {
                let primary = CalendarInfo(
                    calendarId: "ui-test-primary",
                    summary: "UI Test Primary",
                    calendarDescription: "Primary calendar for UI tests",
                    backgroundColor: "#4A90E2",
                    accessRole: CalendarInfo.AccessRole.owner.rawValue,
                    isPrimary: true,
                    isVisible: true,
                    isSyncEnabled: true
                )

                let secondary = CalendarInfo(
                    calendarId: "ui-test-secondary",
                    summary: "UI Test Secondary",
                    calendarDescription: "Secondary calendar for UI tests",
                    backgroundColor: "#F5A623",
                    accessRole: CalendarInfo.AccessRole.writer.rawValue,
                    isPrimary: false,
                    isVisible: true,
                    isSyncEnabled: true
                )

                modelContext.insert(primary)
                modelContext.insert(secondary)
            }

            let entryDescriptor = FetchDescriptor<ScheduleEntry>()
            let existingEntries = try modelContext.fetch(entryDescriptor)
            if existingEntries.isEmpty {
                let now = Date()
                let calendar = Calendar.current
                let todayStart = calendar.startOfDay(for: now)

                let seededEntry = ScheduleEntry(
                    source: ScheduleEntry.Source.calenote.rawValue,
                    managedByCaleNote: true,
                    googleEventId: nil,
                    calendarId: "ui-test-primary",
                    startAt: calendar.date(byAdding: .hour, value: 9, to: todayStart) ?? now,
                    endAt: calendar.date(byAdding: .hour, value: 10, to: todayStart) ?? now.addingTimeInterval(3600),
                    isAllDay: false,
                    title: "UI Test Seeded Entry",
                    body: "検索テスト用の本文です #テスト",
                    tags: ["テスト"],
                    syncStatus: ScheduleEntry.SyncStatus.synced.rawValue
                )

                let secondaryEntry = ScheduleEntry(
                    source: ScheduleEntry.Source.calenote.rawValue,
                    managedByCaleNote: true,
                    googleEventId: nil,
                    calendarId: "ui-test-secondary",
                    startAt: calendar.date(byAdding: .day, value: -1, to: todayStart) ?? now.addingTimeInterval(-86400),
                    endAt: calendar.date(byAdding: .hour, value: 1, to: calendar.date(byAdding: .day, value: -1, to: todayStart) ?? now) ?? now,
                    isAllDay: false,
                    title: "UI Test Editable Entry",
                    body: "編集テスト用の本文です",
                    tags: ["編集"],
                    syncStatus: ScheduleEntry.SyncStatus.synced.rawValue
                )

                modelContext.insert(seededEntry)
                modelContext.insert(secondaryEntry)
            }

            try modelContext.save()
        } catch {
            print("UITestDataSeeder failed: \(error)")
        }
    }
}
