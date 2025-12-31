import Foundation
import Testing
@testable import CaleNote

struct TagParserTests {
    @Test func extractDeduplicatesAndSanitizes() {
        let text = "Meeting #Work and #work and #te\u{0007}st"
        let tags = TagParser.extract(from: text)

        #expect(tags.count == 2)
        #expect(tags[0] == "Work")
        #expect(tags[1] == "test")
    }

    @Test func extractIgnoresEmptyAndOverLengthTags() {
        let longTag = "#" + String(repeating: "a", count: 51)
        let tags = TagParser.extract(from: "#ok \(longTag)")
        #expect(tags == ["ok"])
    }

    @Test func normalizeTrimsAndLowercases() {
        #expect(TagParser.normalize("  Foo\n") == "foo")
    }
}
