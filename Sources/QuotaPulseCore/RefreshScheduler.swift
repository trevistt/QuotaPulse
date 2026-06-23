import Combine
import Foundation

public enum RefreshCadence: String, CaseIterable, Identifiable, Sendable {
    case fast
    case normal
    case batterySaver

    public var id: String { self.rawValue }

    public var interval: TimeInterval {
        switch self {
        case .fast:
            30
        case .normal:
            60
        case .batterySaver:
            300
        }
    }

    public var label: String {
        switch self {
        case .fast:
            "30s"
        case .normal:
            "1m"
        case .batterySaver:
            "5m"
        }
    }
}

public enum RefreshMode: String, CaseIterable, Identifiable, Sendable {
    case auto
    case seconds30
    case oneMinute
    case fiveMinutes
    case tenMinutes
    case manual

    public var id: String { self.rawValue }

    public var label: String {
        switch self {
        case .auto:
            "Auto"
        case .seconds30:
            "30s"
        case .oneMinute:
            "1m"
        case .fiveMinutes:
            "5m"
        case .tenMinutes:
            "10m"
        case .manual:
            "Manual"
        }
    }

    public var interval: TimeInterval? {
        switch self {
        case .auto, .manual:
            nil
        case .seconds30:
            30
        case .oneMinute:
            60
        case .fiveMinutes:
            300
        case .tenMinutes:
            600
        }
    }

    public static func allowedModes(for provider: ProviderKind) -> [RefreshMode] {
        switch provider {
        case .codex:
            [.auto, .seconds30, .oneMinute, .fiveMinutes, .manual]
        case .claude:
            [.auto, .seconds30, .oneMinute, .fiveMinutes, .tenMinutes, .manual]
        }
    }
}

public enum UserPresenceState: String, Codable, Sendable, Equatable {
    case active
    case idle
    case locked
    case screensaver
    case asleep
    case suspended

    public var pausesAutomaticRefresh: Bool {
        switch self {
        case .active, .idle:
            false
        case .locked, .screensaver, .asleep, .suspended:
            true
        }
    }

    public var pausedText: String? {
        switch self {
        case .active, .idle:
            nil
        case .locked:
            "Paused: screen locked"
        case .screensaver:
            "Paused: screensaver"
        case .asleep:
            "Paused: asleep"
        case .suspended:
            "Paused: suspended"
        }
    }
}

public struct RefreshJitter: Sendable {
    private let randomUnit: @Sendable () -> Double

    public init(randomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }) {
        self.randomUnit = randomUnit
    }

    public static let none = RefreshJitter(randomUnit: { 0.5 })

    public func delay(base: TimeInterval) -> TimeInterval {
        let boundedUnit = min(1, max(0, self.randomUnit()))
        let offset = (boundedUnit * 2 - 1) * Self.bound(for: base)
        return max(1, base + offset)
    }

    public static func bound(for base: TimeInterval) -> TimeInterval {
        switch base {
        case ..<60:
            5
        case ..<300:
            10
        case ..<600:
            30
        default:
            60
        }
    }
}

public struct ProviderRefreshState: Equatable, Sendable {
    public let provider: ProviderKind
    public var mode: RefreshMode
    public var isRefreshing: Bool
    public var nextRefreshAt: Date?
    public var cooldownUntil: Date?
    public var authBlockedReason: String?
    public var pausedReason: UserPresenceState?
    public var lastStatusText: String
    public var unchangedSuccesses: Int

    public init(
        provider: ProviderKind,
        mode: RefreshMode = .auto,
        isRefreshing: Bool = false,
        nextRefreshAt: Date? = nil,
        cooldownUntil: Date? = nil,
        authBlockedReason: String? = nil,
        pausedReason: UserPresenceState? = nil,
        lastStatusText: String = "Ready",
        unchangedSuccesses: Int = 0)
    {
        self.provider = provider
        self.mode = mode
        self.isRefreshing = isRefreshing
        self.nextRefreshAt = nextRefreshAt
        self.cooldownUntil = cooldownUntil
        self.authBlockedReason = authBlockedReason.map(UsageSnapshot.sanitized)
        self.pausedReason = pausedReason
        self.lastStatusText = lastStatusText
        self.unchangedSuccesses = unchangedSuccesses
    }
}

