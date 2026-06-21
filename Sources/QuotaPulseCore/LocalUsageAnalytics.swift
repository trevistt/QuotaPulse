import Combine
import Foundation

public struct LocalUsageDailyBucket: Codable, Equatable, Identifiable, Sendable {
    public let date: String
    public let totalTokens: Int
    public let costUSD: Double?
    public let requestCount: Int

    public var id: String { self.date }

    public init(date: String, totalTokens: Int, costUSD: Double?, requestCount: Int) {
        self.date = date
        self.totalTokens = max(0, totalTokens)
        self.costUSD = costUSD
        self.requestCount = max(0, requestCount)
    }
}

public struct LocalUsageAnalyticsSnapshot: Codable, Equatable, Sendable {
    public let provider: ProviderKind
    public let todayCostUSD: Double?
    public let todayTokens: Int?
    public let last30DaysCostUSD: Double?
    public let last30DaysTokens: Int?
    public let latestTokens: Int?
    public let topModel: String?
    public let dailyHistory: [LocalUsageDailyBucket]
    public let updatedAt: Date
    public let sourceLabel: String
    public let isStale: Bool
    public let errorMessage: String?
    public let isCostPartial: Bool
    public let estimateNote: String

    public init(
        provider: ProviderKind,
        todayCostUSD: Double?,
        todayTokens: Int?,
        last30DaysCostUSD: Double?,
        last30DaysTokens: Int?,
        latestTokens: Int?,
        topModel: String?,
        dailyHistory: [LocalUsageDailyBucket],
        updatedAt: Date,
        sourceLabel: String = "Local logs",
        isStale: Bool = false,
        errorMessage: String? = nil,
        isCostPartial: Bool = false,
        estimateNote: String = "Estimated from local logs at API rates; may differ from your plan or bill.")
    {
        self.provider = provider
        self.todayCostUSD = todayCostUSD
        self.todayTokens = todayTokens
        self.last30DaysCostUSD = last30DaysCostUSD
        self.last30DaysTokens = last30DaysTokens
        self.latestTokens = latestTokens
        self.topModel = topModel
        self.dailyHistory = dailyHistory
        self.updatedAt = updatedAt
        self.sourceLabel = sourceLabel
        self.isStale = isStale
        self.errorMessage = errorMessage.map(UsageSnapshot.sanitized)
        self.isCostPartial = isCostPartial
        self.estimateNote = estimateNote
    }

    public static func unavailable(
        provider: ProviderKind,
        message: String = "No local usage analytics yet.",
        updatedAt: Date = Date())
        -> LocalUsageAnalyticsSnapshot
    {
        LocalUsageAnalyticsSnapshot(
            provider: provider,
            todayCostUSD: nil,
            todayTokens: nil,
            last30DaysCostUSD: nil,
            last30DaysTokens: nil,
            latestTokens: nil,
            topModel: nil,
            dailyHistory: [],
            updatedAt: updatedAt,
            sourceLabel: "Local logs",
            isStale: false,
            errorMessage: message,
            isCostPartial: true)
    }

    public func markedStale(errorMessage: String, updatedAt: Date = Date()) -> LocalUsageAnalyticsSnapshot {
        LocalUsageAnalyticsSnapshot(
            provider: self.provider,
            todayCostUSD: self.todayCostUSD,
            todayTokens: self.todayTokens,
            last30DaysCostUSD: self.last30DaysCostUSD,
            last30DaysTokens: self.last30DaysTokens,
            latestTokens: self.latestTokens,
            topModel: self.topModel,
            dailyHistory: self.dailyHistory,
            updatedAt: updatedAt,
            sourceLabel: self.sourceLabel,
            isStale: true,
            errorMessage: errorMessage,
            isCostPartial: self.isCostPartial,
            estimateNote: self.estimateNote)
    }

    public var hasAnyData: Bool {
        self.todayTokens != nil
            || self.last30DaysTokens != nil
            || self.latestTokens != nil
            || !self.dailyHistory.isEmpty
    }
}

public enum LocalUsageAnalyticsFormatter {
    public static func costText(_ value: Double?) -> String {
        guard let value else { return "unavailable" }
        if value < 0.005 { return "<$0.01" }
        return String(format: "$%.2f", value)
    }

