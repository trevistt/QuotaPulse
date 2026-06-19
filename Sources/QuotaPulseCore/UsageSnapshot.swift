import Foundation

public enum ProviderKind: String, Codable, Sendable, CaseIterable {
    case codex
    case claude

    public var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        }
    }

    public var compactName: String {
        switch self {
        case .codex:
            "Cx"
        case .claude:
            "Cl"
        }
    }
}

public enum UsageSource: String, Codable, Sendable, CaseIterable {
    case oauth = "OAuth"
    case cliRPC = "CLI RPC"
    case claudeCLI = "CLI"
    case localFallback = "local fallback"
    case fixture = "fixture"
    case disabled = "disabled"
    case error = "error"
}

public enum UsageWindowRole: String, Codable, Sendable {
    case session
    case weekly
    case unknown
}

public struct UsageWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let resetAt: Date?
    public let windowSeconds: Int?

    public init(usedPercent: Double, resetAt: Date?, windowSeconds: Int?) {
        self.usedPercent = Self.clampPercent(usedPercent)
        self.resetAt = resetAt
        self.windowSeconds = windowSeconds
    }

    public var remainingPercent: Double {
        Self.clampPercent(100 - self.usedPercent)
    }

    public var role: UsageWindowRole {
        switch self.windowSeconds {
        case 18_000:
            .session
        case 604_800:
            .weekly
        default:
            .unknown
        }
    }

    static func clampPercent(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}

public struct UsageNamedWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let window: UsageWindow
    public let detail: String?

    public init(id: String, title: String, window: UsageWindow, detail: String? = nil) {
        self.id = id
        self.title = title
        self.window = window
        self.detail = detail
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let sessionPercentRemaining: Double?
    public let weeklyPercentRemaining: Double?
    public let sessionResetAt: Date?
    public let weeklyResetAt: Date?
    public let extraWindows: [UsageNamedWindow]
    public let source: UsageSource
    public let updatedAt: Date
    public let isStale: Bool
    public let errorMessage: String?

    public init(
        sessionPercentRemaining: Double?,
        weeklyPercentRemaining: Double?,
        sessionResetAt: Date?,
        weeklyResetAt: Date?,
        extraWindows: [UsageNamedWindow] = [],
        source: UsageSource,
        updatedAt: Date,
        isStale: Bool = false,
        errorMessage: String? = nil)
    {
        self.sessionPercentRemaining = sessionPercentRemaining.map(UsageWindow.clampPercent)
        self.weeklyPercentRemaining = weeklyPercentRemaining.map(UsageWindow.clampPercent)
        self.sessionResetAt = sessionResetAt
        self.weeklyResetAt = weeklyResetAt
        self.extraWindows = extraWindows
        self.source = source
        self.updatedAt = updatedAt
        self.isStale = isStale
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case sessionPercentRemaining
        case weeklyPercentRemaining
        case sessionResetAt
        case weeklyResetAt
        case extraWindows
        case source
        case updatedAt
        case isStale
        case errorMessage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionPercentRemaining: try container.decodeIfPresent(Double.self, forKey: .sessionPercentRemaining),
            weeklyPercentRemaining: try container.decodeIfPresent(Double.self, forKey: .weeklyPercentRemaining),
            sessionResetAt: try container.decodeIfPresent(Date.self, forKey: .sessionResetAt),
            weeklyResetAt: try container.decodeIfPresent(Date.self, forKey: .weeklyResetAt),
            extraWindows: (try? container.decodeIfPresent([UsageNamedWindow].self, forKey: .extraWindows)) ?? [],
            source: try container.decode(UsageSource.self, forKey: .source),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt),
            isStale: try container.decodeIfPresent(Bool.self, forKey: .isStale) ?? false,
            errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.sessionPercentRemaining, forKey: .sessionPercentRemaining)
        try container.encodeIfPresent(self.weeklyPercentRemaining, forKey: .weeklyPercentRemaining)
        try container.encodeIfPresent(self.sessionResetAt, forKey: .sessionResetAt)
        try container.encodeIfPresent(self.weeklyResetAt, forKey: .weeklyResetAt)
        try container.encode(self.extraWindows, forKey: .extraWindows)
        try container.encode(self.source, forKey: .source)
        try container.encode(self.updatedAt, forKey: .updatedAt)
        try container.encode(self.isStale, forKey: .isStale)
        try container.encodeIfPresent(self.errorMessage, forKey: .errorMessage)
    }

    public static func fromWindows(
        primary: UsageWindow?,
        secondary: UsageWindow?,
        extraWindows: [UsageNamedWindow] = [],
        source: UsageSource,
        updatedAt: Date = Date()) -> UsageSnapshot
    {
        let normalized = UsageWindowNormalizer.normalize(primary: primary, secondary: secondary)
        return UsageSnapshot(
            sessionPercentRemaining: normalized.session?.remainingPercent,
            weeklyPercentRemaining: normalized.weekly?.remainingPercent,
            sessionResetAt: normalized.session?.resetAt,
            weeklyResetAt: normalized.weekly?.resetAt,
            extraWindows: extraWindows,
            source: source,
            updatedAt: updatedAt)
    }

    public static func error(_ message: String, updatedAt: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            sessionPercentRemaining: nil,
            weeklyPercentRemaining: nil,
            sessionResetAt: nil,
            weeklyResetAt: nil,
            extraWindows: [],
            source: .error,
            updatedAt: updatedAt,
            isStale: false,
            errorMessage: Self.sanitized(message))
    }

    public func markedStale(errorMessage: String, updatedAt: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            sessionPercentRemaining: self.sessionPercentRemaining,
            weeklyPercentRemaining: self.weeklyPercentRemaining,
            sessionResetAt: self.sessionResetAt,
            weeklyResetAt: self.weeklyResetAt,
            extraWindows: self.extraWindows,
            source: self.source,
            updatedAt: updatedAt,
            isStale: true,
            errorMessage: Self.sanitized(errorMessage))
    }

    public var primaryDisplayText: String {
        if let sessionPercentRemaining {
            return "\(Int(sessionPercentRemaining.rounded()))%"
        }
        if errorMessage != nil {
            return "ERR"
        }
        return "No 5h"
    }

    public var sourceLabel: String {
        if self.source == .error { return UsageSource.error.rawValue }
        return self.isStale ? "\(self.source.rawValue), stale" : self.source.rawValue
    }

    public func resetCountdown(now: Date = Date()) -> String {
        guard let resetAt = self.sessionResetAt ?? self.weeklyResetAt else {
            return "unknown"
        }
        return Self.countdown(to: resetAt, now: now)
    }

    public func sessionWindow() -> UsageWindow? {
        guard let sessionPercentRemaining else { return nil }
        return UsageWindow(
            usedPercent: 100 - sessionPercentRemaining,
            resetAt: self.sessionResetAt,
            windowSeconds: 18_000)
    }

    public func weeklyWindow() -> UsageWindow? {
        guard let weeklyPercentRemaining else { return nil }
        return UsageWindow(
            usedPercent: 100 - weeklyPercentRemaining,
            resetAt: self.weeklyResetAt,
            windowSeconds: 604_800)
    }

    public static func countdown(to date: Date, now: Date = Date()) -> String {
        let remaining = max(0, Int(ceil(date.timeIntervalSince(now))))
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func sanitized(_ message: String) -> String {
        var output = message
        let patterns = [
            #"Bearer\s+[A-Za-z0-9._\-]+"#,
            #"sk-[A-Za-z0-9_\-]+"#,
            #""access_token"\s*:\s*"[^"]+""#,
            #""refresh_token"\s*:\s*"[^"]+""#,
            #""id_token"\s*:\s*"[^"]+""#,
        ]
        for pattern in patterns {
            output = output.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: .regularExpression)
        }
        return output
    }
}

