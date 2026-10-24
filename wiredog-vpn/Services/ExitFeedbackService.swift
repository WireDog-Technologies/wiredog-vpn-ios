import Foundation

/// Sends the answer from the paywall exit sheet or the account-deletion flow. The backend turns
/// the reason into an anonymous daily count and keeps any typed text with no account link, so
/// nothing here is tied to who answered. Fire-and-forget: a failure is logged and never blocks.
@MainActor
final class ExitFeedbackService {
    static let shared = ExitFeedbackService()

    enum Kind: String {
        case paywall
        case delete
    }

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func submit(kind: Kind, reason: String, text: String?) async {
        let typed: String?
        if reason == ExitReason.otherKey, let text {
            let cleaned = FeedbackText.sanitize(text)
            typed = cleaned.isEmpty ? nil : cleaned
        } else {
            typed = nil
        }

        do {
            try await apiClient.requestVoid(
                endpoint: .exitFeedback,
                body: ExitFeedbackRequest(kind: kind.rawValue, reason: reason, text: typed)
            )
        } catch {
            LogService.shared.logApp("[ExitFeedback] \(kind.rawValue) answer not sent: \(error.localizedDescription)", level: .warning)
        }
    }
}

private struct ExitFeedbackRequest: Encodable {
    let kind: String
    let reason: String
    let text: String?
}
