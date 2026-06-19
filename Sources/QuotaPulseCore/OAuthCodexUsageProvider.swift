import Foundation

public struct CodexOAuthCredentials: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let accountId: String?

    public init(accessToken: String, refreshToken: String?, idToken: String?, accountId: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.idToken = idToken
        self.accountId = accountId
    }
}

public enum CodexOAuthCredentialsStore {
    public static func authFileURL(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = QuotaPulseEnvironment.value("QUOTA_PULSE_AUTH_PATH", in: env) {
            return URL(fileURLWithPath: override)
        }
        let root: URL
        if let codexHome = env["CODEX_HOME"], !codexHome.isEmpty {
            root = URL(fileURLWithPath: codexHome)
        } else {
            root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        }
        return root.appendingPathComponent("auth.json")
    }

    public static func load(env: [String: String] = ProcessInfo.processInfo.environment) throws -> CodexOAuthCredentials {
        let url = self.authFileURL(env: env)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CodexUsageProviderError.credentialsNotFound
        }
        let data = try Data(contentsOf: url)
        return try self.parse(data: data)
    }

    public static func parse(data: Data) throws -> CodexOAuthCredentials {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexUsageProviderError.invalidResponse("auth.json is not a JSON object")
        }

        if let apiKey = object["OPENAI_API_KEY"] as? String,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return CodexOAuthCredentials(
                accessToken: apiKey,
                refreshToken: nil,
                idToken: nil,
                accountId: nil)
        }

        guard let tokens = object["tokens"] as? [String: Any] else {
            throw CodexUsageProviderError.missingCredentials
        }
        guard let accessToken = Self.stringValue(in: tokens, snake: "access_token", camel: "accessToken"),
              !accessToken.isEmpty else
        {
            throw CodexUsageProviderError.missingCredentials
        }

        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: Self.stringValue(in: tokens, snake: "refresh_token", camel: "refreshToken"),
            idToken: Self.stringValue(in: tokens, snake: "id_token", camel: "idToken"),
            accountId: Self.stringValue(in: tokens, snake: "account_id", camel: "accountId"))
    }

    private static func stringValue(in dictionary: [String: Any], snake: String, camel: String) -> String? {
        if let value = dictionary[snake] as? String, !value.isEmpty { return value }
        if let value = dictionary[camel] as? String, !value.isEmpty { return value }
        return nil
    }
}

public protocol UsageHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionUsageHTTPClient: UsageHTTPClient {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexUsageProviderError.invalidResponse("non-HTTP response")
        }
        return (data, httpResponse)
    }
}

public struct OAuthCodexUsageProvider<Client: UsageHTTPClient>: CodexUsageProviding, Sendable {
    private let env: [String: String]
    private let httpClient: Client
    private let now: @Sendable () -> Date

    public init(
        env: [String: String] = ProcessInfo.processInfo.environment,
        httpClient: Client,
        now: @escaping @Sendable () -> Date = Date.init)
    {
        self.env = env
        self.httpClient = httpClient
        self.now = now
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let credentials = try CodexOAuthCredentialsStore.load(env: self.env)
        var request = URLRequest(url: Self.usageURL(env: self.env))
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("QuotaPulse", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId = credentials.accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await self.httpClient.data(for: request)
        switch response.statusCode {
        case 200...299:
            return try Self.mapUsageResponse(data, source: .oauth, updatedAt: self.now())
        case 401, 403:
            throw CodexUsageProviderError.processFailed("OAuth unauthorized; run Codex to refresh login.")
        default:
            throw CodexUsageProviderError.processFailed("HTTP \(response.statusCode)")
        }
    }

    public static func usageURL(env: [String: String]) -> URL {
        if let override = QuotaPulseEnvironment.value("QUOTA_PULSE_USAGE_URL", in: env),
           let url = URL(string: override)
        {
            return url
        }
        return URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    }

    public static func mapUsageResponse(
        _ data: Data,
        source: UsageSource,
        updatedAt: Date = Date()) throws -> UsageSnapshot
    {
        let response: OAuthUsageResponse
        do {
            response = try JSONDecoder().decode(OAuthUsageResponse.self, from: data)
        } catch {
            throw CodexUsageProviderError.invalidResponse(error.localizedDescription)
        }
        guard let rateLimit = response.rateLimit else {
            throw CodexUsageProviderError.noUsageWindows
        }
        let snapshot = UsageSnapshot.fromWindows(
            primary: rateLimit.primaryWindow?.usageWindow,
            secondary: rateLimit.secondaryWindow?.usageWindow,
            extraWindows: response.sparkExtraWindows,
            source: source,
            updatedAt: updatedAt)
        guard snapshot.sessionPercentRemaining != nil || snapshot.weeklyPercentRemaining != nil else {
            throw CodexUsageProviderError.noUsageWindows
        }
        return snapshot
    }
}

private struct OAuthUsageResponse: Decodable {
    let rateLimit: OAuthRateLimit?
    let additionalRateLimits: [OAuthAdditionalRateLimit]

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.rateLimit = try? container.decodeIfPresent(OAuthRateLimit.self, forKey: .rateLimit)
        let lossy = try? container.decodeIfPresent([LossyOAuthAdditionalRateLimit].self, forKey: .additionalRateLimits)
        self.additionalRateLimits = lossy?.compactMap(\.value) ?? []
    }

