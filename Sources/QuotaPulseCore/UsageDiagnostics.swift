import Foundation

public struct UsageDiagnosticsProviderState: Equatable, Sendable {
    public let provider: ProviderKind
    public let lastSuccessfulRefreshAt: Date?
    public let lastErrorMessage: String?
    public let snapshot: UsageSnapshot
    public let refreshState: ProviderRefreshState
    public let analytics: LocalUsageAnalyticsSnapshot
    public let analyticsLastSuccessfulRefreshAt: Date?
    public let analyticsLastErrorMessage: String?

    public init(
        provider: ProviderKind,
        lastSuccessfulRefreshAt: Date?,
        lastErrorMessage: String?,
        snapshot: UsageSnapshot,
        refreshState: ProviderRefreshState,
        analytics: LocalUsageAnalyticsSnapshot,
        analyticsLastSuccessfulRefreshAt: Date?,
        analyticsLastErrorMessage: String?)
    {
        self.provider = provider
        self.lastSuccessfulRefreshAt = lastSuccessfulRefreshAt
        self.lastErrorMessage = lastErrorMessage
        self.snapshot = snapshot
        self.refreshState = refreshState
        self.analytics = analytics
        self.analyticsLastSuccessfulRefreshAt = analyticsLastSuccessfulRefreshAt
        self.analyticsLastErrorMessage = analyticsLastErrorMessage
    }
}

