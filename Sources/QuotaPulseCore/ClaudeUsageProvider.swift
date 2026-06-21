import Foundation

#if os(macOS)
import LocalAuthentication
import Security
#endif

public struct ClaudeOAuthCredentials: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let scopes: [String]

    public init(accessToken: String, refreshToken: String?, expiresAt: Date?, scopes: [String]) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
    }
}

public enum ClaudeUsageProviderError: LocalizedError, Equatable {
    case liveReadDisabled
    case missingCredentials
    case invalidResponse(String)
    case keychainAccessNotEnabled
    case keychainAccessDenied
    case keychainReadFailed(String)
    case noUsageWindows
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .liveReadDisabled:
            "Claude usage is unavailable: OAuth credentials were not found and CLI fallback is disabled."
        case .missingCredentials:
            "Claude credentials do not contain a usable OAuth access token."
        case let .invalidResponse(message):
            "Claude returned invalid usage data: \(UsageSnapshot.sanitized(message))"
        case .keychainAccessNotEnabled:
            "Claude OAuth Keychain discovery is disabled. Set QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN=1 to allow a user-approved Claude Code Keychain read."
        case .keychainAccessDenied:
            "Claude OAuth Keychain access was denied or unavailable."
        case let .keychainReadFailed(message):
            "Claude OAuth Keychain read failed: \(UsageSnapshot.sanitized(message))"
        case .noUsageWindows:
            "Claude usage did not include a 5-hour or weekly window."
        case let .processFailed(message):
            "Claude OAuth usage failed: \(UsageSnapshot.sanitized(message))"
        }
    }
}

public struct ClaudeOAuthRateLimitError: LocalizedError, Equatable, Sendable {
    public let retryAt: Date
    private let message: String

    public init(retryAt: Date, now: Date) {
        self.retryAt = retryAt
        self.message = "Rate limited. Try again in \(UsageSnapshot.countdown(to: retryAt, now: now))."
    }

    public var errorDescription: String? {
        self.message
    }
}

public enum ClaudeOAuthCredentialSource: String, Equatable, Sendable {
    case credentialsFile
    case appOAuthCache
    case claudeCodeKeychain
}

public struct ClaudeOAuthCredentialRecord: Equatable, Sendable {
    public let credentials: ClaudeOAuthCredentials
    public let source: ClaudeOAuthCredentialSource

    public init(credentials: ClaudeOAuthCredentials, source: ClaudeOAuthCredentialSource) {
        self.credentials = credentials
        self.source = source
    }
}

public protocol ClaudeOAuthCredentialResolving: Sendable {
    func loadRecord(env: [String: String]) throws -> ClaudeOAuthCredentialRecord
}

public struct ClaudeOAuthCredentialsStoreResolver: ClaudeOAuthCredentialResolving {
    public init() {}

    public func loadRecord(env: [String: String]) throws -> ClaudeOAuthCredentialRecord {
        try ClaudeOAuthCredentialsStore.loadRecord(env: env)
    }
}

public protocol ClaudeOAuthKeychainReading: Sendable {
    func readClaudeOAuthCredentialData(allowUserPrompt: Bool) throws -> Data?
}

public enum ClaudeOAuthCredentialsStore {
    public static let claudeCodeKeychainService = "Claude Code-credentials"

