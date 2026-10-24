import Testing
import Foundation
@testable import wiredog_vpn

struct ReminderPlannerTests {

    // MARK: - Helpers

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Builds a profile from /auth/me-shaped JSON. `extra` is spliced in as additional members.
    private func profile(_ extra: String) throws -> UserProfile {
        let json = """
        { "id": 1, "accountType": "standard", \(extra) }
        """
        return try decoder.decode(UserProfile.self, from: Data(json.utf8))
    }

    private func standardEligible() throws -> UserProfile {
        try profile(#""trialIneligibleReason": null, "everHadAccess": false"#)
    }

    private func standardUnverified() throws -> UserProfile {
        try profile(#""trialIneligibleReason": "unverified", "everHadAccess": false"#)
    }

    private func anonymous() throws -> UserProfile {
        try decoder.decode(UserProfile.self, from: Data(#"{ "id": 2, "accountType": "anonymous", "trialIneligibleReason": "anonymous", "everHadAccess": false }"#.utf8))
    }

    // Monday 8pm New York, as Day 0.
    private var day0: Date { date("2026-10-19T20:00:00-04:00") }
    private var now: Date { date("2026-10-19T20:05:00-04:00") }

    private func plan(
        _ user: UserProfile,
        reason: String? = nil,
        day0: Date? = nil,
        tap: (date: Date, wasTrial: Bool)? = nil,
        lapse: Date? = nil,
        iapRenews: Bool = false,
        now: Date? = nil
    ) -> [PlannedReminder] {
        ReminderPlanner.plan(
            user: user,
            now: now ?? self.now,
            calendar: calendar,
            day0: day0 ?? self.day0,
            reason: reason,
            checkoutTap: tap,
            lapseObserved: lapse,
            iapRenews: iapRenews
        )
    }

    private func hourAndMinute(_ reminder: PlannedReminder) -> [Int] {
        let parts = calendar.dateComponents([.hour, .minute], from: reminder.fireDate)
        return [parts.hour ?? -1, parts.minute ?? -1]
    }

    // MARK: - Sign-up sequence

    @Test func eligibleStandard_getsThreeRemindersAtTenAM() throws {
        let reminders = plan(try standardEligible())

        #expect(reminders.count == 3)
        #expect(reminders.map(hourAndMinute) == [[10, 0], [10, 0], [10, 0]])
        #expect(reminders[0].title == "Your 14-day free trial is ready.")
        #expect(reminders[1].title == "Cancel anytime.")
        #expect(reminders[2].title == "Last reminder from us.")
        // Day 1, 3 and 7 after Monday 19 Oct.
        let days = reminders.map { calendar.component(.day, from: $0.fireDate) }
        #expect(days == [20, 22, 26])
    }

    @Test func unverifiedStandard_getsTheVerifyWording() throws {
        let reminders = plan(try standardUnverified())

        #expect(reminders[0].title == "Unlock your free trial by verifying your email.")
        #expect(reminders[1].title == nil)
        #expect(reminders[1].body == "Verify your email, then try WireDog free for 14 days.")
        #expect(reminders[2].body == "Whenever you're ready for your free trial, let us know!")
    }

    @Test func anonymous_getsThePlainWording() throws {
        let reminders = plan(try anonymous())

        #expect(reminders[0].title == "Protect your connection.")
        #expect(reminders[1].body == "Pick a payment method that fits your privacy needs.")
        #expect(reminders[2].body == "WireDog is here whenever you're ready. We won't nag you again.")
    }

    @Test func tooExpensive_swapsFirstAndThirdMessage() throws {
        let reminders = plan(try standardEligible(), reason: "too_expensive")

        #expect(reminders[0].title == "Try it free first.")
        #expect(reminders[1].title == "Less per month on longer plans.")
        #expect(reminders[2].title == "Last reminder from us.")
    }

    @Test func notReady_skipsDayOneAndAddsDayFourteenWithDefaultCopy() throws {
        let reminders = plan(try standardEligible(), reason: "not_ready")

        #expect(reminders.count == 3)
        let days = reminders.map { calendar.component(.day, from: $0.fireDate) }
        #expect(days == [22, 26, 2]) // Oct 22, Oct 26, Nov 2
        #expect(reminders[0].title == "Cancel anytime.")
        #expect(reminders[1].title == "Your 14-day free trial is ready.")
        #expect(reminders[2].title == "Last reminder from us.")
    }

    @Test func otherReasons_useTheDefaultTrack() throws {
        for reason in ["server_locations", "missing_feature", "other"] {
            let reminders = plan(try standardEligible(), reason: reason)
            #expect(reminders.map(\.title) == plan(try standardEligible()).map(\.title))
        }
    }

    @Test func noDay0_meansNoSequence() throws {
        let reminders = ReminderPlanner.plan(
            user: try standardEligible(), now: now, calendar: calendar,
            day0: nil, reason: nil, checkoutTap: nil, lapseObserved: nil, iapRenews: false
        )
        #expect(reminders.isEmpty)
    }

    @Test func pastReminders_areDropped() throws {
        let later = date("2026-10-23T09:00:00-04:00")
        let reminders = plan(try standardEligible(), now: later)

        #expect(reminders.count == 1) // only day 7 is still ahead
        #expect(reminders[0].title == "Last reminder from us.")
    }

    // MARK: - Who is left out

    @Test func paidRevokedAndOrganizationAccounts_getNoSignupReminders() throws {
        let paid = try profile(#""isActive": true, "subscriptionExpiresAt": "2030-01-01T00:00:00Z", "everHadAccess": true, "autoRenews": true, "trialIneligibleReason": "has_time""#)
        let revoked = try profile(#""revokedReason": "fraud", "trialIneligibleReason": "revoked", "everHadAccess": false"#)
        let org = try profile(#""organizationName": "Acme", "subscriptionManagedByOrganization": true, "trialIneligibleReason": "has_time""#)
        let lapsedBefore = try profile(#""everHadAccess": true, "trialIneligibleReason": "paid_before""#)

        #expect(plan(paid).isEmpty) // auto-renewing: nothing to remind
        #expect(plan(revoked).isEmpty)
        #expect(plan(org).isEmpty)
        // Had access before: not in the sign-up sequence (and no lapse observed yet).
        #expect(plan(lapsedBefore).isEmpty)
    }

    // MARK: - Checkout started

    @Test func checkoutTap_replacesTheSequenceWithOneFinishReminder() throws {
        let tapDate = date("2026-10-19T15:00:00-04:00")
        let trialTap = plan(try standardEligible(), tap: (tapDate, true))
        let checkoutTap = plan(try anonymous(), tap: (tapDate, false))

        #expect(trialTap.count == 1)
        #expect(trialTap[0].title == "You're one step away.")
        #expect(calendar.component(.day, from: trialTap[0].fireDate) == 20)
        #expect(checkoutTap.count == 1)
        #expect(checkoutTap[0].title == "Pick up where you left off.")
    }

    // MARK: - Trial ending and win-back

    @Test func runningTrial_getsOneReminderTwoDaysBeforeItEnds() throws {
        let user = try profile(#""isActive": true, "trialEndsAt": "2030-11-02T14:00:00Z", "subscriptionExpiresAt": "2030-11-02T14:00:00Z", "billingPeriod": "12months", "beganAsTrial": true, "autoRenews": true, "everHadAccess": true"#)
        let reminders = plan(user)

        #expect(reminders.count == 1)
        #expect(reminders[0].title == "Your free trial ends in 2 days.")
        #expect(reminders[0].body.contains("$83.88"))
        #expect(calendar.component(.day, from: reminders[0].fireDate) == 31) // Oct 31
        #expect(hourAndMinute(reminders[0]) == [10, 0])
    }

    @Test func nonRenewingPlan_getsWinBackFromItsExpiry_butRenewingOnesDoNot() throws {
        let nonRenewing = try profile(#""isActive": true, "subscriptionExpiresAt": "2030-11-01T12:00:00Z", "everHadAccess": true, "autoRenews": false"#)
        let renewingCard = try profile(#""isActive": true, "subscriptionExpiresAt": "2030-11-01T12:00:00Z", "everHadAccess": true, "autoRenews": true"#)

        #expect(plan(nonRenewing).map(\.title) == ["Your WireDog protection has ended.", "Still need a VPN?"])
        #expect(plan(renewingCard).isEmpty)
        #expect(plan(nonRenewing, iapRenews: true).isEmpty) // an Apple plan that will renew itself
    }

    @Test func lapsedAccount_getsWinBackFromWhenTheLapseWasSeen() throws {
        let lapsed = try profile(#""everHadAccess": true, "trialIneligibleReason": "paid_before""#)
        let seen = date("2026-10-19T09:00:00-04:00")
        let reminders = plan(lapsed, lapse: seen)

        #expect(reminders.count == 2)
        #expect(calendar.component(.day, from: reminders[0].fireDate) == 22)
    }
}