public enum UsageDiagnosticsFormatter {
    public static func errorCategory(_ message: String?) -> String {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "None"
        }
        let lowercased = message.lowercased()
        if UsageSnapshot.isRateLimitMessage(message) { return "Rate limited" }
        if UsageSnapshot.isAuthFailureMessage(message) { return "Auth blocked" }
        if lowercased.contains("credential") || lowercased.contains("oauth access token") {
            return "Credentials unavailable"
        }
        if lowercased.contains("keychain") { return "Keychain unavailable" }
        if lowercased.contains("timeout") || lowercased.contains("timed out") {
            return "Timeout"
        }
        if lowercased.contains("network") || lowercased.contains("offline") || lowercased.contains("internet") {
            return "Network"
        }
        if lowercased.contains("local usage") || lowercased.contains("logs") || lowercased.contains("jsonl") {
            return "Local analytics"
        }
        if lowercased.contains("disabled") { return "Disabled" }
        return "Error"
    }

    public static func errorCategory(provider: ProviderKind, snapshot: UsageSnapshot, lastErrorMessage: String?) -> String {
        if provider == .claude, snapshot.isAuthBlocked {
            return "Auth blocked"
        }
        return self.errorCategory(lastErrorMessage ?? snapshot.errorMessage)
    }

    public static func lastSuccessfulText(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "No successful refresh yet" }
        return Self.relativeText(prefix: "Success", date: date, now: now)
    }

    public static func analyticsStatusText(
        _ snapshot: LocalUsageAnalyticsSnapshot,
        lastSuccessfulRefreshAt: Date?,
        lastErrorMessage: String?,
        now: Date = Date())
        -> String
    {
        let success = lastSuccessfulRefreshAt.map { Self.relativeText(prefix: "Updated", date: $0, now: now) }
            ?? (snapshot.hasAnyData ? Self.relativeText(prefix: "Updated", date: snapshot.updatedAt, now: now) : "No scan data yet")
        let error = Self.errorCategory(lastErrorMessage ?? snapshot.errorMessage)
        guard error != "None" else { return success }
        return "\(success) · Error \(error)"
    }

    public static func refreshText(state: ProviderRefreshState, now: Date = Date()) -> String {
        if state.isRefreshing { return "Refreshing now" }
        if let paused = state.pausedReason?.pausedText {
            return paused.replacingOccurrences(of: "Paused: ", with: "Paused ")
        }
        if let authBlockedReason = state.authBlockedReason {
            return "Paused for login repair: \(UsageSnapshot.sanitized(authBlockedReason))"
        }
        if state.provider == .claude,
           let cooldown = state.cooldownUntil,
           cooldown > now
        {
            return "Cooldown \(Self.refreshCountdown(to: cooldown, now: now))"
        }
        if state.mode == .manual { return "Manual mode" }
        if let nextRefreshAt = state.nextRefreshAt {
            return "Next \(Self.refreshCountdown(to: nextRefreshAt, now: now))"
        }
        return state.lastStatusText
    }

    public static func credentialMode(provider: ProviderKind, snapshot: UsageSnapshot) -> String {
        switch provider {
        case .codex:
            switch snapshot.source {
            case .oauth:
                return "OAuth auth file"
            case .cliRPC:
                return "Codex CLI RPC fallback"
            case .localFallback:
                return "Local usage fallback"
            case .fixture:
                return "Fixture data"
            case .disabled:
                return "Disabled"
            case .claudeCLI:
                return "Not used for Codex"
            case .error:
                return "OAuth/CLI/local cascade unavailable"
            }
        case .claude:
            switch snapshot.source {
            case .oauth:
                return "Claude login"
            case .claudeCLI:
                return "Explicit Claude CLI fallback"
            case .fixture:
                return "Fixture data"
            case .disabled:
                return "Safe startup: Claude login not checked"
            case .error:
                return "OAuth unavailable; CLI off"
            case .cliRPC, .localFallback:
                return "Not used for Claude"
            }
        }
    }

    public static func nextAction(provider: ProviderKind, snapshot: UsageSnapshot) -> String {
        if provider == .claude {
            if snapshot.hasRateLimitError {
                return "Wait for cooldown, then press Refresh."
            }
            if snapshot.hasAuthFailureError {
                return "Click Fix Claude Login. If it stays blocked, open Claude Code, run /logout, then /login, return here, and press Refresh."
            }
            if snapshot.source == .disabled || self.errorCategory(snapshot.errorMessage) == "Credentials unavailable" {
                return "Safe startup avoids login prompts. Click Fix Claude Login only while you are at this Mac."
            }
        }
        if snapshot.errorMessage != nil {
            return "Press Refresh; check provider login if it stays unavailable."
        }
        if snapshot.isStale {
            return "Showing cached value until the next successful refresh."
        }
        return "No action needed."
    }

    public static func safeExport(
        states: [UsageDiagnosticsProviderState],
        providerOrder: [ProviderKind],
        now: Date = Date())
        -> String
    {
        let orderedStates = ProviderKind.normalizedOrder(providerOrder).compactMap { provider in
            states.first { $0.provider == provider }
        }
        var lines: [String] = [
            "QuotaPulse Diagnostics",
            "Generated: \(Self.iso(now))",
            "Safe export: tokens, cookies, Authorization headers, auth JSON, and full credential paths are redacted.",
        ]

        for state in orderedStates {
            lines.append("")
            lines.append("[\(state.provider.displayName)]")
            lines.append("Source: \(state.snapshot.sourceLabel)")
            lines.append("Credential mode: \(Self.credentialMode(provider: state.provider, snapshot: state.snapshot))")
            lines.append("Last successful refresh: \(Self.lastSuccessfulText(state.lastSuccessfulRefreshAt, now: now))")
            lines.append("Last error category: \(Self.errorCategory(provider: state.provider, snapshot: state.snapshot, lastErrorMessage: state.lastErrorMessage))")
            lines.append("Refresh mode: \(state.refreshState.mode.label)")
            lines.append("Refresh status: \(Self.refreshText(state: state.refreshState, now: now))")
            lines.append("Local analytics: \(Self.analyticsStatusText(state.analytics, lastSuccessfulRefreshAt: state.analyticsLastSuccessfulRefreshAt, lastErrorMessage: state.analyticsLastErrorMessage, now: now))")
            lines.append("Next action: \(Self.nextAction(provider: state.provider, snapshot: state.snapshot))")
        }

        return Self.sanitizedDiagnosticsText(lines.joined(separator: "\n"))
    }

    public static func sanitizedDiagnosticsText(_ text: String) -> String {
        var output = UsageSnapshot.sanitized(text)
        let pathPatterns = [
            #"~/(?:\.claude|\.codex|Library)/(?:[^\s,;:]+)"#,
            #"/Users/[^\s,;:]+"#,
            #"/private/[^\s,;:]+"#,
            #"/var/[^\s,;:]+"#,
            #"/Volumes/[^\s,;:]+"#,
        ]
        for pattern in pathPatterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "[path]",
                options: .regularExpression)
        }
        return output
    }

    private static func relativeText(prefix: String, date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(prefix) just now" }
        if seconds < 3_600 { return "\(prefix) \(max(1, seconds / 60))m ago" }
        if seconds < 86_400 { return "\(prefix) \(max(1, seconds / 3_600))h ago" }
        return "\(prefix) \(max(1, seconds / 86_400))d ago"
    }

    private static func refreshCountdown(to date: Date, now: Date) -> String {
        let remaining = max(0, Int(ceil(date.timeIntervalSince(now))))
        if remaining < 60 { return "\(remaining)s" }
        let minutes = Int(ceil(Double(remaining) / 60.0))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
