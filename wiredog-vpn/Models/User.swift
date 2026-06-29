import Foundation

struct User: Equatable, Codable {
    let username: String
    let accountNumber: String
    let subscriptionPlan: String
    let subscriptionEndDate: Date?

    var daysRemaining: Int {
        guard let endDate = subscriptionEndDate else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endDateStart = calendar.startOfDay(for: endDate)
        let components = calendar.dateComponents([.day], from: today, to: endDateStart)
        return max(components.day ?? 0, 0)
    }

    var isSubscriptionActive: Bool {
        guard let endDate = subscriptionEndDate else { return false }
        return endDate > Date()
    }
}
