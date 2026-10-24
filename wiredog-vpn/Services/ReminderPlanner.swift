#if os(iOS)
import Foundation

/// One local notification the app wants scheduled.
struct PlannedReminder: Equatable {
    let id: String
    let fireDate: Date
    /// First sentence of the message, shown bold. nil for one-sentence messages.
    let title: String?
    let body: String
}

/// Which wording an unpaid account sees.
enum ReminderSegment: Equatable {
    /// Standard account that can start the 14-day free trial now.
    case trial
    /// Standard account that has to verify its email before it can start the trial.
    case unverified
    /// Anonymous account (no trial), or a Standard one while trials are switched off.
    case plain
}

/// Decides which reminders should exist, from account state alone. No scheduling and no I/O, so
/// the rules live in one place and can be unit-tested: the schedule, who is in or out, which
/// wording each person gets, and the 10:00-local delivery time. ReminderService applies the plan.
///
/// The rules, in short:
/// - Unpaid, never-paid, non-organization, non-revoked accounts get up to three reminders after
///   Day 0 (the moment notifications were allowed). Never the same message twice.
/// - If they tapped a checkout / trial button and left, that sequence is replaced by one
///   "finish setting up" reminder the next morning.
/// - A running free trial gets one reminder two days before it ends.
/// - Lapsed or non-renewing subscribers get up to two win-back reminders.
enum ReminderPlanner {
    private enum Slot {
        case first, third, seventh
    }

    // MARK: - Public

    static func segment(for user: UserProfile) -> ReminderSegment {
        guard user.accountType == .standard else { return .plain }
        if user.trialEligible { return .trial }
        if user.trialIneligibleReason == .unverified { return .unverified }
        return .plain
    }

