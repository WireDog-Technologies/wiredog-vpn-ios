import Foundation

/// Plain-text rules for the typed "Other" reason on the exit surveys. The server applies the same
/// rules again (wiredog-backend `lib/feedbackText.ts`) and is the authority; this only keeps the
/// text box honest and short. Keep the two in step.
///
/// Allowed: letters and numbers in any script, spaces, and . , ! ? ' " - ( ) / : ; & % $ @ # +
/// Everything else (angle brackets, backticks, braces, control and zero-width characters) is dropped.
enum FeedbackText {
    static let maxLength = 140

    private static let allowedPunctuation = CharacterSet(charactersIn: ".,!?'\"-()/:;&%$@#+")

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.letters.contains(scalar)
            || CharacterSet.decimalDigits.contains(scalar)
            || allowedPunctuation.contains(scalar)
    }

    /// Applied on every keystroke: drops what the server would drop, turns line breaks into spaces,
    /// and caps the length. Spaces stay as typed, because trimming here would make it impossible to
    /// type the space between two words.
    static func filterWhileTyping(_ input: String) -> String {
        var result = ""
        for scalar in input.precomposedStringWithCompatibilityMapping.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                result.unicodeScalars.append(" ")
            } else if isAllowed(scalar) {
                result.unicodeScalars.append(scalar)
            }
        }
        return String(result.prefix(maxLength))
    }

    /// The form that is sent: single spaces, nothing at either end.
    static func sanitize(_ input: String) -> String {
        let words = filterWhileTyping(input).split(separator: " ", omittingEmptySubsequences: true)
        return String(words.joined(separator: " ").prefix(maxLength))
    }
}