    public static func tokenText(_ value: Int?) -> String {
        guard let value else { return "unavailable" }
        return Self.integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func sourceText(_ snapshot: LocalUsageAnalyticsSnapshot) -> String {
        snapshot.isStale ? "\(snapshot.sourceLabel), stale" : snapshot.sourceLabel
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

public struct LocalUsageAnalyticsCache: Sendable {
    private let url: URL

    public init(url: URL? = nil, provider: ProviderKind) {
        self.url = url ?? FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/QuotaPulse/local-analytics-\(provider.rawValue).json")
    }

    public func load() -> LocalUsageAnalyticsSnapshot? {
        guard let data = try? Data(contentsOf: self.url) else { return nil }
        return try? JSONDecoder().decode(LocalUsageAnalyticsSnapshot.self, from: data)
    }

    public func save(_ snapshot: LocalUsageAnalyticsSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: self.url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: self.url, options: .atomic)
        } catch {
            // Analytics cache failure must never break quota display.
        }
    }
}

public protocol LocalUsageAnalyticsProviding: Sendable {
    func fetchAnalytics() async throws -> LocalUsageAnalyticsSnapshot
}

@MainActor
public final class LocalUsageAnalyticsStore: ObservableObject {
    @Published public private(set) var snapshot: LocalUsageAnalyticsSnapshot
    @Published public private(set) var isRefreshing = false

    private let providerKind: ProviderKind
    private let provider: any LocalUsageAnalyticsProviding
    private let cache: LocalUsageAnalyticsCache

    public init(
        providerKind: ProviderKind,
        provider: any LocalUsageAnalyticsProviding,
        cache: LocalUsageAnalyticsCache)
    {
        self.providerKind = providerKind
        self.provider = provider
        self.cache = cache
        self.snapshot = cache.load() ?? LocalUsageAnalyticsSnapshot.unavailable(provider: providerKind)
    }

    public convenience init(
        providerKind: ProviderKind,
        provider: any LocalUsageAnalyticsProviding,
        cacheURL: URL? = nil)
    {
        self.init(
            providerKind: providerKind,
            provider: provider,
            cache: LocalUsageAnalyticsCache(url: cacheURL, provider: providerKind))
    }

    @discardableResult
    public func refresh() async -> Bool {
        guard !self.isRefreshing else { return false }
        self.isRefreshing = true
        defer { self.isRefreshing = false }

        do {
            let snapshot = try await self.provider.fetchAnalytics()
            self.snapshot = snapshot
            self.cache.save(snapshot)
            return true
        } catch {
            let message = UsageSnapshot.sanitized(error.localizedDescription)
            if self.snapshot.hasAnyData {
                self.snapshot = self.snapshot.markedStale(errorMessage: message)
            } else if let cached = self.cache.load(), cached.hasAnyData {
                self.snapshot = cached.markedStale(errorMessage: message)
            } else {
                self.snapshot = LocalUsageAnalyticsSnapshot.unavailable(
                    provider: self.providerKind,
                    message: message)
            }
            return true
        }
    }

    public func replaceSnapshotForTesting(_ snapshot: LocalUsageAnalyticsSnapshot) {
        self.snapshot = snapshot
    }
}

@MainActor
public final class LocalUsageAnalyticsScheduler: ObservableObject {
    @Published public private(set) var lastRefreshAt: Date?

    private let stores: [LocalUsageAnalyticsStore]
    private let interval: TimeInterval
    private var timer: Timer?

    public init(stores: [LocalUsageAnalyticsStore], interval: TimeInterval = 5 * 60) {
        self.stores = stores
        self.interval = max(60, interval)
    }

    public func start() {
        self.refreshNow()
        self.scheduleNext()
    }

    public func stop() {
        self.timer?.invalidate()
        self.timer = nil
    }

    public func refreshNow() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for store in self.stores {
                _ = await store.refresh()
            }
            self.lastRefreshAt = Date()
        }
    }

    private func scheduleNext() {
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshNow()
            }
        }
    }
}

public struct FixtureLocalUsageAnalyticsProvider: LocalUsageAnalyticsProviding, Sendable {
    public enum Mode: String, Sendable {
        case full
        case empty
        case error
        case codexOnly
    }

    private let provider: ProviderKind
    private let mode: Mode
    private let now: @Sendable () -> Date