public enum ProviderRefreshPolicy {
    public static let claudeFastModeDuration: TimeInterval = 12 * 60
    public static let wakeRefreshDelay: TimeInterval = 6

    public static func automaticBaseDelay(
        provider: ProviderKind,
        presence: UserPresenceState,
        dashboardVisible: Bool,
        unchangedSuccesses: Int,
        fastModeUntil: Date?,
        now: Date)
        -> TimeInterval?
    {
        guard !presence.pausesAutomaticRefresh else { return nil }

        switch provider {
        case .codex:
            if presence == .idle { return unchangedSuccesses >= 2 ? 300 : 60 }
            if unchangedSuccesses >= 2, !dashboardVisible { return 60 }
            return 30
        case .claude:
            if presence == .idle { return 300 }
            if unchangedSuccesses >= 3 { return 300 }
            if let fastModeUntil, fastModeUntil > now { return 30 }
            return 300
        }
    }
}

public struct RefreshBackoffPolicy: Sendable {
    public let maximumDelay: TimeInterval

    public init(maximumDelay: TimeInterval = 15 * 60) {
        self.maximumDelay = maximumDelay
    }

    public func delay(base: TimeInterval, consecutiveFailures: Int) -> TimeInterval {
        guard consecutiveFailures > 0 else { return base }
        let multiplier = pow(2.0, Double(min(consecutiveFailures, 4)))
        return min(self.maximumDelay, base * multiplier)
    }
}

public actor RefreshGate {
    private var running = false

    public init() {}

    public func run(_ operation: @Sendable () async -> Void) async -> Bool {
        guard !self.running else { return false }
        self.running = true
        defer { self.running = false }
        await operation()
        return true
    }
}

@MainActor
public final class RefreshScheduler: ObservableObject {
    @Published public private(set) var codexState: ProviderRefreshState
    @Published public private(set) var claudeState: ProviderRefreshState
    @Published public private(set) var presence: UserPresenceState = .active
    @Published public private(set) var dashboardVisible = false
    public private(set) var cadence: RefreshCadence

    private let stores: [ProviderKind: UsageStore]
    private let policy: RefreshBackoffPolicy
    private let jitter: RefreshJitter
    private let now: @Sendable () -> Date
    private var timers: [ProviderKind: Timer] = [:]
    private var fastModeUntil: [ProviderKind: Date] = [:]
    private var previousSnapshots: [ProviderKind: UsageSnapshot] = [:]

    public init(
        store: UsageStore,
        cadence: RefreshCadence = .normal,
        policy: RefreshBackoffPolicy = RefreshBackoffPolicy(),
        jitter: RefreshJitter = RefreshJitter(),
        now: @escaping @Sendable () -> Date = Date.init)
    {
        self.stores = [.codex: store]
        self.cadence = cadence
        self.policy = policy
        self.jitter = jitter
        self.now = now
        self.codexState = ProviderRefreshState(provider: .codex)
        self.claudeState = ProviderRefreshState(provider: .claude, mode: .manual, lastStatusText: "Unavailable")
    }

    public init(
        stores: [UsageStore],
        cadence: RefreshCadence = .normal,
        policy: RefreshBackoffPolicy = RefreshBackoffPolicy(),
        jitter: RefreshJitter = RefreshJitter(),
        now: @escaping @Sendable () -> Date = Date.init)
    {
        var mapped: [ProviderKind: UsageStore] = [:]
        if let codexStore = stores.first {
            mapped[.codex] = codexStore
        }
        if stores.indices.contains(1) {
            mapped[.claude] = stores[1]
        }
        self.stores = mapped
        self.cadence = cadence
        self.policy = policy
        self.jitter = jitter
        self.now = now
        self.codexState = ProviderRefreshState(provider: .codex)
        self.claudeState = ProviderRefreshState(provider: .claude)
    }

    public func start() {
        self.refreshNow()
    }

    public func stop() {
        for timer in self.timers.values {
            timer.invalidate()
        }
        self.timers = [:]
        self.codexState.nextRefreshAt = nil
        self.claudeState.nextRefreshAt = nil
    }