    public static func credentialsFileURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = QuotaPulseEnvironment.value("QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH", in: env) {
            return URL(fileURLWithPath: override)
        }
        if let configDir = env["CLAUDE_CONFIG_DIR"]?.split(separator: ",").first, !configDir.isEmpty {
            return URL(fileURLWithPath: String(configDir)).appendingPathComponent(".credentials.json")
        }
        let home = env["HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/.credentials.json")
    }

    public static func oauthCacheURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = QuotaPulseEnvironment.value("QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH", in: env) {
            return URL(fileURLWithPath: override)
        }
        let home = env["HOME"].map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/QuotaPulse/ClaudeOAuth/credentials.json")
    }

    public static func isKeychainDiscoveryEnabled(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        QuotaPulseEnvironment.isEnabled("QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN", in: env)
    }

    public static func isKeychainPromptAllowed(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        QuotaPulseEnvironment.isEnabled("QUOTA_PULSE_ALLOW_CLAUDE_KEYCHAIN_PROMPT", in: env)
    }

    public static func load(env: [String: String] = ProcessInfo.processInfo.environment) throws -> ClaudeOAuthCredentials {
        try self.loadRecord(env: env).credentials
    }

    public static func loadRecord(
        env: [String: String] = ProcessInfo.processInfo.environment,
        keychainReader: any ClaudeOAuthKeychainReading = ClaudeCodeKeychainCredentialReader())
        throws -> ClaudeOAuthCredentialRecord
    {
        let url = self.credentialsFileURL(env: env)
        let hasExplicitCredentialPath = QuotaPulseEnvironment.isExplicitlySet(
            "QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH",
            in: env)
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            return ClaudeOAuthCredentialRecord(
                credentials: try self.parse(data: data),
                source: .credentialsFile)
        }
        if hasExplicitCredentialPath {
            throw ClaudeUsageProviderError.missingCredentials
        }

        let cacheURL = self.oauthCacheURL(env: env)
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            let data = try Data(contentsOf: cacheURL)
            return ClaudeOAuthCredentialRecord(
                credentials: try self.parse(data: data),
                source: .appOAuthCache)
        }

        guard self.isKeychainDiscoveryEnabled(env: env) else {
            throw ClaudeUsageProviderError.missingCredentials
        }

        let allowUserPrompt = self.isKeychainPromptAllowed(env: env)
        guard let keychainData = try keychainReader.readClaudeOAuthCredentialData(allowUserPrompt: allowUserPrompt),
              !keychainData.isEmpty
        else {
            throw ClaudeUsageProviderError.missingCredentials
        }
        return ClaudeOAuthCredentialRecord(
            credentials: try self.parse(data: keychainData),
            source: .claudeCodeKeychain)
    }

    public static func parse(data: Data) throws -> ClaudeOAuthCredentials {
        let response: ClaudeCredentialsFile
        do {
            response = try JSONDecoder().decode(ClaudeCredentialsFile.self, from: data)
        } catch {
            throw ClaudeUsageProviderError.invalidResponse(error.localizedDescription)
        }

        let oauth = response.claudeAiOauth
        guard let accessToken = oauth?.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty else
        {
            throw ClaudeUsageProviderError.missingCredentials
        }
        let expiresAt = oauth?.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000.0) }
        return ClaudeOAuthCredentials(
            accessToken: accessToken,
            refreshToken: oauth?.refreshToken,
            expiresAt: expiresAt,
            scopes: oauth?.scopes ?? [])
    }
}

public struct ClaudeCodeKeychainCredentialReader: ClaudeOAuthKeychainReading {
    public init() {}

    public func readClaudeOAuthCredentialData(allowUserPrompt: Bool) throws -> Data? {
        #if os(macOS)
        if let data = try Self.readNewestCandidateData(allowUserPrompt: allowUserPrompt) {
            return data
        }
        return try Self.readLegacyData(allowUserPrompt: allowUserPrompt)
        #else
        _ = allowUserPrompt
        throw ClaudeUsageProviderError.keychainReadFailed("Keychain is only available on macOS.")
        #endif
    }

    #if os(macOS)
    private struct Candidate {
        let persistentRef: Data
        let modifiedAt: Date?
        let createdAt: Date?
    }

    private static func readNewestCandidateData(allowUserPrompt: Bool) throws -> Data? {
        let candidates = try Self.candidatesWithoutPrompt()
        guard let candidate = candidates.first else { return nil }
        return try Self.readData(
            persistentRef: candidate.persistentRef,
            allowUserPrompt: allowUserPrompt)
    }