    public init(
        provider: ProviderKind,
        mode: Mode = .full,
        now: @escaping @Sendable () -> Date = Date.init)
    {
        self.provider = provider
        self.mode = mode
        self.now = now
    }

    public func fetchAnalytics() async throws -> LocalUsageAnalyticsSnapshot {
        let now = self.now()
        switch self.mode {
        case .error:
            throw LocalUsageAnalyticsError.scanFailed("Local analytics fixture error.")
        case .empty:
            return LocalUsageAnalyticsSnapshot.unavailable(
                provider: self.provider,
                message: "No local analytics data found.",
                updatedAt: now)
        case .codexOnly where self.provider == .claude:
            return LocalUsageAnalyticsSnapshot.unavailable(
                provider: self.provider,
                message: "Claude local analytics unavailable in this fixture.",
                updatedAt: now)
        case .codexOnly, .full:
            let daily = Self.fixtureDaily(now: now, provider: self.provider)
            let today = daily.last
            let totalTokens = daily.reduce(0) { $0 + $1.totalTokens }
            let totalCost = daily.compactMap(\.costUSD).reduce(0, +)
            return LocalUsageAnalyticsSnapshot(
                provider: self.provider,
                todayCostUSD: today?.costUSD,
                todayTokens: today?.totalTokens,
                last30DaysCostUSD: totalCost,
                last30DaysTokens: totalTokens,
                latestTokens: self.provider == .codex ? 18_420 : 11_850,
                topModel: self.provider == .codex ? "gpt-5.4-codex" : "claude-sonnet-4.5",
                dailyHistory: daily,
                updatedAt: now,
                sourceLabel: "Local logs fixture",
                isCostPartial: false)
        }
    }

    private static func fixtureDaily(now: Date, provider: ProviderKind) -> [LocalUsageDailyBucket] {
        let calendar = Calendar(identifier: .gregorian)
        let formatter = LocalUsageLogScanner.dayFormatter
        return (0..<14).map { index in
            let offset = 13 - index
            let date = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let wave = (index % 5) + 1
            let base = provider == .codex ? 18_000 : 12_000
            let tokens = base + wave * (provider == .codex ? 2_900 : 2_100)
            let cost = Double(tokens) * (provider == .codex ? 0.0000042 : 0.0000068)
            return LocalUsageDailyBucket(
                date: formatter.string(from: date),
                totalTokens: tokens,
                costUSD: cost,
                requestCount: 2 + wave)
        }
    }
}

public enum LocalUsageAnalyticsError: LocalizedError, Equatable, Sendable {
    case noLogsFound(String)
    case scanFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .noLogsFound(provider):
            "No \(provider) local usage logs were found."
        case let .scanFailed(message):
            "Local usage analytics scan failed: \(UsageSnapshot.sanitized(message))"
        }
    }
}

public struct CodexLocalLogAnalyticsProvider: LocalUsageAnalyticsProviding, Sendable {
    private let env: [String: String]
    private let codexHome: URL?
    private let now: @Sendable () -> Date
    private let options: LocalUsageLogScanner.Options

    public init(
        env: [String: String] = ProcessInfo.processInfo.environment,
        codexHome: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        options: LocalUsageLogScanner.Options = LocalUsageLogScanner.Options())
    {
        self.env = env
        self.codexHome = codexHome
        self.now = now
        self.options = options
    }

    public func fetchAnalytics() async throws -> LocalUsageAnalyticsSnapshot {
        let now = self.now()
        let roots = Self.codexRoots(env: self.env, codexHome: self.codexHome)
        return try await Task.detached(priority: .utility) {
            try LocalUsageLogScanner.scanCodex(roots: roots, now: now, options: self.options)
        }.value
    }

    public static func codexRoots(env: [String: String], codexHome: URL? = nil) -> [URL] {
        let home = codexHome
            ?? env["CODEX_HOME"].flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        return [
            home.appendingPathComponent("sessions", isDirectory: true),
            home.appendingPathComponent("archived_sessions", isDirectory: true),
        ]
    }
}

public struct ClaudeLocalLogAnalyticsProvider: LocalUsageAnalyticsProviding, Sendable {
    private let env: [String: String]
    private let roots: [URL]?
    private let now: @Sendable () -> Date
    private let options: LocalUsageLogScanner.Options

