import Foundation

public actor RateLimitedUsageProvider: CodexUsageProviding {
    private let provider: any CodexUsageProviding
    private let minimumInterval: TimeInterval
    private let now: @Sendable () -> Date
    private var lastSnapshot: UsageSnapshot?
    private var lastFetchAt: Date?

    public init(
        provider: any CodexUsageProviding,
        minimumInterval: TimeInterval,
        now: @escaping @Sendable () -> Date = Date.init)
    {
        self.provider = provider
        self.minimumInterval = minimumInterval
        self.now = now
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let currentDate = self.now()
        if let lastSnapshot,
           let lastFetchAt,
           currentDate.timeIntervalSince(lastFetchAt) < self.minimumInterval
        {
            return lastSnapshot
        }

        let snapshot = try await self.provider.fetchUsage()
        self.lastSnapshot = snapshot
        self.lastFetchAt = currentDate
        return snapshot
    }
}
