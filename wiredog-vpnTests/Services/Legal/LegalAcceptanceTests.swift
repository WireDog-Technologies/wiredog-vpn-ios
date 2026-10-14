import Foundation
import Testing
@testable import wiredog_vpn

struct LegalAcceptanceTests {
    private let legal = LegalVersions(privacyVersion: "2", termsVersion: "5", summary: nil)

    @Test func firstLaunchWithoutConfigRequiresBoth() {
        let result = LegalAcceptance.pending(legal: nil, acceptedPrivacy: "", acceptedTerms: "", legacyAccepted: false)
        #expect(result == [.privacy, .terms])
    }

    @Test func returningUserWithoutConfigFailsOpen() {
        #expect(LegalAcceptance.pending(legal: nil, acceptedPrivacy: "1", acceptedTerms: "1", legacyAccepted: false).isEmpty)
        #expect(LegalAcceptance.pending(legal: nil, acceptedPrivacy: "", acceptedTerms: "", legacyAccepted: true).isEmpty)
    }

    @Test func upToDateUserSeesNothing() {
        #expect(LegalAcceptance.pending(legal: legal, acceptedPrivacy: "2", acceptedTerms: "5", legacyAccepted: true).isEmpty)
    }

    @Test func onlyChangedDocumentIsPending() {
        #expect(LegalAcceptance.pending(legal: legal, acceptedPrivacy: "1", acceptedTerms: "5", legacyAccepted: true) == [.privacy])
        #expect(LegalAcceptance.pending(legal: legal, acceptedPrivacy: "2", acceptedTerms: "4", legacyAccepted: true) == [.terms])
        #expect(LegalAcceptance.pending(legal: legal, acceptedPrivacy: "1", acceptedTerms: "4", legacyAccepted: true) == [.privacy, .terms])
    }

    @Test func newInstallWithConfigRequiresBoth() {
        let result = LegalAcceptance.pending(legal: legal, acceptedPrivacy: "", acceptedTerms: "", legacyAccepted: false)
        #expect(result == [.privacy, .terms])
    }

    @Test func legacyAcceptedUserIsNotPromptedOnShip() {
        #expect(LegalAcceptance.pending(legal: legal, acceptedPrivacy: "", acceptedTerms: "", legacyAccepted: true).isEmpty)
    }

    @Test func adoptingLegacyAcceptanceRecordsServerVersionsSoLaterBumpsPrompt() {
        let adopted = LegalAcceptance.adoptLegacyAcceptance(legal: legal, acceptedPrivacy: "", acceptedTerms: "", legacyAccepted: true)
        #expect(adopted.privacy == "2" && adopted.terms == "5")

        let bumped = LegalVersions(privacyVersion: "3", termsVersion: "5", summary: nil)
        let result = LegalAcceptance.pending(legal: bumped, acceptedPrivacy: adopted.privacy, acceptedTerms: adopted.terms, legacyAccepted: true)
        #expect(result == [.privacy])
    }

    @Test func adoptionLeavesNonLegacyAndExistingVersionsAlone() {
        let fresh = LegalAcceptance.adoptLegacyAcceptance(legal: legal, acceptedPrivacy: "", acceptedTerms: "", legacyAccepted: false)
        #expect(fresh.privacy.isEmpty && fresh.terms.isEmpty)
        let existing = LegalAcceptance.adoptLegacyAcceptance(legal: legal, acceptedPrivacy: "1", acceptedTerms: "", legacyAccepted: true)
        #expect(existing.privacy == "1" && existing.terms == "5")
    }

    @Test func appConfigDecodesWithAndWithoutLegal() throws {
        let base = #"{"maintenanceMode":false,"platforms":{}"#
        let without = try JSONDecoder().decode(AppConfigResponse.self, from: Data((base + "}").utf8))
        #expect(without.legal == nil)
        let with = try JSONDecoder().decode(AppConfigResponse.self, from: Data((base + #","legal":{"privacyVersion":"a","termsVersion":"b","summary":null,"updatedAt":"x"}}"#).utf8))
        #expect(with.legal == LegalVersions(privacyVersion: "a", termsVersion: "b", summary: nil))
    }
}
