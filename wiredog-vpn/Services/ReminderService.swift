#if os(iOS)
import Foundation
import UserNotifications

/// Local reminders that bring unpaid people back and keep paying ones informed. Everything stays
/// on the device: no push token, nothing sent to the backend, no per-user record anywhere else.
///
/// What to send and when is decided by ReminderPlanner; this class asks for permission, keeps the
/// few facts the planner needs (when notifications were allowed, the exit-sheet reason, whether a
/// checkout was started), and replaces the pending notifications with the plan. It rebuilds from
/// state on every app foreground, so it never drifts out of date.
@MainActor
final class ReminderService {
    static let shared = ReminderService()

    private static let idPrefix = "wd.reminder."
    private static let enabledKey = "reminders_enabled"

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    // MARK: - Settings switch

    /// The in-app "Reminders" switch. On by default; notifications still need iOS permission.
    var isEnabled: Bool {
        defaults.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool, for user: UserProfile?) {
        defaults.set(enabled, forKey: Self.enabledKey)
        Task { await sync(for: user) }
    }

    // MARK: - Permission

    /// Asks for notification permission once, at app open, before the paywall. iOS shows its
    /// prompt a single time per install; after that this does nothing. Organization members and
    /// revoked accounts are never asked, since none of the reminders apply to them.
    func requestPermissionIfNeeded(for user: UserProfile) async {
        guard isEnabled, !user.isRevoked, !user.isOrganizationMember, user.lostOrganizationAccess == nil else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            LogService.shared.logApp("[Reminders] notification permission \(granted ? "granted" : "declined")")
        } catch {
            LogService.shared.logApp("[Reminders] permission request failed: \(error.localizedDescription)", level: .warning)
        }
        await sync(for: user)
    }

    // MARK: - Facts the planner needs

    /// The reason picked on the paywall exit sheet. Stays on this device.
    func recordExitReason(_ reason: String?, for user: UserProfile?) {
        guard let user else { return }
        if let reason {
            defaults.set(reason, forKey: key("reason", user.id))
        } else {
            defaults.removeObject(forKey: key("reason", user.id))
        }
        Task { await sync(for: user) }
    }

    /// They tapped a checkout or trial button on the paywall (and so went to the website).
    func recordCheckoutTap(wasTrial: Bool, for user: UserProfile?) {
        guard let user, user.isUnpaidNeverPaid else { return }
        defaults.set(Date(), forKey: key("checkout", user.id))
        defaults.set(wasTrial, forKey: key("checkoutTrial", user.id))
        Task { await sync(for: user) }
    }

    // MARK: - Scheduling

    /// Rebuilds the pending reminders from the current account state. Safe to call often.
    func sync(for user: UserProfile?) async {
        guard let user, isEnabled else {
            cancelAll()
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            cancelAll()
            return
        }

        // Day 0 is the first time we see permission granted for an account still in the sign-up funnel.
        if user.isUnpaidNeverPaid, date("day0", user.id) == nil {
            defaults.set(Date(), forKey: key("day0", user.id))
        }

        // Remember when access was first seen to have ended, for the win-back reminders.
        if !user.hasEntitlement, user.everHadAccess {
            if date("lapse", user.id) == nil { defaults.set(Date(), forKey: key("lapse", user.id)) }
        } else {
            defaults.removeObject(forKey: key("lapse", user.id))
        }

        // Only worth asking StoreKit for an active plan that the website doesn't renew.
        let iapRenews: Bool
        if user.hasEntitlement, !user.autoRenews {
            iapRenews = await IAPService.shared.isAutoRenewOn()
        } else {
            iapRenews = false
        }

        let tap: (date: Date, wasTrial: Bool)?
        if let tapDate = date("checkout", user.id) {
            tap = (tapDate, defaults.bool(forKey: key("checkoutTrial", user.id)))
        } else {
            tap = nil
        }

        let planned = ReminderPlanner.plan(
            user: user,
            now: Date(),
            day0: date("day0", user.id),
            reason: defaults.string(forKey: key("reason", user.id)),
            checkoutTap: tap,
            lapseObserved: date("lapse", user.id),
            iapRenews: iapRenews
        )
        await replacePending(with: planned)
    }

    /// Removes every pending reminder. Called on sign-out, account deletion, and when the switch
    /// is turned off. The saved per-account facts are left alone: they hold no personal data.
    func cancelAll() {
        Task { await removePending() }
    }

    private func replacePending(with planned: [PlannedReminder]) async {
        await removePending()
        for reminder in planned {
            let content = UNMutableNotificationContent()
            if let title = reminder.title {
                content.title = title
            }
            content.body = reminder.body
            content.sound = .default

            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                LogService.shared.logApp("[Reminders] could not schedule \(reminder.id): \(error.localizedDescription)", level: .warning)
            }
        }
        LogService.shared.logApp("[Reminders] \(planned.count) reminder(s) scheduled")
    }

    private func removePending() async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }

    // MARK: - Storage keys

    private func key(_ name: String, _ accountId: Int) -> String {
        "reminders_\(name)_\(accountId)"
    }

    private func date(_ name: String, _ accountId: Int) -> Date? {
        defaults.object(forKey: key(name, accountId)) as? Date
    }
}
#endif