    public func setCadence(_ cadence: RefreshCadence) {
        self.cadence = cadence
        let mode: RefreshMode = {
            switch cadence {
            case .fast:
                .seconds30
            case .normal:
                .oneMinute
            case .batterySaver:
                .fiveMinutes
            }
        }()
        self.setMode(mode, for: .codex)
        self.setMode(mode, for: .claude)
    }

    public func mode(for provider: ProviderKind) -> RefreshMode {
        self.state(for: provider).mode
    }

    public func state(for provider: ProviderKind) -> ProviderRefreshState {
        switch provider {
        case .codex:
            self.codexState
        case .claude:
            self.claudeState
        }
    }

    public func setMode(_ mode: RefreshMode, for provider: ProviderKind) {
        guard RefreshMode.allowedModes(for: provider).contains(mode) else { return }
        self.updateState(for: provider) { state in
            state.mode = mode
            state.lastStatusText = mode == .manual ? "Manual mode" : "Ready"
        }
        self.scheduleNext(for: provider)
    }

    public func setDashboardVisible(_ visible: Bool) {
        guard self.dashboardVisible != visible else { return }
        self.dashboardVisible = visible
        self.rescheduleAutomaticProviders()
    }

    public func updatePresence(_ newPresence: UserPresenceState) {
        let wasPaused = self.presence.pausesAutomaticRefresh
        self.presence = newPresence
        if newPresence.pausesAutomaticRefresh {
            for provider in ProviderKind.allCases {
                self.timers[provider]?.invalidate()
                self.timers[provider] = nil
                self.updateState(for: provider) { state in
                    state.nextRefreshAt = nil
                    state.pausedReason = newPresence
                    state.lastStatusText = newPresence.pausedText ?? "Paused"
                }
            }
            return
        }

        for provider in ProviderKind.allCases {
            self.updateState(for: provider) { state in
                state.pausedReason = nil
            }
        }

        if wasPaused {
            self.scheduleWakeRefresh()
        } else {
            self.rescheduleAutomaticProviders()
        }
    }

    public func refreshNow() {
        for provider in ProviderKind.allCases {
            self.refresh(provider: provider, manual: true)
        }
    }

    public func repairClaudeLogin() {
        self.updateState(for: .claude) { state in
            state.authBlockedReason = nil
            state.cooldownUntil = nil
            state.nextRefreshAt = nil
            state.lastStatusText = "Repairing Claude login..."
        }
        self.refresh(provider: .claude, manual: true)
    }

    public func markClaudeAuthBlockedForTesting(reason: String = UsageSnapshot.claudeLoginExpiredMessage) {
        self.updateState(for: .claude) { state in
            state.isRefreshing = false
            state.authBlockedReason = reason
            state.cooldownUntil = nil
            state.nextRefreshAt = nil
            state.lastStatusText = "Claude login needs repair"
        }
    }

    public func refresh(provider: ProviderKind, manual: Bool) {
        guard let store = self.stores[provider] else { return }
        let state = self.state(for: provider)
        if state.isRefreshing || store.isRefreshing {
            self.updateState(for: provider) { state in
                state.isRefreshing = true
                state.lastStatusText = "Refreshing..."
            }
            return
        }
        if self.presence.pausesAutomaticRefresh,
           (!manual || self.presence == .asleep || self.presence == .suspended)
        {
            self.updateState(for: provider) { state in
                state.pausedReason = self.presence
                state.lastStatusText = self.presence.pausedText ?? "Paused"
                state.nextRefreshAt = nil
            }
            return
        }
        if !manual, state.mode == .manual {
            self.updateState(for: provider) { state in
                state.nextRefreshAt = nil
                state.lastStatusText = "Manual mode"
            }
            return
        }
        if provider == .claude,
           state.authBlockedReason != nil,
           !manual
        {
            self.updateState(for: provider) { state in
                state.nextRefreshAt = nil
                state.cooldownUntil = nil
                state.lastStatusText = "Claude login needs repair"
            }
            return
        }
        if provider == .claude,
           let cooldownUntil = state.cooldownUntil,
           cooldownUntil > self.now()
        {
            self.updateState(for: provider) { state in
                state.nextRefreshAt = cooldownUntil
                state.lastStatusText = "Claude cooldown: retry in \(UsageSnapshot.countdown(to: cooldownUntil, now: self.now()))"
            }
            return
        }

        self.timers[provider]?.invalidate()
        self.timers[provider] = nil
        self.updateState(for: provider) { state in
            state.isRefreshing = true
            state.nextRefreshAt = nil
            state.lastStatusText = "Refreshing..."
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard await store.refresh() else {
                self.updateState(for: provider) { state in
                    state.isRefreshing = store.isRefreshing
                    state.lastStatusText = store.isRefreshing ? "Refreshing..." : state.lastStatusText
                }
                return
            }
            self.finishRefresh(for: provider, snapshot: store.snapshot)
        }
    }

