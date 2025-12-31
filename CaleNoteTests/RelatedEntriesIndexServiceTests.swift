import Foundation
import Testing
@testable import CaleNote

@MainActor
struct RelatedEntriesIndexServiceTests {
    @Test func relatedEntriesFindSameMonthDayAndHoliday() {
        let service = RelatedEntriesIndexService()

        let entryA = TestHelpers.makeEntry(
            title: "New Year 2024",
            startAt: TestHelpers.makeDate(year: 2024, month: 1, day: 1),
            endAt: TestHelpers.makeDate(year: 2024, month: 1, day: 1, hour: 10)
        )
        let entryB = TestHelpers.makeEntry(
            title: "New Year 2025",
            startAt: TestHelpers.makeDate(year: 2025, month: 1, day: 1),
            endAt: TestHelpers.makeDate(year: 2025, month: 1, day: 1, hour: 10)
        )
        let entryC = TestHelpers.makeEntry(
            title: "Random",
            startAt: TestHelpers.makeDate(year: 2025, month: 2, day: 2),
            endAt: TestHelpers.makeDate(year: 2025, month: 2, day: 2, hour: 10)
        )

        service.rebuildIndex(entries: [entryA, entryB, entryC])

        let related = service.relatedEntries(for: entryA)
        #expect(related.sameMonthDay.count == 1)
        #expect(related.sameMonthDay.first?.title == "New Year 2025")
        #expect(related.sameHoliday?.entries.count == 1)
        #expect(related.sameHoliday?.entries.first?.title == "New Year 2025")
    }
}