    public init(
        env: [String: String] = ProcessInfo.processInfo.environment,
        roots: [URL]? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        options: LocalUsageLogScanner.Options = LocalUsageLogScanner.Options())
    {
        self.env = env
        self.roots = roots
        self.now = now
        self.options = options
    }

    public func fetchAnalytics() async throws -> LocalUsageAnalyticsSnapshot {
        let now = self.now()
        let roots = self.roots ?? Self.claudeProjectsRoots(env: self.env)
        return try await Task.detached(priority: .utility) {
            try LocalUsageLogScanner.scanClaude(roots: roots, now: now, options: self.options)
        }.value
    }

    public static func claudeProjectsRoots(env: [String: String]) -> [URL] {
        if let config = env["CLAUDE_CONFIG_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !config.isEmpty
        {
            return config
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { raw in
                    let url = URL(fileURLWithPath: raw, isDirectory: true)
                    return url.lastPathComponent == "projects"
                        ? url
                        : url.appendingPathComponent("projects", isDirectory: true)
                }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(".config/claude/projects", isDirectory: true),
            home.appendingPathComponent(".claude/projects", isDirectory: true),
        ]
    }
}

public enum LocalUsageLogScanner {
    public struct Options: Sendable {
        public var historyDays: Int
        public var maxFiles: Int
        public var maxLineBytes: Int

        public init(historyDays: Int = 30, maxFiles: Int = 5_000, maxLineBytes: Int = 512 * 1024) {
            self.historyDays = max(1, min(365, historyDays))
            self.maxFiles = max(1, maxFiles)
            self.maxLineBytes = max(1_024, maxLineBytes)
        }
    }

    struct Record: Sendable {
        let timestamp: Date
        let model: String
        let inputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
        let outputTokens: Int
        let costUSD: Double?

        var totalTokens: Int {
            self.inputTokens + self.cacheReadTokens + self.cacheCreationTokens + self.outputTokens
        }
    }

    private enum CodexUsageSource {
        case incremental
        case cumulativeTotal
    }

    private struct CodexUsageCandidate {
        let usage: [String: Any]
        let source: CodexUsageSource
    }

    private struct TokenUsageTotals {
        let inputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
        let outputTokens: Int

        var totalTokens: Int {
            self.inputTokens + self.cacheReadTokens + self.cacheCreationTokens + self.outputTokens
        }

        func delta(from previous: TokenUsageTotals) -> TokenUsageTotals {
            TokenUsageTotals(
                inputTokens: max(0, self.inputTokens - previous.inputTokens),
                cacheReadTokens: max(0, self.cacheReadTokens - previous.cacheReadTokens),
                cacheCreationTokens: max(0, self.cacheCreationTokens - previous.cacheCreationTokens),
                outputTokens: max(0, self.outputTokens - previous.outputTokens))
        }
    }

    public static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func scanCodex(roots: [URL], now: Date, options: Options = Options()) throws -> LocalUsageAnalyticsSnapshot {
        let files = self.jsonlFiles(roots: roots, maxFiles: options.maxFiles)
        guard !files.isEmpty else { throw LocalUsageAnalyticsError.noLogsFound("Codex") }
        let records = try files.flatMap { try self.codexRecords(fileURL: $0, options: options) }
        return try self.snapshot(provider: .codex, records: records, now: now, options: options)
    }

    public static func scanClaude(roots: [URL], now: Date, options: Options = Options()) throws -> LocalUsageAnalyticsSnapshot {
        let files = self.jsonlFiles(roots: roots, maxFiles: options.maxFiles)
        guard !files.isEmpty else { throw LocalUsageAnalyticsError.noLogsFound("Claude") }
        let records = try files.flatMap { try self.claudeRecords(fileURL: $0, options: options) }
        return try self.snapshot(provider: .claude, records: records, now: now, options: options)
    }

