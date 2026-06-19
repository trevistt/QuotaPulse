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
public final class RefreshScheduler {
    public private(set) var cadence: RefreshCadence

    private let stores: [UsageStore]
    private let policy: RefreshBackoffPolicy
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    public init(
        store: UsageStore,
        cadence: RefreshCadence = .normal,
        policy: RefreshBackoffPolicy = RefreshBackoffPolicy())
    {
        self.stores = [store]
        self.cadence = cadence
        self.policy = policy
    }

    public init(
        stores: [UsageStore],
        cadence: RefreshCadence = .normal,
        policy: RefreshBackoffPolicy = RefreshBackoffPolicy())
    {
        self.stores = stores
        self.cadence = cadence
        self.policy = policy
    }

    public func start() {
        self.refreshNow()
    }

    public func stop() {
        self.timer?.invalidate()
        self.timer = nil
        self.refreshTask?.cancel()
        self.refreshTask = nil
    }

    public func setCadence(_ cadence: RefreshCadence) {
        self.cadence = cadence
        self.scheduleNext()
    }

    public func refreshNow() {
        guard self.refreshTask == nil else { return }
        self.timer?.invalidate()
        self.timer = nil
        self.refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for store in self.stores {
                _ = await store.refresh()
            }
            self.refreshTask = nil
            self.scheduleNext()
        }
    }

    private func scheduleNext() {
        self.timer?.invalidate()
        let delay = self.policy.delay(
            base: self.cadence.interval,
            consecutiveFailures: self.stores.map(\.consecutiveFailures).max() ?? 0)
        self.timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
    }
}
