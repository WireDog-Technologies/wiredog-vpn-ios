import Foundation
import UIKit

@MainActor
class BroadcastService: ObservableObject {
    static let shared = BroadcastService()

    @Published private(set) var messages: [BroadcastMessage] = []
    @Published private(set) var readIds: Set<String> = BroadcastReadStore.loadReadIds()

    private var pollingTask: Task<Void, Never>?
    private static let pollingInterval: TimeInterval = 5 * 60
    private static let pollingJitter: TimeInterval = 60

    private init() {
        setupPollingLifecycle()
    }

    // MARK: - Public

    func start() {
        Task { await refresh() }
        startPolling()
    }

    func refresh() async {
        do {
            // The backend query is the source of truth for which announcements are live —
            // whatever it returns is exactly what should be shown, no client-side lifecycle filtering.
            let fetched: [BroadcastMessage] = try await APIClient.shared.request(endpoint: .announcements)
            messages = fetched
            pruneReadIds(stillPresent: Set(fetched.map(\.id)))
        } catch {
            LogService.shared.logApp("[Broadcast] Fetch failed: \(error.localizedDescription)", level: .warning)
        }
    }

    // `target` is still carried on each message for backend organization/reporting, but every
    // active announcement is shown to every user — a maintenance notice for a server you aren't
    // currently on shouldn't go unseen just because it isn't selected.
    func activeMessages() -> [BroadcastMessage] {
        messages.sorted { $0.startAt > $1.startAt }
    }

    func unreadCount() -> Int {
        activeMessages().filter { !readIds.contains($0.id) }.count
    }

    func markRead(_ ids: [String]) {
        let newIds = Set(ids).subtracting(readIds)
        guard !newIds.isEmpty else { return }
        readIds.formUnion(newIds)
        BroadcastReadStore.save(readIds)
    }

    func markUnread(_ id: String) {
        guard readIds.contains(id) else { return }
        readIds.remove(id)
        BroadcastReadStore.save(readIds)
    }

    /// Drops read-IDs for messages the backend no longer returns, so the local read-set
    /// doesn't grow forever as old announcements are removed from the DB.
    private func pruneReadIds(stillPresent currentIds: Set<String>) {
        let pruned = readIds.intersection(currentIds)
        guard pruned != readIds else { return }
        readIds = pruned
        BroadcastReadStore.save(pruned)
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                let jitter = TimeInterval.random(in: 0...Self.pollingJitter)
                let delay = Self.pollingInterval + jitter
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func setupPollingLifecycle() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopPolling()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
            self?.startPolling()
        }
    }
}
