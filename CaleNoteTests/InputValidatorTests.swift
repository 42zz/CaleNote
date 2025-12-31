import Foundation
import Testing
@testable import CaleNote

struct InputValidatorTests {
    @Test func sanitizeTitleTrimsAndRemovesControlCharacters() {
        let input = "  hello\u{0007}  "
        let sanitized = InputValidator.sanitizeTitle(input)
        #expect(sanitized == "hello")
    }

    @Test func validateReturnsErrorForLongTitle() {
        let title = String(repeating: "a", count: InputValidator.maxTitleLength + 1)
        let error = InputValidator.validate(title: title, body: "ok")
        #expect(error != nil)
    }

    @Test func validateReturnsNilForValidLengths() {
        let error = InputValidator.validate(title: "title", body: "body")
        #expect(error == nil)
    }
}