    private static func candidatesWithoutPrompt() throws -> [Candidate] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ClaudeOAuthCredentialsStore.claudeCodeKeychainService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnPersistentRef as String: true,
        ]
        Self.applyNoUI(to: &query)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let rows = result as? [[String: Any]] else { return [] }
            return rows.compactMap { row in
                guard let persistentRef = row[kSecValuePersistentRef as String] as? Data else { return nil }
                return Candidate(
                    persistentRef: persistentRef,
                    modifiedAt: row[kSecAttrModificationDate as String] as? Date,
                    createdAt: row[kSecAttrCreationDate as String] as? Date)
            }
            .sorted { lhs, rhs in
                let lhsDate = lhs.modifiedAt ?? lhs.createdAt ?? .distantPast
                let rhsDate = rhs.modifiedAt ?? rhs.createdAt ?? .distantPast
                return lhsDate > rhsDate
            }
        case errSecItemNotFound, errSecInteractionNotAllowed:
            return []
        case errSecUserCanceled, errSecAuthFailed, errSecNoAccessForItem:
            throw ClaudeUsageProviderError.keychainAccessDenied
        default:
            throw ClaudeUsageProviderError.keychainReadFailed("status \(status)")
        }
    }

    private static func readData(persistentRef: Data, allowUserPrompt: Bool) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecValuePersistentRef as String: persistentRef,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        if !allowUserPrompt {
            Self.applyNoUI(to: &query)
        }
        return try Self.copyData(query: query, allowUserPrompt: allowUserPrompt)
    }

    private static func readLegacyData(allowUserPrompt: Bool) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ClaudeOAuthCredentialsStore.claudeCodeKeychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        if !allowUserPrompt {
            Self.applyNoUI(to: &query)
        }
        return try Self.copyData(query: query, allowUserPrompt: allowUserPrompt)
    }

    private static func copyData(query: [String: Any], allowUserPrompt: Bool) throws -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            if allowUserPrompt {
                throw ClaudeUsageProviderError.keychainAccessDenied
            }
            return nil
        case errSecUserCanceled, errSecAuthFailed, errSecNoAccessForItem:
            throw ClaudeUsageProviderError.keychainAccessDenied
        default:
            throw ClaudeUsageProviderError.keychainReadFailed("status \(status)")
        }
    }

    private static func applyNoUI(to query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecUseAuthenticationUI as String] = "u_AuthUIF" as CFString
    }
    #endif
}

public struct ImmediateFailureUsageProvider: CodexUsageProviding, Sendable {
    private let message: String
    private let now: @Sendable () -> Date

    public init(message: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.message = UsageSnapshot.sanitized(message)
        self.now = now
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        UsageSnapshot.error(self.message, updatedAt: self.now())
    }
}

public struct FixtureClaudeUsageProvider: CodexUsageProviding, Sendable {
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
                    usedPercent: 15,
                    resetAt: date.addingTimeInterval(3 * 3_600 + 12 * 60),
                    windowSeconds: 18_000),
                secondary: UsageWindow(
                    usedPercent: 42,
                    resetAt: date.addingTimeInterval(3 * 86_400 + 2 * 3_600),
                    windowSeconds: 604_800),
                extraWindows: [
                    UsageNamedWindow(
                        id: "claude-sonnet-weekly",
                        title: "Claude Sonnet Weekly",
                        window: UsageWindow(
                            usedPercent: 35,
                            resetAt: date.addingTimeInterval(3 * 86_400 + 2 * 3_600),
                            windowSeconds: 604_800)),
                    UsageNamedWindow(
                        id: "claude-routines",
                        title: "Daily Routines",
                        window: UsageWindow(
                            usedPercent: 18,
                            resetAt: date.addingTimeInterval(19 * 3_600),
                            windowSeconds: 604_800)),
                ],
                source: .fixture,
                updatedAt: date)
        case .weeklyOnly:
            return UsageSnapshot.fromWindows(
                primary: nil,
                secondary: UsageWindow(
                    usedPercent: 44,
                    resetAt: date.addingTimeInterval(3 * 86_400),
                    windowSeconds: 604_800),
                source: .fixture,
                updatedAt: date)
        case .error:
            throw ClaudeUsageProviderError.noUsageWindows
        }
    }
}

