import Foundation

enum LegalDocument: Hashable {
    case privacy
    case terms
}

// Decides which legal documents the user still needs to accept. Accepted versions are stored
// locally only (UserDefaults) — nothing about acceptance is sent to the server.
enum LegalAcceptance {
    static let legacyAcceptedKey = "hasAcceptedPrivacyDisclosure"
    static let privacyKey = "acceptedPrivacyVersion"
    static let termsKey = "acceptedTermsVersion"

    /// - legacyAccepted: the pre-versioning boolean. Users who accepted under it have no stored
    ///   versions; they're treated as current until `adoptLegacyAcceptance` records the server's
    ///   versions, so shipping this doesn't re-prompt anyone.
    static func pending(
        legal: LegalVersions?,
        acceptedPrivacy: String,
        acceptedTerms: String,
        legacyAccepted: Bool
    ) -> Set<LegalDocument> {
        guard let legal else {
            // No config: never block returning users (fail open). A first-ever launch still
            // shows the initial screen.
            let hasAcceptedBefore = legacyAccepted || !acceptedPrivacy.isEmpty || !acceptedTerms.isEmpty
            return hasAcceptedBefore ? [] : [.privacy, .terms]
        }

        var result: Set<LegalDocument> = []
        if acceptedPrivacy != legal.privacyVersion, !(legacyAccepted && acceptedPrivacy.isEmpty) {
            result.insert(.privacy)
        }
        if acceptedTerms != legal.termsVersion, !(legacyAccepted && acceptedTerms.isEmpty) {
            result.insert(.terms)
        }
        return result
    }

    /// True when the user has accepted something before, i.e. the prompt is a re-accept.
    static func isUpdate(acceptedPrivacy: String, acceptedTerms: String, legacyAccepted: Bool) -> Bool {
        legacyAccepted || !acceptedPrivacy.isEmpty || !acceptedTerms.isEmpty
    }

    /// Records the server's current versions for documents a legacy-accepted user has no
    /// stored version for. Returns the (possibly updated) pair.
    static func adoptLegacyAcceptance(
        legal: LegalVersions,
        acceptedPrivacy: String,
        acceptedTerms: String,
        legacyAccepted: Bool
    ) -> (privacy: String, terms: String) {
        guard legacyAccepted else { return (acceptedPrivacy, acceptedTerms) }
        return (
            acceptedPrivacy.isEmpty ? legal.privacyVersion : acceptedPrivacy,
            acceptedTerms.isEmpty ? legal.termsVersion : acceptedTerms
        )
    }
}