    public var summaryText: String {
        self.summaryText(now: self.now())
    }

    public func summaryText(now: Date) -> String {
        if let paused = self.presence.pausedText {
            return paused
        }
        if self.claudeState.authBlockedReason != nil {
            return "Claude login needs repair; Codex keeps refreshing."
        }
        if let cooldown = self.claudeState.cooldownUntil,
           cooldown > now
        {
            return "Claude cooldown: retry in \(Self.refreshCountdown(to: cooldown, now: now))"
        }
        return "Next: Codex \(self.nextText(for: .codex, now: now)) · Claude \(self.nextText(for: .claude, now: now))"
    }

    public func nextText(for provider: ProviderKind) -> String {
        self.nextText(for: provider, now: self.now())
    }

    public func nextText(for provider: ProviderKind, now: Date) -> String {
        let state = self.state(for: provider)
        if state.isRefreshing { return "now" }
        if state.authBlockedReason != nil { return "Login" }
        if state.mode == .manual { return "Manual" }
        guard let nextRefreshAt = state.nextRefreshAt else { return "soon" }
        return Self.refreshCountdown(to: nextRefreshAt, now: now)
    }

    public static func refreshCountdown(to date: Date, now: Date = Date()) -> String {
        let remaining = max(0, Int(ceil(date.timeIntervalSince(now))))
        if remaining < 60 { return "\(remaining)s" }
        let minutes = Int(ceil(Double(remaining) / 60.0))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    public func refreshProviderForTesting(_ provider: ProviderKind, manual: Bool = true) async {
        guard let store = self.stores[provider] else { return }
        if self.presence.pausesAutomaticRefresh {
            self.updateState(for: provider) { state in
                state.pausedReason = self.presence
                state.lastStatusText = self.presence.pausedText ?? "Paused"
            }
            return
        }
        _ = await store.refresh()
        self.finishRefresh(for: provider, snapshot: store.snapshot)
        if manual {
            self.scheduleNext(for: provider)
        }
    }

    private func finishRefresh(for provider: ProviderKind, snapshot: UsageSnapshot) {
        let previous = self.previousSnapshots[provider]
        let changed = previous.map { !Self.sameUsage($0, snapshot) } ?? true
        self.previousSnapshots[provider] = snapshot
        let retryAt = snapshot.rateLimitRetryAt
        if provider == .claude, changed, !snapshot.isStale, snapshot.errorMessage == nil {
            self.fastModeUntil[provider] = self.now().addingTimeInterval(ProviderRefreshPolicy.claudeFastModeDuration)
        }
        if provider == .claude, retryAt != nil {
            self.fastModeUntil[provider] = nil
        }
        let authBlockedReason = provider == .claude && snapshot.isAuthBlocked
            ? UsageSnapshot.claudeLoginExpiredMessage
            : nil

        self.updateState(for: provider) { state in
            state.isRefreshing = false
            state.authBlockedReason = authBlockedReason
            state.cooldownUntil = authBlockedReason == nil ? retryAt : nil
            state.nextRefreshAt = authBlockedReason == nil ? state.nextRefreshAt : nil
            state.unchangedSuccesses = (!snapshot.isStale && snapshot.errorMessage == nil)
                ? (changed ? 0 : state.unchangedSuccesses + 1)
                : state.unchangedSuccesses
            if authBlockedReason != nil {
                state.lastStatusText = "Claude login needs repair"
            } else if let retryAt, retryAt > self.now() {
                state.lastStatusText = "Claude cooldown: retry in \(Self.refreshCountdown(to: retryAt, now: self.now()))"
            } else if snapshot.isStale {
                state.lastStatusText = snapshot.errorMessage ?? "Stale"
            } else if snapshot.errorMessage != nil {
                state.lastStatusText = snapshot.errorMessage ?? "Error"
            } else {
                state.lastStatusText = "Updated just now"
            }
        }
        self.scheduleNext(for: provider)
    }

    private func scheduleWakeRefresh() {
        for provider in ProviderKind.allCases {
            guard self.state(for: provider).mode != .manual else { continue }
            let delay = self.jitter.delay(base: ProviderRefreshPolicy.wakeRefreshDelay)
            self.schedule(provider: provider, delay: delay, statusText: "Refresh after wake")
        }
    }

    private func rescheduleAutomaticProviders() {
        for provider in ProviderKind.allCases {
            self.scheduleNext(for: provider)
        }
    }

    private func scheduleNext(for provider: ProviderKind) {
        self.timers[provider]?.invalidate()
        self.timers[provider] = nil
        guard self.stores[provider] != nil else { return }

        var state = self.state(for: provider)
        if self.presence.pausesAutomaticRefresh {
            state.nextRefreshAt = nil
            state.pausedReason = self.presence
            state.lastStatusText = self.presence.pausedText ?? "Paused"
            self.setState(state, for: provider)
            return
        }
        state.pausedReason = nil

        if provider == .claude,
           state.authBlockedReason != nil
        {
            state.nextRefreshAt = nil
            state.cooldownUntil = nil
            state.lastStatusText = "Claude login needs repair"
            self.setState(state, for: provider)
            return
        }

        if provider == .claude,
           let cooldownUntil = state.cooldownUntil,
           cooldownUntil > self.now()
        {
            self.setState(state, for: provider)
            self.schedule(provider: provider, until: cooldownUntil, statusText: "Claude cooldown")
            return
        }

        let baseDelay: TimeInterval?
        if let explicit = state.mode.interval {
            baseDelay = explicit
        } else if state.mode == .manual {
            state.nextRefreshAt = nil
            state.lastStatusText = "Manual mode"
            self.setState(state, for: provider)
            return
        } else {
            baseDelay = ProviderRefreshPolicy.automaticBaseDelay(
                provider: provider,
                presence: self.presence,
                dashboardVisible: self.dashboardVisible,
                unchangedSuccesses: state.unchangedSuccesses,
                fastModeUntil: self.fastModeUntil[provider],
                now: self.now())
        }

        guard let baseDelay else {
            state.nextRefreshAt = nil
            self.setState(state, for: provider)
            return
        }
        let delay = self.jitter.delay(base: baseDelay)
        self.setState(state, for: provider)
        self.schedule(provider: provider, delay: delay, statusText: "Next refresh")
    }

    private func schedule(provider: ProviderKind, until date: Date, statusText: String) {
        self.schedule(provider: provider, delay: max(1, date.timeIntervalSince(self.now())), statusText: statusText)
    }

    private func schedule(provider: ProviderKind, delay: TimeInterval, statusText: String) {
        let nextDate = self.now().addingTimeInterval(delay)
        self.updateState(for: provider) { state in
            state.nextRefreshAt = nextDate
            state.lastStatusText = statusText
        }
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(provider: provider, manual: false)
            }
        }
        self.timers[provider] = timer
    }

    private func updateState(for provider: ProviderKind, mutate: (inout ProviderRefreshState) -> Void) {
        var state = self.state(for: provider)
        mutate(&state)
        self.setState(state, for: provider)
    }

    private func setState(_ state: ProviderRefreshState, for provider: ProviderKind) {
        switch provider {
        case .codex:
            self.codexState = state
        case .claude:
            self.claudeState = state
        }
    }

    private static func sameUsage(_ lhs: UsageSnapshot, _ rhs: UsageSnapshot) -> Bool {
        lhs.sessionPercentRemaining == rhs.sessionPercentRemaining
            && lhs.weeklyPercentRemaining == rhs.weeklyPercentRemaining
            && lhs.sessionResetAt == rhs.sessionResetAt
            && lhs.weeklyResetAt == rhs.weeklyResetAt
    }
}