public struct DisabledClaudeUsageProvider: CodexUsageProviding, Sendable {
    private let message: String
    private let now: @Sendable () -> Date

    public init(
        message: String = ClaudeUsageProviderError.liveReadDisabled.localizedDescription,
        now: @escaping @Sendable () -> Date = Date.init)
    {
        self.message = UsageSnapshot.sanitized(message)
        self.now = now
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        UsageSnapshot(
            sessionPercentRemaining: nil,
            weeklyPercentRemaining: nil,
            sessionResetAt: nil,
            weeklyResetAt: nil,
            source: .disabled,
            updatedAt: self.now(),
            errorMessage: self.message)
    }
}

public struct OAuthClaudeUsageProvider<Client: UsageHTTPClient>: CodexUsageProviding, Sendable {
    public static var betaHeaderValue: String { "oauth-2025-04-20" }
    public static var fallbackClaudeCodeVersion: String { "2.1.0" }
    public static var fallbackRateLimitCooldown: TimeInterval { 5 * 60 }

    private let credentials: ClaudeOAuthCredentials
    private let env: [String: String]
    private let httpClient: Client
    private let now: @Sendable () -> Date

    public init(
        credentials: ClaudeOAuthCredentials,
        env: [String: String] = ProcessInfo.processInfo.environment,
        httpClient: Client,
        now: @escaping @Sendable () -> Date = Date.init)
    {
        self.credentials = credentials
        self.env = env
        self.httpClient = httpClient
        self.now = now
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL(env: self.env))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(self.credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.claudeCodeUserAgent(env: self.env), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.betaHeaderValue, forHTTPHeaderField: "anthropic-beta")

