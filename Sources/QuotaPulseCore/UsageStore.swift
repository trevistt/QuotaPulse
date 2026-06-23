import Combine
import Foundation

public struct UsageSnapshotCache: Sendable {
    private let url: URL

    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            self.url = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/QuotaPulse/last-snapshot.json")
        }
    }

    public func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: self.url) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    public func save(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: self.url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: self.url, options: .atomic)
        } catch {
            // Cache failure must never break the live meter.
        }
    }
}

@MainActor
public final class UsageStore: ObservableObject {
    @Published public private(set) var snapshot: UsageSnapshot
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var consecutiveFailures = 0
    @Published public private(set) var lastSuccessfulRefreshAt: Date?
    @Published public private(set) var lastErrorMessage: String?

    private let provider: any CodexUsageProviding
    private let cache: UsageSnapshotCache

    public init(provider: any CodexUsageProviding, cache: UsageSnapshotCache = UsageSnapshotCache()) {
        self.provider = provider
        self.cache = cache
        self.snapshot = cache.load() ?? UsageSnapshot.error("No usage data yet.")
        if self.snapshot.errorMessage == nil, !self.snapshot.isStale {
            self.lastSuccessfulRefreshAt = self.snapshot.updatedAt
        }
    }

    @discardableResult
    public func refresh() async -> Bool {
        guard !self.isRefreshing else { return false }
        self.isRefreshing = true
        defer { self.isRefreshing = false }

        do {
            let snapshot = try await self.provider.fetchUsage()
            self.snapshot = snapshot
            self.consecutiveFailures = 0
            self.lastSuccessfulRefreshAt = snapshot.updatedAt
            self.lastErrorMessage = nil
            self.cache.save(snapshot)
            return true
        } catch {
            let message = UsageSnapshot.sanitized(error.localizedDescription)
            let rateLimitRetryAt = (error as? ClaudeOAuthRateLimitError)?.retryAt
            self.consecutiveFailures += 1
            self.lastErrorMessage = message
            if self.snapshot.sessionPercentRemaining != nil || self.snapshot.weeklyPercentRemaining != nil {
                self.snapshot = self.snapshot.markedStale(
                    errorMessage: message,
                    rateLimitRetryAt: rateLimitRetryAt)
            } else if let cached = self.cache.load(),
                      cached.sessionPercentRemaining != nil || cached.weeklyPercentRemaining != nil
            {
                self.snapshot = cached.markedStale(
                    errorMessage: message,
                    rateLimitRetryAt: rateLimitRetryAt)
            } else {
                self.snapshot = UsageSnapshot.error(message)
            }
            return true
        }
    }

    public func replaceSnapshotForTesting(_ snapshot: UsageSnapshot) {
        self.snapshot = snapshot
        if snapshot.errorMessage == nil, !snapshot.isStale {
            self.lastSuccessfulRefreshAt = snapshot.updatedAt
            self.lastErrorMessage = nil
        } else if let message = snapshot.errorMessage {
            self.lastErrorMessage = message
        }
    }
}