    static func codexRecords(fileURL: URL, options: Options = Options()) throws -> [Record] {
        var records: [Record] = []
        var currentModel: String?
        var previousTotalUsage: TokenUsageTotals?
        try self.scanJSONLines(fileURL: fileURL, options: options) { object in
            let payload = object["payload"] as? [String: Any]
            if let model = Self.codexModel(from: object, payload: payload, fallback: currentModel) {
                currentModel = model
            }
            guard let timestamp = Self.timestamp(from: object, fallback: payload) else { return }
            guard let candidate = Self.codexUsageCandidate(from: object, payload: payload) else { return }
            let rawUsage = Self.tokenUsageTotals(from: candidate.usage)
            let usage: TokenUsageTotals
            switch candidate.source {
            case .incremental:
                usage = rawUsage
            case .cumulativeTotal:
                if let previousTotalUsage {
                    usage = rawUsage.delta(from: previousTotalUsage)
                } else {
                    usage = TokenUsageTotals(inputTokens: 0, cacheReadTokens: 0, cacheCreationTokens: 0, outputTokens: 0)
                }
                previousTotalUsage = rawUsage
            }
            guard usage.totalTokens > 0 else { return }
            let model = Self.codexModel(from: object, payload: payload, fallback: currentModel)
                ?? "unknown-codex-model"
            records.append(Record(
                timestamp: timestamp,
                model: EstimatedTokenPricing.normalizeModel(model),
                inputTokens: usage.inputTokens,
                cacheReadTokens: usage.cacheReadTokens,
                cacheCreationTokens: usage.cacheCreationTokens,
                outputTokens: usage.outputTokens,
                costUSD: EstimatedTokenPricing.costUSD(
                    provider: .codex,
                    model: model,
                    inputTokens: usage.inputTokens,
                    cacheReadTokens: usage.cacheReadTokens,
                    cacheCreationTokens: usage.cacheCreationTokens,
                    outputTokens: usage.outputTokens)))
        }
        return records
    }

    static func claudeRecords(fileURL: URL, options: Options = Options()) throws -> [Record] {
        var keyed: [String: Record] = [:]
        var unkeyed: [Record] = []
        try self.scanJSONLines(fileURL: fileURL, options: options) { object in
            guard Self.stringValue(object["type"]) == "assistant" else { return }
            guard let timestamp = Self.timestamp(from: object, fallback: nil) else { return }
            guard let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let model = Self.stringValue(message["model"])
            else { return }
            let input = Self.intValue(usage["input_tokens"])
            let cacheRead = Self.intValue(usage["cache_read_input_tokens"])
            let cacheCreate = Self.intValue(usage["cache_creation_input_tokens"])
            let output = Self.intValue(usage["output_tokens"])
            guard input > 0 || cacheRead > 0 || cacheCreate > 0 || output > 0 else { return }
            let record = Record(
                timestamp: timestamp,
                model: EstimatedTokenPricing.normalizeModel(model),
                inputTokens: input,
                cacheReadTokens: cacheRead,
                cacheCreationTokens: cacheCreate,
                outputTokens: output,
                costUSD: EstimatedTokenPricing.costUSD(
                    provider: .claude,
                    model: model,
                    inputTokens: input,
                    cacheReadTokens: cacheRead,
                    cacheCreationTokens: cacheCreate,
                    outputTokens: output))
            if let messageID = Self.stringValue(message["id"]),
               let requestID = Self.stringValue(object["requestId"] ?? object["request_id"])
            {
                keyed["\(fileURL.path):\(messageID):\(requestID)"] = record
            } else {
                unkeyed.append(record)
            }
        }
        return keyed.keys.sorted().compactMap { keyed[$0] } + unkeyed
    }

    private static func snapshot(
        provider: ProviderKind,
        records: [Record],
        now: Date,
        options: Options)
        throws -> LocalUsageAnalyticsSnapshot
    {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -(options.historyDays - 1), to: now) ?? now)
        let todayKey = self.dayFormatter.string(from: now)
        let windowRecords = records.filter { $0.timestamp >= startDate && $0.timestamp <= now.addingTimeInterval(60) }
        guard !windowRecords.isEmpty else {
            return LocalUsageAnalyticsSnapshot.unavailable(
                provider: provider,
                message: "No local analytics rows found in the last \(options.historyDays)d.",
                updatedAt: now)
        }

        var dayTokens: [String: Int] = [:]
        var dayCost: [String: Double] = [:]
        var dayRequests: [String: Int] = [:]
        var modelTokens: [String: Int] = [:]
        var hasUnknownPricing = false
        var latest = windowRecords[0]

