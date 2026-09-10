import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class AccountUsageStore {
    private(set) var value: AccountUsage?
    private(set) var errorMessage: String?
    private(set) var updatedAt: Date?
    private let preferences: UserDefaults
    private var cacheKey: String?
    private var generation = UUID()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshAgain = false

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
    }

    func activate(namespace: String) {
        let key = "accountUsage." + SHA256.hash(data: Data(namespace.utf8)).map { String(format: "%02x", $0) }.joined()
        guard key != cacheKey else { return }
        clear()
        cacheKey = key
        if let data = preferences.data(forKey: key),
           let cached = try? JSONDecoder().decode(Snapshot.self, from: data),
           cached.value.currency == "USD", (0...100).contains(cached.value.remainingPercent) {
            value = cached.value
            updatedAt = cached.updatedAt
        }
    }

    func clear(removeCached: Bool = false) {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        refreshAgain = false
        if removeCached, let cacheKey { preferences.removeObject(forKey: cacheKey) }
        cacheKey = nil
        value = nil
        updatedAt = nil
        errorMessage = nil
    }

    /// Refreshes independently of a sheet's lifetime. Forced updates during a request
    /// queue one follow-up so a just-finished answer cannot leave an older usage value.
    @discardableResult
    func refresh(force: Bool = false, load: @escaping @MainActor () async throws -> AccountUsage) -> Task<Void, Never>? {
        guard let cacheKey else { return nil }
        if let refreshTask {
            if force { refreshAgain = true }
            return refreshTask
        }
        if !force, let updatedAt, Date().timeIntervalSince(updatedAt) < 30 { return nil }
        let currentGeneration = generation
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == currentGeneration {
                    refreshTask = nil
                    if refreshAgain {
                        refreshAgain = false
                        refresh(force: true, load: load)
                    }
                }
            }
            do {
                try Task.checkCancellation()
                let latest = try await load()
                try Task.checkCancellation()
                guard generation == currentGeneration else { return }
                let now = Date()
                value = latest
                updatedAt = now
                errorMessage = nil
                if let data = try? JSONEncoder().encode(Snapshot(value: latest, updatedAt: now)) {
                    preferences.set(data, forKey: cacheKey)
                }
            } catch is CancellationError {
                // Switching accounts or signing out must not publish a stale request.
            } catch {
                guard generation == currentGeneration else { return }
                errorMessage = error.localizedDescription
            }
        }
        refreshTask = task
        return task
    }

    private struct Snapshot: Codable {
        let value: AccountUsage
        let updatedAt: Date
    }
}
