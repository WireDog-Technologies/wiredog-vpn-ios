import Testing
import Foundation
@testable import wiredog_vpn

struct FeedbackTextTests {

    @Test func keepsOrdinarySentences() {
        #expect(FeedbackText.sanitize("It's too pricey, honestly (for me).") == "It's too pricey, honestly (for me).")
    }

    @Test func dropsMarkupAndScriptCharacters() {
        #expect(FeedbackText.sanitize("<script>alert(1)</script>") == "scriptalert(1)/script")
        #expect(FeedbackText.sanitize("`rm -rf` {{x}} \\ <img src=x>") == "rm -rf x img srcx")
    }

    @Test func lineBreaksBecomeSingleSpacesAndEdgesAreTrimmed() {
        #expect(FeedbackText.sanitize("  hello\n\n\tworld  ") == "hello world")
    }

    @Test func typingKeepsSpacesSoWordsCanBeSeparated() {
        #expect(FeedbackText.filterWhileTyping("hello ") == "hello ")
        #expect(FeedbackText.filterWhileTyping("a\nb") == "a b")
    }

    @Test func keepsLettersFromOtherScripts() {
        #expect(FeedbackText.sanitize("precio muy alto, señor") == "precio muy alto, señor")
    }

    @Test func capsAtOneHundredFortyCharacters() {
        let long = String(repeating: "a", count: 300)
        #expect(FeedbackText.sanitize(long).count == FeedbackText.maxLength)
        #expect(FeedbackText.filterWhileTyping(long).count == FeedbackText.maxLength)
    }

    @Test func onlyDisallowedCharactersLeavesNothing() {
        #expect(FeedbackText.sanitize("<<<>>>{}[]") == "")
    }
}