        let (data, response) = try await self.httpClient.data(for: request)
        let responseDate = self.now()
        switch response.statusCode {
        case 200...299:
            return try Self.mapUsageResponse(data, source: .oauth, updatedAt: responseDate)
        case 401, 403:
            throw ClaudeUsageProviderError.processFailed("OAuth unauthorized; run Claude to refresh login.")
        case 429:
            throw ClaudeOAuthRateLimitError(
                retryAt: Self.retryAt(from: response, now: responseDate),
                now: responseDate)
        default:
            throw ClaudeUsageProviderError.processFailed("HTTP \(response.statusCode)")
        }
    }

    public static func usageURL(env: [String: String]) -> URL {
        if let override = QuotaPulseEnvironment.value("QUOTA_PULSE_CLAUDE_USAGE_URL", in: env),
           let url = URL(string: override)
        {
            return url
        }
        return URL(string: "https://api.anthropic.com/api/oauth/usage")!
    }

    public static func claudeCodeUserAgent(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let version = self.normalizedClaudeCodeVersion(
            QuotaPulseEnvironment.value("QUOTA_PULSE_CLAUDE_CODE_VERSION", in: env)
                ?? env["CLAUDE_CODE_VERSION"])
            ?? self.fallbackClaudeCodeVersion
        return "claude-code/\(version)"
    }

    public static func mapUsageResponse(
        _ data: Data,
        source: UsageSource,
        updatedAt: Date = Date()) throws -> UsageSnapshot
    {
        let response: ClaudeOAuthUsageResponse
        do {
            response = try JSONDecoder().decode(ClaudeOAuthUsageResponse.self, from: data)
        } catch {
            throw ClaudeUsageProviderError.invalidResponse(error.localizedDescription)
        }

        let snapshot = UsageSnapshot.fromWindows(
            primary: response.fiveHour?.usageWindow(windowSeconds: 18_000),
            secondary: response.sevenDay?.usageWindow(windowSeconds: 604_800),
            extraWindows: response.extraWindows,
            source: source,
            updatedAt: updatedAt)
        guard snapshot.sessionPercentRemaining != nil || snapshot.weeklyPercentRemaining != nil else {
            throw ClaudeUsageProviderError.noUsageWindows
        }
        return snapshot
    }

    public static func parseISO8601Date(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func normalizedClaudeCodeVersion(_ versionString: String?) -> String? {
        guard let raw = versionString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else {
            return nil
        }
        let token = raw.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? raw
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func retryAt(from response: HTTPURLResponse, now: Date) -> Date {
        guard let header = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !header.isEmpty
        else {
            return now.addingTimeInterval(Self.fallbackRateLimitCooldown)
        }

        if let seconds = TimeInterval(header) {
            return now.addingTimeInterval(max(0, seconds))
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: header) ?? now.addingTimeInterval(Self.fallbackRateLimitCooldown)
    }
}

public actor ReloadingClaudeOAuthUsageProvider<Client: UsageHTTPClient, Resolver: ClaudeOAuthCredentialResolving>: CodexUsageProviding {
    private var currentRecord: ClaudeOAuthCredentialRecord?
    private var nextAllowedRefreshAt: Date?
    private let env: [String: String]
    private let httpClient: Client
    private let credentialResolver: Resolver
    private let now: @Sendable () -> Date

    public init(
        initialRecord: ClaudeOAuthCredentialRecord? = nil,
        env: [String: String] = ProcessInfo.processInfo.environment,
        httpClient: Client,
        credentialResolver: Resolver,
        now: @escaping @Sendable () -> Date = Date.init)
    {
        self.currentRecord = initialRecord
        self.env = env
        self.httpClient = httpClient
        self.credentialResolver = credentialResolver
        self.now = now
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let currentDate = self.now()
        if let nextAllowedRefreshAt {
            guard nextAllowedRefreshAt <= currentDate else {
                throw ClaudeOAuthRateLimitError(retryAt: nextAllowedRefreshAt, now: currentDate)
            }
            self.nextAllowedRefreshAt = nil
        }

        let record = try self.currentRecord ?? self.loadRecord()
        do {
            let snapshot = try await self.fetchUsage(with: record)
            self.nextAllowedRefreshAt = nil
            return snapshot
        } catch let rateLimitError as ClaudeOAuthRateLimitError {
            self.nextAllowedRefreshAt = rateLimitError.retryAt
            throw rateLimitError
        } catch let authError {
            guard Self.shouldRetryAfterReload(authError) else {
                throw authError
            }
            let reloadedRecord: ClaudeOAuthCredentialRecord
            do {
                reloadedRecord = try self.loadRecord()
            } catch {
                throw authError
            }
            do {
                let snapshot = try await self.fetchUsage(with: reloadedRecord)
                self.nextAllowedRefreshAt = nil
                return snapshot
            } catch let rateLimitError as ClaudeOAuthRateLimitError {
                self.nextAllowedRefreshAt = rateLimitError.retryAt
                throw rateLimitError
            }
        }
    }

    private func loadRecord() throws -> ClaudeOAuthCredentialRecord {
        let record = try self.credentialResolver.loadRecord(env: self.env)
        self.currentRecord = record
        return record
    }

    private func fetchUsage(with record: ClaudeOAuthCredentialRecord) async throws -> UsageSnapshot {
        self.currentRecord = record
        let provider = OAuthClaudeUsageProvider(
            credentials: record.credentials,
            env: self.env,
            httpClient: self.httpClient,
            now: self.now)
        return try await provider.fetchUsage()
    }

    private static func shouldRetryAfterReload(_ error: Error) -> Bool {
        UsageSnapshot.isAuthFailureMessage(error.localizedDescription)
    }
}

private struct ClaudeCredentialsFile: Decodable {
    let claudeAiOauth: ClaudeCredentialsOAuth?
}

private struct ClaudeCredentialsOAuth: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Double?
    let scopes: [String]?
}

