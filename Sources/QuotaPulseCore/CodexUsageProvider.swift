import Foundation

public protocol CodexUsageProviding: Sendable {
    func fetchUsage() async throws -> UsageSnapshot
}

public enum CodexUsageProviderError: LocalizedError, Equatable {
    case credentialsNotFound
    case missingCredentials
    case invalidResponse(String)
    case noUsageWindows
    case processFailed(String)
    case timedOut(String)
    case allSourcesFailed([String])

    public var errorDescription: String? {
        switch self {
        case .credentialsNotFound:
            "Codex auth.json was not found."
        case .missingCredentials:
            "Codex auth.json exists but does not contain usable credentials."
        case let .invalidResponse(message):
            "Codex returned invalid usage data: \(UsageSnapshot.sanitized(message))"
        case .noUsageWindows:
            "Codex usage did not include a 5-hour or weekly window."
        case let .processFailed(message):
            "Codex CLI RPC failed: \(UsageSnapshot.sanitized(message))"
        case let .timedOut(method):
            "Codex CLI RPC timed out during \(method)."
        case let .allSourcesFailed(messages):
            "All Codex usage sources failed: \(messages.map(UsageSnapshot.sanitized).joined(separator: " | "))"
        }
    }
}

public struct CascadingCodexUsageProvider: CodexUsageProviding {
    private let providers: [any CodexUsageProviding]

    public init(providers: [any CodexUsageProviding]) {
        self.providers = providers
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        var failures: [String] = []
        for provider in self.providers {
            do {
                return try await provider.fetchUsage()
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        throw CodexUsageProviderError.allSourcesFailed(failures)
    }
}

public struct FixtureCodexUsageProvider: CodexUsageProviding, Sendable {
    public enum Mode: String, Sendable {
        case success
        case weeklyOnly
        case error
    }

    private let mode: Mode
    private let now: @Sendable () -> Date

    public init(mode: Mode = .success, now: @escaping @Sendable () -> Date = Date.init) {
        self.mode = mode
        self.now = now
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let date = self.now()
        switch self.mode {
        case .success:
            return UsageSnapshot.fromWindows(
                primary: UsageWindow(
                    usedPercent: 37,
                    resetAt: date.addingTimeInterval(2 * 3_600 + 18 * 60),
                    windowSeconds: 18_000),
                secondary: UsageWindow(
                    usedPercent: 61,
                    resetAt: date.addingTimeInterval(2 * 86_400 + 4 * 3_600),
                    windowSeconds: 604_800),
                extraWindows: [
                    UsageNamedWindow(
                        id: "codex-spark",
                        title: "Codex Spark 5-hour",
                        window: UsageWindow(
                            usedPercent: 28,
                            resetAt: date.addingTimeInterval(3 * 3_600 + 8 * 60),
                            windowSeconds: 18_000)),
                    UsageNamedWindow(
                        id: "codex-spark-weekly",
                        title: "Codex Spark Weekly",
                        window: UsageWindow(
                            usedPercent: 46,
                            resetAt: date.addingTimeInterval(3 * 86_400 + 6 * 3_600),
                            windowSeconds: 604_800)),
                ],
                source: .fixture,
                updatedAt: date)
        case .weeklyOnly:
            return UsageSnapshot.fromWindows(
                primary: UsageWindow(
                    usedPercent: 12,
                    resetAt: date.addingTimeInterval(4 * 86_400),
                    windowSeconds: 604_800),
                secondary: nil,
                source: .fixture,
                updatedAt: date)
        case .error:
            throw CodexUsageProviderError.noUsageWindows
        }
    }
}