        for record in windowRecords {
            let day = self.dayFormatter.string(from: record.timestamp)
            dayTokens[day, default: 0] += record.totalTokens
            dayRequests[day, default: 0] += 1
            modelTokens[record.model, default: 0] += record.totalTokens
            if let cost = record.costUSD {
                dayCost[day, default: 0] += cost
            } else {
                hasUnknownPricing = true
            }
            if record.timestamp >= latest.timestamp {
                latest = record
            }
        }

        let daily = (0..<options.historyDays).map { index -> LocalUsageDailyBucket in
            let date = calendar.date(byAdding: .day, value: -(options.historyDays - 1 - index), to: now) ?? now
            let key = self.dayFormatter.string(from: date)
            return LocalUsageDailyBucket(
                date: key,
                totalTokens: dayTokens[key] ?? 0,
                costUSD: dayCost[key],
                requestCount: dayRequests[key] ?? 0)
        }
        let totalTokens = daily.reduce(0) { $0 + $1.totalTokens }
        let totalCost = daily.compactMap(\.costUSD).reduce(0, +)
        let todayCost = dayCost[todayKey]
        let topModel = modelTokens.max { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key > rhs.key }
            return lhs.value < rhs.value
        }?.key

        return LocalUsageAnalyticsSnapshot(
            provider: provider,
            todayCostUSD: todayCost,
            todayTokens: dayTokens[todayKey],
            last30DaysCostUSD: totalCost > 0 ? totalCost : nil,
            last30DaysTokens: totalTokens,
            latestTokens: latest.totalTokens,
            topModel: topModel,
            dailyHistory: daily,
            updatedAt: now,
            sourceLabel: "Local logs",
            isCostPartial: hasUnknownPricing)
    }

    private static func jsonlFiles(roots: [URL], maxFiles: Int) -> [URL] {
        var files: [URL] = []
        for root in roots {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles])
                else { continue }
                for case let url as URL in enumerator {
                    guard files.count < maxFiles else { return files.sorted { $0.path < $1.path } }
                    guard url.pathExtension == "jsonl" else { continue }
                    files.append(url)
                }
            } else if root.pathExtension == "jsonl" {
                files.append(root)
            }
            guard files.count < maxFiles else { break }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func scanJSONLines(
        fileURL: URL,
        options: Options,
        onObject: ([String: Any]) -> Void)
        throws
    {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var buffer = Data()
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                self.consumeLine(Data(line.prefix(options.maxLineBytes)), onObject: onObject)
            }
        }
        if !buffer.isEmpty {
            self.consumeLine(Data(buffer.prefix(options.maxLineBytes)), onObject: onObject)
        }
    }

    private static func consumeLine(_ line: Data, onObject: ([String: Any]) -> Void) {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return }
        onObject(object)
    }

    private static func usageDictionary(from object: [String: Any], payload: [String: Any]?) -> [String: Any]? {
        if let usage = object["usage"] as? [String: Any] { return usage }
        if let usage = payload?["usage"] as? [String: Any] { return usage }
        if let usage = (payload?["info"] as? [String: Any])?["usage"] as? [String: Any] { return usage }
        if let usage = object["token_usage"] as? [String: Any] { return usage }
        if let usage = payload?["token_usage"] as? [String: Any] { return usage }
        return nil
    }

    private static func codexUsageCandidate(from object: [String: Any], payload: [String: Any]?) -> CodexUsageCandidate? {
        if let usage = self.usageDictionary(from: object, payload: payload) {
            return CodexUsageCandidate(usage: usage, source: .incremental)
        }
        let info = payload?["info"] as? [String: Any]
            ?? object["info"] as? [String: Any]
        if let usage = info?["last_token_usage"] as? [String: Any] {
            return CodexUsageCandidate(usage: usage, source: .incremental)
        }
        if let usage = info?["total_token_usage"] as? [String: Any] {
            return CodexUsageCandidate(usage: usage, source: .cumulativeTotal)
        }
        return nil
    }

    private static func tokenUsageTotals(from usage: [String: Any]) -> TokenUsageTotals {
        let output = Self.intValue(usage["output_tokens"] ?? usage["output"])
            + Self.intValue(usage["reasoning_output_tokens"] ?? usage["reasoning_output"])
        return TokenUsageTotals(
            inputTokens: Self.intValue(usage["input_tokens"] ?? usage["input"]),
            cacheReadTokens: Self.intValue(usage["cached_input_tokens"] ?? usage["cache_read_input_tokens"] ?? usage["cache_read"]),
            cacheCreationTokens: Self.intValue(usage["cache_creation_input_tokens"] ?? usage["cache_creation"]),
            outputTokens: output)
    }

    private static func codexModel(from object: [String: Any], payload: [String: Any]?, fallback: String?) -> String? {
        let info = payload?["info"] as? [String: Any]
            ?? object["info"] as? [String: Any]
        let collaborationMode = payload?["collaboration_mode"] as? [String: Any]
        let collaborationSettings = collaborationMode?["settings"] as? [String: Any]
        return Self.stringValue(info?["model"])
            ?? Self.stringValue(info?["model_name"])
            ?? Self.stringValue(payload?["model"])
            ?? Self.stringValue(object["model"])
            ?? Self.stringValue(collaborationSettings?["model"])
            ?? fallback
    }

    private static func timestamp(from object: [String: Any], fallback: [String: Any]?) -> Date? {
        let raw = self.stringValue(object["timestamp"])
            ?? self.stringValue(object["time"])
            ?? self.stringValue(fallback?["timestamp"])
            ?? self.stringValue(fallback?["time"])
        guard let raw else { return nil }
        return self.parseDate(raw)
    }

    private static func parseDate(_ raw: String) -> Date? {
        if let unix = Double(raw), unix > 1_000_000_000 {
            return Date(timeIntervalSince1970: unix > 9_999_999_999 ? unix / 1000 : unix)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return max(0, value) }
        if let number = value as? NSNumber { return max(0, number.intValue) }
        if let string = value as? String, let int = Int(string) { return max(0, int) }
        return 0
    }
}