public enum UsageDisplayFormatter {
    public struct ProviderLine: Equatable, Sendable {
        public let provider: ProviderKind
        public let value: String

        public var compactText: String {
            "\(self.provider.compactName) \(self.value)"
        }

        public var accessibilityText: String {
            "\(self.provider.displayName) \(self.value)"
        }
    }

    public static func title(codex: UsageSnapshot, claude: UsageSnapshot) -> String {
        "\(ProviderKind.codex.displayName) \(codex.primaryDisplayText)  \(ProviderKind.claude.displayName) \(claude.primaryDisplayText)"
    }

    public static func compactTitle(codex: UsageSnapshot, claude: UsageSnapshot) -> String {
        self.menuBarCompactText(codex: codex, claude: claude)
    }

    public static func menuBarLines(codex: UsageSnapshot, claude: UsageSnapshot) -> [ProviderLine] {
        [
            ProviderLine(provider: .codex, value: Self.menuBarValue(codex)),
            ProviderLine(provider: .claude, value: Self.menuBarValue(claude)),
        ]
    }

    public static func menuBarMultilineText(codex: UsageSnapshot, claude: UsageSnapshot) -> String {
        self.menuBarLines(codex: codex, claude: claude)
            .map(\.compactText)
            .joined(separator: "\n")
    }

    public static func menuBarCompactText(codex: UsageSnapshot, claude: UsageSnapshot) -> String {
        self.menuBarLines(codex: codex, claude: claude)
            .map(\.compactText)
            .joined(separator: "  ")
    }

    public static func menuBarAccessibilityText(codex: UsageSnapshot, claude: UsageSnapshot) -> String {
        self.menuBarLines(codex: codex, claude: claude)
            .map(\.accessibilityText)
            .joined(separator: ", ")
    }

    public static func progressFraction(forRemainingPercent percent: Double?) -> Double? {
        guard let percent else { return nil }
        return UsageWindow.clampPercent(percent) / 100
    }

    private static func menuBarValue(_ snapshot: UsageSnapshot) -> String {
        if let value = snapshot.sessionPercentRemaining {
            return "\(Int(value.rounded()))%"
        }
        if snapshot.errorMessage != nil {
            return "ERR"
        }
        return "--"
    }
}

public enum UsageWindowNormalizer {
    public static func normalize(
        primary: UsageWindow?,
        secondary: UsageWindow?) -> (session: UsageWindow?, weekly: UsageWindow?)
    {
        var session: UsageWindow?
        var weekly: UsageWindow?
        var unknowns: [UsageWindow] = []

        for window in [primary, secondary].compactMap({ $0 }) {
            switch window.role {
            case .session where session == nil:
                session = window
            case .weekly where weekly == nil:
                weekly = window
            default:
                unknowns.append(window)
            }
        }

        if session == nil {
            session = unknowns.first
            if !unknowns.isEmpty {
                unknowns.removeFirst()
            }
        }
        if weekly == nil {
            weekly = unknowns.first
        }

        return (session, weekly)
    }
}
