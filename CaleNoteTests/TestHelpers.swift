import Foundation
import SwiftData
@testable import CaleNote

@MainActor
enum TestModelContainer {
    static let shared: ModelContainer = {
        let schema = Schema([
            ScheduleEntry.self,
            CalendarInfo.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: config)
    }()
}

enum TestHelpers {
    static func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 9,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        return calendar.date(from: components) ?? Date()
    }

    static func makeEntry(
        title: String,
        body: String? = nil,
        tags: [String] = [],
        startAt: Date,
        endAt: Date,
        source: ScheduleEntry.Source = .calenote,
        managedByCaleNote: Bool = true,
        googleEventId: String? = nil,
        syncStatus: ScheduleEntry.SyncStatus = .pending
    ) -> ScheduleEntry {
        ScheduleEntry(
            source: source.rawValue,
            managedByCaleNote: managedByCaleNote,
            googleEventId: googleEventId,
            calendarId: nil,
            startAt: startAt,
            endAt: endAt,
            isAllDay: false,
            title: title,
            body: body,
            tags: tags,
            syncStatus: syncStatus.rawValue,
            lastSyncedAt: nil
        )
    }

    @MainActor
    static func makeModelContext() -> ModelContext {
        ModelContext(TestModelContainer.shared)
    }
}