    var sparkExtraWindows: [UsageNamedWindow] {
        var usedIDs = Set<String>()
        return self.additionalRateLimits.flatMap { limit -> [UsageNamedWindow] in
            guard limit.isSpark else { return [] }
            let candidates: [(OAuthWindow?, String, String)] = [
                (limit.rateLimit?.primaryWindow, "codex-spark", "Codex Spark 5-hour"),
                (limit.rateLimit?.secondaryWindow, "codex-spark-weekly", "Codex Spark Weekly"),
            ]
            return candidates.compactMap { window, fallbackID, fallbackTitle in
                guard let window else { return nil }
                let kind = Self.sparkKind(for: window, fallbackID: fallbackID, fallbackTitle: fallbackTitle)
                guard usedIDs.insert(kind.id).inserted else { return nil }
                return UsageNamedWindow(id: kind.id, title: kind.title, window: window.usageWindow)
            }
        }
    }

    private static func sparkKind(
        for window: OAuthWindow,
        fallbackID: String,
        fallbackTitle: String) -> (id: String, title: String)
    {
        guard let seconds = window.limitWindowSeconds else {
            return (fallbackID, fallbackTitle)
        }
        if seconds <= 6 * 3_600 {
            return ("codex-spark", "Codex Spark 5-hour")
        }
        if seconds >= 6 * 86_400 {
            return ("codex-spark-weekly", "Codex Spark Weekly")
        }
        return (fallbackID, fallbackTitle)
    }
}

private struct OAuthRateLimit: Decodable {
    let primaryWindow: OAuthWindow?
    let secondaryWindow: OAuthWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct OAuthAdditionalRateLimit: Decodable {
    let limitName: String?
    let meteredFeature: String?
    let rateLimit: OAuthRateLimit?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }

    var isSpark: Bool {
        [self.limitName, self.meteredFeature]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("spark") }
    }
}

private struct LossyOAuthAdditionalRateLimit: Decodable {
    let value: OAuthAdditionalRateLimit?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try? container.decode(OAuthAdditionalRateLimit.self)
    }
}

private struct OAuthWindow: Decodable {
    let usedPercent: Double
    let resetAt: Int?
    let limitWindowSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.usedPercent = try container.flexibleDouble(forKey: .usedPercent)
        self.resetAt = try? container.flexibleInt(forKey: .resetAt)
        self.limitWindowSeconds = try? container.flexibleInt(forKey: .limitWindowSeconds)
    }

    var usageWindow: UsageWindow {
        UsageWindow(
            usedPercent: self.usedPercent,
            resetAt: self.resetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            windowSeconds: self.limitWindowSeconds)
    }
}

extension KeyedDecodingContainer {
    func flexibleDouble(forKey key: Key) throws -> Double {
        if let value = try? self.decode(Double.self, forKey: key) { return value }
        if let value = try? self.decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? self.decode(String.self, forKey: key), let parsed = Double(value) { return parsed }
        throw DecodingError.typeMismatch(
            Double.self,
            DecodingError.Context(codingPath: self.codingPath + [key], debugDescription: "Expected number"))
    }

    func flexibleInt(forKey key: Key) throws -> Int {
        if let value = try? self.decode(Int.self, forKey: key) { return value }
        if let value = try? self.decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? self.decode(String.self, forKey: key), let parsed = Int(value) { return parsed }
        throw DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(codingPath: self.codingPath + [key], debugDescription: "Expected integer"))
    }
}