private struct ClaudeOAuthUsageResponse: Decodable {
    let fiveHour: ClaudeOAuthWindow?
    let sevenDay: ClaudeOAuthWindow?
    let sevenDaySonnet: ClaudeOAuthWindow?
    let sevenDayOpus: ClaudeOAuthWindow?
    let sevenDayRoutines: ClaudeOAuthWindow?
    let sevenDayCowork: ClaudeOAuthWindow?
    let extraUsage: ClaudeOAuthExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case sevenDayRoutines = "seven_day_routines"
        case sevenDayCowork = "seven_day_cowork"
        case extraUsage = "extra_usage"
    }

    var extraWindows: [UsageNamedWindow] {
        var windows: [UsageNamedWindow] = []
        if let sonnet = self.sevenDaySonnet?.usageWindow(windowSeconds: 604_800) {
            windows.append(UsageNamedWindow(id: "claude-sonnet-weekly", title: "Claude Sonnet Weekly", window: sonnet))
        }
        if let opus = self.sevenDayOpus?.usageWindow(windowSeconds: 604_800) {
            windows.append(UsageNamedWindow(id: "claude-opus-weekly", title: "Claude Opus Weekly", window: opus))
        }
        if let routines = (self.sevenDayRoutines ?? self.sevenDayCowork)?.usageWindow(windowSeconds: 604_800) {
            windows.append(UsageNamedWindow(id: "claude-routines", title: "Daily Routines", window: routines))
        }
        if let extra = self.extraUsage?.usageWindow {
            windows.append(extra)
        }
        return windows
    }
}

private struct ClaudeOAuthWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.utilization = try container.flexibleDoubleIfPresent(forKey: .utilization)
        self.resetsAt = try? container.decodeIfPresent(String.self, forKey: .resetsAt)
    }

    func usageWindow(windowSeconds: Int) -> UsageWindow? {
        guard let utilization else { return nil }
        return UsageWindow(
            usedPercent: utilization,
            resetAt: OAuthClaudeUsageProvider<URLSessionUsageHTTPClient>.parseISO8601Date(self.resetsAt),
            windowSeconds: windowSeconds)
    }
}

private struct ClaudeOAuthExtraUsage: Decodable {
    let isEnabled: Bool?
    let monthlyLimit: Double?
    let usedCredits: Double?
    let utilization: Double?
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.flexibleBoolIfPresent(forKey: .isEnabled)
        self.monthlyLimit = try container.flexibleDoubleIfPresent(forKey: .monthlyLimit)
        self.usedCredits = try container.flexibleDoubleIfPresent(forKey: .usedCredits)
        self.utilization = try container.flexibleDoubleIfPresent(forKey: .utilization)
        self.currency = try? container.decodeIfPresent(String.self, forKey: .currency)
    }

    var usageWindow: UsageNamedWindow? {
        guard self.isEnabled != false else { return nil }
        let usedPercent: Double
        if let utilization {
            usedPercent = utilization
        } else if let usedCredits,
                  let monthlyLimit,
                  monthlyLimit > 0
        {
            usedPercent = (usedCredits / monthlyLimit) * 100
        } else {
            return nil
        }
        return UsageNamedWindow(
            id: "claude-extra-usage",
            title: "Extra Usage",
            window: UsageWindow(usedPercent: usedPercent, resetAt: nil, windowSeconds: nil),
            detail: self.detailText)
    }

    private var detailText: String? {
        guard let usedCredits,
              let monthlyLimit
        else {
            return self.isEnabled == true ? "Monthly cap" : nil
        }
        let code = self.currency?.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = (code?.isEmpty == false) ? "\(code!) " : ""
        return "Monthly cap \(prefix)\(Self.moneyText(usedCredits)) / \(prefix)\(Self.moneyText(monthlyLimit))"
    }

    private static func moneyText(_ minorUnits: Double) -> String {
        let major = minorUnits / 100
        return String(format: "%.2f", major)
    }
}

extension KeyedDecodingContainer {
    func flexibleBoolIfPresent(forKey key: Key) throws -> Bool? {
        guard self.contains(key), (try? self.decodeNil(forKey: key)) == false else { return nil }
        if let value = try? self.decode(Bool.self, forKey: key) { return value }
        if let value = try? self.decode(Int.self, forKey: key) { return value != 0 }
        if let value = try? self.decode(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                break
            }
        }
        throw DecodingError.typeMismatch(
            Bool.self,
            DecodingError.Context(codingPath: self.codingPath + [key], debugDescription: "Expected boolean"))
    }
}