public enum EstimatedTokenPricing {
    struct Price {
        let input: Double
        let output: Double
        let cacheRead: Double?
        let cacheCreate: Double?
    }

    public static func costUSD(
        provider: ProviderKind,
        model: String,
        inputTokens: Int,
        cacheReadTokens: Int,
        cacheCreationTokens: Int,
        outputTokens: Int)
        -> Double?
    {
        guard let price = self.price(provider: provider, model: model) else { return nil }
        let inputCost = Double(inputTokens) * price.input
        let outputCost = Double(outputTokens) * price.output
        let cacheReadCost = Double(cacheReadTokens) * (price.cacheRead ?? price.input)
        let cacheCreateCost = Double(cacheCreationTokens) * (price.cacheCreate ?? price.input)
        return inputCost + outputCost + cacheReadCost + cacheCreateCost
    }

    static func normalizeModel(_ model: String) -> String {
        model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func price(provider: ProviderKind, model: String) -> Price? {
        let normalized = self.normalizeModel(model)
        switch provider {
        case .codex:
            if normalized.contains("gpt-5.4") {
                return Price(input: 2.5e-6, output: 15e-6, cacheRead: 0.25e-6, cacheCreate: nil)
            }
            if normalized.contains("gpt-5.3") || normalized.contains("gpt-5.2") {
                return Price(input: 1.75e-6, output: 14e-6, cacheRead: 0.175e-6, cacheCreate: nil)
            }
            if normalized.contains("gpt-5-mini") || normalized.contains("mini") {
                return Price(input: 0.25e-6, output: 2e-6, cacheRead: 0.025e-6, cacheCreate: nil)
            }
            if normalized.contains("gpt-5") {
                return Price(input: 1.25e-6, output: 10e-6, cacheRead: 0.125e-6, cacheCreate: nil)
            }
            return nil
        case .claude:
            if normalized.contains("opus") {
                return Price(input: 15e-6, output: 75e-6, cacheRead: 1.5e-6, cacheCreate: 18.75e-6)
            }
            if normalized.contains("haiku") {
                return Price(input: 0.8e-6, output: 4e-6, cacheRead: 0.08e-6, cacheCreate: 1e-6)
            }
            if normalized.contains("sonnet") || normalized.contains("claude") {
                return Price(input: 3e-6, output: 15e-6, cacheRead: 0.3e-6, cacheCreate: 3.75e-6)
            }
            return nil
        }
    }
}