    /// - Parameters:
    ///   - day0: When notifications were allowed for this unpaid account (nil if not yet).
    ///   - reason: The reason picked on the paywall exit sheet, if any.
    ///   - checkoutTap: Set when they tapped a checkout / trial button; `wasTrial` picks the wording.
    ///   - lapseObserved: When the app first saw this account's access had ended.
    ///   - iapRenews: Whether an Apple subscription on this device is set to renew.
    static func plan(
        user: UserProfile,
        now: Date,
        calendar: Calendar = .current,
        day0: Date?,
        reason: String?,
        checkoutTap: (date: Date, wasTrial: Bool)?,
        lapseObserved: Date?,
        iapRenews: Bool
    ) -> [PlannedReminder] {
        // Organization members and revoked accounts get none: a personal plan wouldn't help them.
        guard !user.isRevoked, !user.isOrganizationMember, user.lostOrganizationAccess == nil else { return [] }

        var planned: [PlannedReminder] = []

        if user.isUnpaidNeverPaid {
            if let tap = checkoutTap {
                planned += finishSetup(after: tap.date, wasTrial: tap.wasTrial, calendar: calendar)
            } else if let day0 {
                planned += signupSequence(user: user, day0: day0, reason: reason, calendar: calendar)
            }
        } else if let trialEnd = user.trialEndsAt, trialEnd > now {
            planned += trialEnding(user: user, calendar: calendar)
        } else if user.hasEntitlement {
            // An auto-renewing plan extends its own expiry, so a win-back dated from the expiry the
            // app last saw could fire after it renewed. Only plans that will really end get one.
            if !user.autoRenews, !iapRenews, let expiry = user.subscriptionExpiresAt {
                planned += winBack(from: expiry, calendar: calendar)
            }
        } else if user.everHadAccess, let lapseObserved {
            planned += winBack(from: lapseObserved, calendar: calendar)
        }

        return planned
            .filter { $0.fireDate > now }
            .sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: - Sign-up sequence

    private static func signupSequence(user: UserProfile, day0: Date, reason: String?, calendar: Calendar) -> [PlannedReminder] {
        let kind = segment(for: user)
        let tooExpensive = reason == ExitReason.tooExpensiveKey

        // "Not ready yet / need more time" shifts everything later and uses the default wording:
        // the +3 message on day 3, the +1 message on day 7, and the last reminder on day 14.
        let schedule: [(slot: Slot, day: Int)] = reason == ExitReason.notReadyKey
            ? [(.third, 3), (.first, 7), (.seventh, 14)]
            : [(.first, 1), (.third, 3), (.seventh, 7)]

        return schedule.enumerated().compactMap { (index, entry) -> PlannedReminder? in
            guard let fire = morning(daysAfter: entry.day, of: day0, calendar: calendar) else { return nil }
            let text = message(entry.slot, segment: kind, tooExpensive: tooExpensive)
            return PlannedReminder(id: "wd.reminder.signup.\(index + 1)", fireDate: fire, title: text.title, body: text.body)
        }
    }

    private static func message(_ slot: Slot, segment: ReminderSegment, tooExpensive: Bool) -> (title: String?, body: String) {
        if tooExpensive {
            switch slot {
            case .first:
                switch segment {
                case .trial:
                    return ("Try it free first.", "14 days free, then plans from $4.99/mo on the 2-year plan.")
                case .unverified:
                    return ("Verify your email to try WireDog free for 14 days.", "Then plans from $4.99/mo on the 2-year plan.")
                case .plain:
                    return ("Plans from $4.99/mo.", "Our 2-year plan works out to $4.99 a month.")
                }
            case .third:
                return ("Less per month on longer plans.", "Annual is $6.99/mo, 2-year is $4.99/mo, versus $9.99 monthly.")
            case .seventh:
                break // the last reminder is the same for everyone in a segment
            }
        }

        switch (slot, segment) {
        case (.first, .trial):
            return ("Your 14-day free trial is ready.", "Try WireDog VPN risk-free.")
        case (.first, .unverified):
            return ("Unlock your free trial by verifying your email.", "Get a taste of WireDog VPN for 14 days.")
        case (.first, .plain):
            return ("Protect your connection.", "Plans start at $4.99/mo on the 2-year plan.")
        case (.third, .trial):
            return ("Cancel anytime.", "Start your trial in under a minute. Cancel before day 14 and you pay nothing.")
        case (.third, .unverified):
            return (nil, "Verify your email, then try WireDog free for 14 days.")
        case (.third, .plain):
            return ("Your connection is still unprotected.", "Pick a payment method that fits your privacy needs.")
        case (.seventh, .trial):
            return ("Last reminder from us.", "Your free trial is still waiting. We won't nag you again.")
        case (.seventh, .unverified):
            return ("Last reminder from us.", "Whenever you're ready for your free trial, let us know!")
        case (.seventh, .plain):
            return ("Last reminder from us.", "WireDog is here whenever you're ready. We won't nag you again.")
        }
    }

    // MARK: - Checkout started, not finished

    private static func finishSetup(after tapDate: Date, wasTrial: Bool, calendar: Calendar) -> [PlannedReminder] {
        guard let fire = morning(daysAfter: 1, of: tapDate, calendar: calendar) else { return [] }
        if wasTrial {
            return [PlannedReminder(
                id: "wd.reminder.finish",
                fireDate: fire,
                title: "You're one step away.",
                body: "Finish starting your free trial. Nothing is charged today."
            )]
        }
        return [PlannedReminder(
            id: "wd.reminder.finish",
            fireDate: fire,
            title: "Pick up where you left off.",
            body: "Finish setting up WireDog. Plans from $4.99/mo."
        )]
    }

    // MARK: - Free trial ending

    private static func trialEnding(user: UserProfile, calendar: Calendar) -> [PlannedReminder] {
        guard let end = user.trialEndsAt,
              let fire = morning(daysAfter: -2, of: end, calendar: calendar) else { return [] }

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        let date = formatter.string(from: end)

        let charge = chargeText(for: user.billingPeriod).map { "\($0) " } ?? ""
        return [PlannedReminder(
            id: "wd.reminder.trial-ending",
            fireDate: fire,
            title: "Your free trial ends in 2 days.",
            body: "If you keep it, you'll be charged \(charge)on \(date). Manage or cancel in your account."
        )]
    }

    /// The first charge after a trial, from the plan the trial was started on. nil when unknown,
    /// so the message omits the amount rather than guessing.
    private static func chargeText(for billingPeriod: String?) -> String? {
        guard let billingPeriod else { return nil }
        if billingPeriod.contains("24") { return "$119.76" }
        if billingPeriod.contains("12") { return "$83.88" }
        if billingPeriod.contains("1") { return "$9.99" }
        return nil
    }

    // MARK: - Win-back

    private static func winBack(from base: Date, calendar: Calendar) -> [PlannedReminder] {
        var reminders: [PlannedReminder] = []
        if let fire = morning(daysAfter: 3, of: base, calendar: calendar) {
            reminders.append(PlannedReminder(
                id: "wd.reminder.winback.1",
                fireDate: fire,
                title: "Your WireDog protection has ended.",
                body: "Renew to get back online. Your account and settings are still here."
            ))
        }
        if let fire = morning(daysAfter: 30, of: base, calendar: calendar) {
            reminders.append(PlannedReminder(
                id: "wd.reminder.winback.2",
                fireDate: fire,
                title: "Still need a VPN?",
                body: "Your account is waiting. Pick up where you left off."
            ))
        }
        return reminders
    }

    // MARK: - Time

    /// 10:00 local time, `days` days after (or before, if negative) the given moment.
    static func morning(daysAfter days: Int, of base: Date, calendar: Calendar) -> Date? {
        guard let shifted = calendar.date(byAdding: .day, value: days, to: base) else { return nil }
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: shifted)
    }
}
#endif
