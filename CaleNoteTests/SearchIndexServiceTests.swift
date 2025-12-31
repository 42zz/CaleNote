import Foundation
import Testing
@testable import CaleNote

@MainActor
struct SearchIndexServiceTests {
    private let historyKey = "searchHistory"

    @Test func searchMatchesTitleTagsAndBody() {
        UserDefaults.standard.removeObject(forKey: historyKey)
        let service = SearchIndexService()

        let entry1 = TestHelpers.makeEntry(
            title: "Team Meeting",
            body: "Discuss roadmap",
            tags: ["work", "planning"],
            startAt: TestHelpers.makeDate(year: 2025, month: 1, day: 10),
            endAt: TestHelpers.makeDate(year: 2025, month: 1, day: 10, hour: 10)
        )
        let entry2 = TestHelpers.makeEntry(
            title: "Grocery List",
            body: "Buy milk",
            tags: ["personal"],
            startAt: TestHelpers.makeDate(year: 2025, month: 1, day: 11),
            endAt: TestHelpers.makeDate(year: 2025, month: 1, day: 11, hour: 12)
        )
        let entry3 = TestHelpers.makeEntry(
            title: "Team Lunch",
            body: "Cafe",
            tags: ["Work"],
            startAt: TestHelpers.makeDate(year: 2025, month: 1, day: 12),
            endAt: TestHelpers.makeDate(year: 2025, month: 1, day: 12, hour: 13)
        )

        service.rebuildIndex(entries: [entry1, entry2, entry3])

        let titleResults = service.search(query: "Team", includeBody: false)
        #expect(titleResults.count == 2)

        let tagResults = service.search(query: "#work", includeBody: false)
        #expect(tagResults.count == 2)

        let bodyResults = service.search(query: "milk", includeBody: true)
        #expect(bodyResults.count == 1)
        #expect(bodyResults.first?.title == "Grocery List")

        let combinedResults = service.search(query: "Team #work", includeBody: false)
        #expect(combinedResults.count == 2)
    }

    @Test func tagSummariesRespectCountsAndSuggestions() {
        UserDefaults.standard.removeObject(forKey: historyKey)
        let service = SearchIndexService()

        let entry1 = TestHelpers.makeEntry(
            title: "One",
            tags: ["work", "swift"],
            startAt: TestHelpers.makeDate(year: 2025, month: 1, day: 1),
            endAt: TestHelpers.makeDate(year: 2025, month: 1, day: 1, hour: 10)
        )
        let entry2 = TestHelpers.makeEntry(
            title: "Two",
            tags: ["work"],
            startAt: TestHelpers.makeDate(year: 2025, month: 1, day: 2),
            endAt: TestHelpers.makeDate(year: 2025, month: 1, day: 2, hour: 10)
        )
        entry1.updatedAt = TestHelpers.makeDate(year: 2025, month: 1, day: 5)
        entry2.updatedAt = TestHelpers.makeDate(year: 2025, month: 1, day: 6)

        service.rebuildIndex(entries: [entry1, entry2])

        let summaries = service.tagSummaries()
        let workSummary = summaries.first { $0.id == "work" }
        #expect(workSummary?.count == 2)

        let suggestions = service.tagSuggestions(limit: 1)
        #expect(suggestions.first == "work")

        let recent = service.recentTags(limit: 1)
        #expect(recent.first?.name == "work")
    }

    @Test func historyDeduplicatesAndCapsToTwenty() {
        UserDefaults.standard.removeObject(forKey: historyKey)
        let service = SearchIndexService()

        for index in 0..<25 {
            service.addHistory("query-\(index)")
        }
        service.addHistory("query-24")

        #expect(service.history.count == 20)
        #expect(service.history.first == "query-24")
    }
}
