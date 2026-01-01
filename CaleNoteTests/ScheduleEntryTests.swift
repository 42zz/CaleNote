import Foundation
import Testing
@testable import CaleNote

struct ScheduleEntryTests {
    @Test func validationDetectsIssues() {
        let entry = TestHelpers.makeEntry(
            title: " ",
            startAt: TestHelpers.makeDate(year: 2025, month: 1, day: 1, hour: 10),
            endAt: TestHelpers.makeDate(year: 2025, month: 1, day: 1, hour: 9),
            source: .google
        )
        entry.source = "unknown"

        let errors = entry.validate()
        #expect(errors.contains(.emptyTitle))
        #expect(errors.contains(.endBeforeStart))
        #expect(errors.contains(.invalidSource("unknown")))
    }

    @Test func updateSyncStatusSetsLastSyncedAt() {
        let entry = TestHelpers.makeEntry(
            title: "Sync",
            startAt: TestHelpers.makeDate(year: 2025, month: 1, day: 1),
            endAt: TestHelpers.makeDate(year: 2025, month: 1, day: 1, hour: 10)
        )
        #expect(entry.lastSyncedAt == nil)
        entry.updateSyncStatus(.synced)
        #expect(entry.isSynced)
        #expect(entry.lastSyncedAt != nil)
    }

    @Test func addTagDoesNotDuplicateAndRemoveTagWorks() {
        let entry = TestHelpers.makeEntry(
            title: "Tags",
            tags: ["work"],
            startAt: TestHelpers.makeDate(year: 2025, month: 1, day: 1),
            endAt: TestHelpers.makeDate(year: 2025, month: 1, day: 1, hour: 10)
        )
        entry.addTag("work")
        entry.addTag("personal")
        #expect(entry.tags.count == 2)
        entry.removeTag("work")
        #expect(entry.tags == ["personal"])
    }

    @Test func durationIsCalculatedFromDates() {
        let start = TestHelpers.makeDate(year: 2025, month: 1, day: 1, hour: 10)
        let end = TestHelpers.makeDate(year: 2025, month: 1, day: 1, hour: 11)
        let entry = TestHelpers.makeEntry(
            title: "Duration",
            startAt: start,
            endAt: end
        )
        #expect(entry.duration == 3600)
    }
}
