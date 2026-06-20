import QuotaPulseCore
import Darwin
import Foundation

@main
enum QuotaPulseTestHarness {
    @MainActor
    static func main() async {
        let harness = Harness()
        await harness.runAll()
        if harness.failures > 0 {
            print("FAILED: \(harness.failures) assertion(s)")
            exit(EXIT_FAILURE)
        }
        print("PASS: \(harness.passes) assertions")
    }
}

@MainActor
private final class Harness {
    var failures = 0
    var passes = 0

    func runAll() async {
        await self.run("UsageSnapshot primary 5h selection", self.usageSnapshotPrimarySelection)
        await self.run("UsageSnapshot reversed window normalization", self.reversedWindowNormalization)
        await self.run("UsageSnapshot weekly-only is not primary", self.weeklyOnlyNotPrimary)
        await self.run("UsageSnapshot legacy cache decoding", self.usageSnapshotLegacyCacheDecoding)
        await self.run("UsagePace reserve and deficit", self.usagePaceReserveAndDeficit)
        await self.run("Stale auth failure menu bar formatter", self.staleAuthFailureMenuBarFormatter)
        await self.run("Secret sanitization", self.secretSanitization)
        await self.run("QuotaPulse legacy env aliases", self.quotaPulseLegacyEnvAliases)
        await self.run("OAuth credentials parsing", self.oauthCredentialsParsing)
        await self.run("OAuth usage mapping", self.oauthUsageMapping)
        await self.run("OAuth Codex extra Spark windows", self.oauthCodexExtraSparkWindows)
        await self.run("OAuth request headers", self.oauthRequestHeaders)
        await self.run("Claude OAuth credentials parsing", self.claudeOAuthCredentialsParsing)
        await self.run("Claude OAuth credentials file load", self.claudeOAuthCredentialsFileLoad)
        await self.run("Claude OAuth credential discovery sources", self.claudeOAuthCredentialDiscoverySources)
        await self.run("Claude OAuth Keychain fail-closed discovery", self.claudeOAuthKeychainFailClosedDiscovery)
        await self.run("Claude OAuth usage mapping", self.claudeOAuthUsageMapping)
        await self.run("Claude OAuth extra windows mapping", self.claudeOAuthExtraWindowsMapping)
        await self.run("Claude OAuth request headers", self.claudeOAuthRequestHeaders)
        await self.run("Claude OAuth credential reload retry", self.claudeOAuthCredentialReloadRetry)
        await self.run("Claude OAuth credential reload bounded failure", self.claudeOAuthCredentialReloadBoundedFailure)
        await self.run("Claude OAuth rate limit cooldown", self.claudeOAuthRateLimitCooldown)
        await self.run("Claude source planner", self.claudeSourcePlanner)
        await self.run("Claude OAuth rate limit cache", self.claudeOAuthRateLimitCache)
        await self.run("Claude weekly-only is not primary", self.claudeWeeklyOnlyNotPrimary)
        await self.run("Claude CLI usage mapping", self.claudeCLIUsageMapping)
        await self.run("Claude CLI weekly missing", self.claudeCLIWeeklyMissing)
        await self.run("Claude CLI malformed output", self.claudeCLIMalformedOutput)
        await self.run("Claude CLI provider stub", self.claudeCLIProviderStub)
        await self.run("Claude CLI timeout", self.claudeCLITimeout)
        await self.run("Claude CLI allows practical state file update", self.claudeCLIAllowsPracticalStateUpdate)
        await self.run("Claude CLI protected state mutation guard", self.claudeCLIProtectedStateMutationGuard)
        await self.run("CLI RPC usage mapping", self.cliRPCUsageMapping)
        await self.run("CLI RPC timeout", self.cliRPCTimeout)
        await self.run("Local fallback usage file", self.localFallbackUsageFile)
        await self.run("Local fallback session scan", self.localFallbackSessionScan)
        await self.run("Refresh cadence and backoff", self.refreshCadenceAndBackoff)
        await self.run("Refresh gate no-overlap", self.refreshGateNoOverlap)
        await self.run("Refresh jitter bounds", self.refreshJitterBounds)
        await self.run("Smart Refresh separate provider modes", self.smartRefreshSeparateProviderModes)
        await self.run("Smart Refresh auto policy", self.smartRefreshAutoPolicy)
        await self.run("Smart Refresh presence pause and wake", self.smartRefreshPresencePauseAndWake)
        await self.run("Smart Refresh Claude unchanged baseline", self.smartRefreshClaudeUnchangedBaseline)
        await self.run("Smart Refresh manual cooldown skip", self.smartRefreshManualCooldownSkip)
        await self.run("Smart Refresh countdown text updates from supplied time", self.smartRefreshCountdownTextUsesSuppliedNow)
        await self.run("Smart Refresh scheduler debounce", self.smartRefreshSchedulerDebounce)
        await self.run("UsageStore refresh feedback debounce", self.usageStoreRefreshFeedbackDebounce)
        await self.run("UsageStore stale last-good", self.usageStoreStaleLastGood)
        await self.run("Codex refresh while Claude rate-limited", self.codexRefreshWhileClaudeRateLimited)
        await self.run("Dual-provider independent failure", self.dualProviderIndependentFailure)
        await self.run("Dual-provider title formatter", self.dualProviderTitleFormatter)
    }

    private func run(_ name: String, _ body: () async throws -> Void) async {
        do {
            try await body()
            print("ok - \(name)")
        } catch {
            self.failures += 1
            print("not ok - \(name): \(UsageSnapshot.sanitized(error.localizedDescription))")
        }
    }

    private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if condition() {
            self.passes += 1
        } else {
            self.failures += 1
            throw HarnessFailure(message)
        }
    }

    private func usageSnapshotPrimarySelection() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = UsageSnapshot.fromWindows(
            primary: UsageWindow(usedPercent: 22, resetAt: now.addingTimeInterval(3_600), windowSeconds: 18_000),
            secondary: UsageWindow(usedPercent: 43, resetAt: now.addingTimeInterval(86_400), windowSeconds: 604_800),
            source: .fixture,
            updatedAt: now)
        try self.expect(snapshot.sessionPercentRemaining == 78, "5h remaining should be 78")
        try self.expect(snapshot.weeklyPercentRemaining == 57, "weekly remaining should be 57")
        try self.expect(snapshot.primaryDisplayText == "78%", "primary display should be 5h remaining")
    }

    private func reversedWindowNormalization() async throws {
        let snapshot = UsageSnapshot.fromWindows(
            primary: UsageWindow(usedPercent: 11, resetAt: nil, windowSeconds: 604_800),
            secondary: UsageWindow(usedPercent: 73, resetAt: nil, windowSeconds: 18_000),
            source: .fixture)
        try self.expect(snapshot.sessionPercentRemaining == 27, "session window should be selected from secondary")
        try self.expect(snapshot.weeklyPercentRemaining == 89, "weekly window should be selected from primary")
        try self.expect(snapshot.primaryDisplayText == "27%", "main display must not show weekly")
    }

    private func weeklyOnlyNotPrimary() async throws {
        let snapshot = UsageSnapshot.fromWindows(
            primary: UsageWindow(usedPercent: 10, resetAt: nil, windowSeconds: 604_800),
            secondary: nil,
            source: .fixture)
        try self.expect(snapshot.sessionPercentRemaining == nil, "weekly-only should leave session unavailable")
        try self.expect(snapshot.weeklyPercentRemaining == 90, "weekly remaining should still be available")
        try self.expect(snapshot.primaryDisplayText == "No 5h", "main display should not reuse weekly")
    }

    private func usageSnapshotLegacyCacheDecoding() async throws {
        let json = """
        {
          "sessionPercentRemaining": 82,
          "weeklyPercentRemaining": 67,
          "sessionResetAt": 803578145,
          "weeklyResetAt": 804044820,
          "source": "OAuth",
          "updatedAt": 803565621,
          "isStale": false
        }
        """
        let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        try self.expect(snapshot.extraWindows.isEmpty, "legacy cache decodes with empty extra windows")
        try self.expect(snapshot.primaryDisplayText == "82%", "legacy cache primary display remains stable")
    }

    private func usagePaceReserveAndDeficit() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reserveWindow = UsageWindow(
            usedPercent: 40,
            resetAt: now.addingTimeInterval(50),
            windowSeconds: 100)
        guard let reservePace = UsagePace(window: reserveWindow, now: now) else {
            throw HarnessFailure("reserve pace should compute")
        }
        try self.expect(reservePace.expectedUsedPercent == 50, "reserve expected usage")
        try self.expect(reservePace.actualUsedPercent == 40, "reserve actual usage")
        try self.expect(UsagePaceFormatter.balanceText(reservePace) == "10% in reserve", "reserve text")
        try self.expect(reservePace.lastsUntilReset, "reserve lasts until reset")

        let deficitWindow = UsageWindow(
            usedPercent: 75,
            resetAt: now.addingTimeInterval(50),
            windowSeconds: 100)
        guard let deficitPace = UsagePace(window: deficitWindow, now: now) else {
            throw HarnessFailure("deficit pace should compute")
        }
        try self.expect(UsagePaceFormatter.balanceText(deficitPace) == "25% in deficit", "deficit text")
        try self.expect(!deficitPace.lastsUntilReset, "deficit projects empty before reset")
        try self.expect(UsagePaceFormatter.expectedUsedText(deficitPace) == "Expected 50% used", "expected text")
    }

    private func staleAuthFailureMenuBarFormatter() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let codex = UsageSnapshot(
            sessionPercentRemaining: 63,
            weeklyPercentRemaining: 39,
            sessionResetAt: nil,
            weeklyResetAt: nil,
            source: .oauth,
            updatedAt: now)
        let healthyClaude = UsageSnapshot(
            sessionPercentRemaining: 92,
            weeklyPercentRemaining: 82,
            sessionResetAt: now.addingTimeInterval(3_600),
            weeklyResetAt: nil,
            source: .oauth,
            updatedAt: now)
        let staleClaude = UsageSnapshot(
            sessionPercentRemaining: 89,
            weeklyPercentRemaining: 82,
            sessionResetAt: now.addingTimeInterval(3_600),
            weeklyResetAt: nil,
            source: .oauth,
            updatedAt: now)
            .markedStale(errorMessage: "Claude OAuth usage failed: OAuth unauthorized; run Claude to refresh login.")
        let expiredClaude = UsageSnapshot(
            sessionPercentRemaining: 89,
            weeklyPercentRemaining: 82,
            sessionResetAt: now.addingTimeInterval(-1),
            weeklyResetAt: nil,
            source: .oauth,
            updatedAt: now)
            .markedStale(errorMessage: "Claude OAuth usage failed: OAuth unauthorized; run Claude to refresh login.")
        let missingClaude = UsageSnapshot(
            sessionPercentRemaining: nil,
            weeklyPercentRemaining: 82,
            sessionResetAt: nil,
            weeklyResetAt: nil,
            source: .oauth,
            updatedAt: now)
            .markedStale(errorMessage: "Claude OAuth usage failed: OAuth unauthorized; run Claude to refresh login.")

        try self.expect(staleClaude.hasAuthFailureError, "Claude stale auth failure is detected")
        try self.expect(staleClaude.hasStaleAuthFailure, "Claude stale auth failure state is detected")
        try self.expect(staleClaude.hasUsableCachedSessionPercent(now: now), "Claude stale auth cached session is usable before reset")

        let healthyCompact = UsageDisplayFormatter.menuBarCompactText(codex: codex, claude: healthyClaude, now: now)
        try self.expect(healthyCompact.contains("Cl 92%"), "healthy Claude renders percent")

        let staleCompact = UsageDisplayFormatter.menuBarCompactText(codex: codex, claude: staleClaude, now: now)
        try self.expect(staleCompact.contains("Cx 63%"), "Codex remains visible during Claude auth failure")
        try self.expect(staleCompact.contains("Cl 89!"), "Claude stale auth failure renders stale-marked cached value")
        try self.expect(!staleCompact.contains("Cl 89%"), "Claude stale auth failure does not render old percentage as live")
        try self.expect(!staleCompact.contains("Cl ERR"), "Claude stale auth with usable cache does not render ERR")

        let expiredCompact = UsageDisplayFormatter.menuBarCompactText(codex: codex, claude: expiredClaude, now: now)
        try self.expect(expiredCompact.contains("Cl ERR"), "expired cached Claude session renders ERR")
        try self.expect(!expiredCompact.contains("Cl 89!"), "expired cached Claude session does not render stale marker")

        let missingCompact = UsageDisplayFormatter.menuBarCompactText(codex: codex, claude: missingClaude, now: now)
        try self.expect(missingCompact.contains("Cl ERR"), "missing cached Claude session renders ERR")
    }

    private func secretSanitization() async throws {
        let snapshot = UsageSnapshot.error("Bearer abc.def sk-test123 \"access_token\":\"secret\"")
        try self.expect(snapshot.primaryDisplayText == "ERR", "error display should be ERR")
        try self.expect(snapshot.errorMessage?.contains("abc.def") == false, "bearer token redacted")
        try self.expect(snapshot.errorMessage?.contains("sk-test123") == false, "api key redacted")
        try self.expect(snapshot.errorMessage?.contains("secret") == false, "access token redacted")
    }

    private func quotaPulseLegacyEnvAliases() async throws {
        let legacyEnv = [
            "CODEX_NOTCH_METER_AUTH_PATH": "/tmp/legacy-auth.json",
            "CODEX_NOTCH_METER_ENABLE_CLAUDE_KEYCHAIN": "1",
            "CODEX_NOTCH_METER_CLAUDE_CLI_PATH": "/tmp/legacy-claude",
        ]
        try self.expect(
            QuotaPulseEnvironment.value("QUOTA_PULSE_AUTH_PATH", in: legacyEnv) == "/tmp/legacy-auth.json",
            "legacy env alias should resolve")
        try self.expect(
            ClaudeOAuthCredentialsStore.isKeychainDiscoveryEnabled(env: legacyEnv),
            "legacy Keychain flag should remain compatible")
        try self.expect(
            ClaudeCLIUsageProvider.executablePath(env: legacyEnv) == "/tmp/legacy-claude",
            "legacy Claude CLI path should remain compatible")

        let preferredEnv = [
            "QUOTA_PULSE_AUTH_PATH": "/tmp/new-auth.json",
            "CODEX_NOTCH_METER_AUTH_PATH": "/tmp/legacy-auth.json",
        ]
        try self.expect(
            CodexOAuthCredentialsStore.authFileURL(env: preferredEnv).path == "/tmp/new-auth.json",
            "new QuotaPulse env should take priority")
    }

    private func oauthCredentialsParsing() async throws {
        let snake = #"{"tokens":{"access_token":"access","refresh_token":"refresh","id_token":"id","account_id":"acct"}}"#
        let camel = #"{"tokens":{"accessToken":"access","refreshToken":"refresh","idToken":"id","accountId":"acct"}}"#
        let snakeCredentials = try CodexOAuthCredentialsStore.parse(data: Data(snake.utf8))
        let camelCredentials = try CodexOAuthCredentialsStore.parse(data: Data(camel.utf8))
        try self.expect(snakeCredentials.accessToken == "access", "snake credentials parsed")
        try self.expect(camelCredentials.accountId == "acct", "camel credentials parsed")
    }

    private func oauthUsageMapping() async throws {
        let json = """
        {"rate_limit":{"primary_window":{"used_percent":37,"reset_at":1800003600,"limit_window_seconds":18000},"secondary_window":{"used_percent":"64","reset_at":"1800864000","limit_window_seconds":604800}}}
        """
        let snapshot = try OAuthCodexUsageProvider<StubHTTPClient>.mapUsageResponse(
            Data(json.utf8),
            source: .oauth,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try self.expect(snapshot.sessionPercentRemaining == 63, "OAuth session remaining")
        try self.expect(snapshot.weeklyPercentRemaining == 36, "OAuth weekly remaining")
        try self.expect(snapshot.source == .oauth, "OAuth source")
    }

    private func oauthCodexExtraSparkWindows() async throws {
        let json = """
        {
          "rate_limit": {
            "primary_window": {"used_percent":37,"reset_at":1800003600,"limit_window_seconds":18000},
            "secondary_window": {"used_percent":64,"reset_at":1800604800,"limit_window_seconds":604800}
          },
          "additional_rate_limits": [
            {
              "limit_name": "GPT-5.3-Codex-Spark",
              "metered_feature": "codex_spark",
              "rate_limit": {
                "primary_window": {"used_percent":28,"reset_at":1800007200,"limit_window_seconds":18000},
                "secondary_window": {"used_percent":47,"reset_at":1800608400,"limit_window_seconds":604800}
              }
            }
          ]
        }
        """
        let snapshot = try OAuthCodexUsageProvider<StubHTTPClient>.mapUsageResponse(
            Data(json.utf8),
            source: .oauth,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try self.expect(snapshot.extraWindows.count == 2, "Codex Spark extra windows are mapped")
        try self.expect(snapshot.extraWindows.map(\.title).contains("Codex Spark 5-hour"), "Spark 5-hour title")
        try self.expect(snapshot.extraWindows.map(\.title).contains("Codex Spark Weekly"), "Spark weekly title")
        try self.expect(snapshot.extraWindows.first { $0.id == "codex-spark" }?.window.remainingPercent == 72, "Spark remaining")
    }

    private func oauthRequestHeaders() async throws {
        let temp = try Self.makeTempDirectory()
        let auth = temp.appendingPathComponent("auth.json")
        try Data(#"{"tokens":{"access_token":"access-secret","refresh_token":"refresh","account_id":"acct-1"}}"#.utf8)
            .write(to: auth)
        let body = #"{"rate_limit":{"primary_window":{"used_percent":40,"reset_at":1800003600,"limit_window_seconds":18000}}}"#
        let client = StubHTTPClient(statusCode: 200, body: body)
        let provider = OAuthCodexUsageProvider(
            env: [
                "QUOTA_PULSE_AUTH_PATH": auth.path,
                "QUOTA_PULSE_USAGE_URL": "https://example.test/usage",
            ],
            httpClient: client,
            now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let snapshot = try await provider.fetchUsage()
        try self.expect(snapshot.sessionPercentRemaining == 60, "OAuth provider maps body")
        try self.expect(
            client.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer access-secret",
            "Authorization header sent")
        try self.expect(
            client.lastRequest?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct-1",
            "account header sent")
    }

    private func claudeOAuthCredentialsParsing() async throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"claude-access","refreshToken":"refresh","expiresAt":1800000000000,"scopes":["user:profile"]}}
        """
        let credentials = try ClaudeOAuthCredentialsStore.parse(data: Data(json.utf8))
        try self.expect(credentials.accessToken == "claude-access", "Claude access token parsed")
        try self.expect(credentials.refreshToken == "refresh", "Claude refresh token parsed")
        try self.expect(credentials.scopes == ["user:profile"], "Claude scopes parsed")
        let path = ClaudeOAuthCredentialsStore.credentialsFileURL(
            env: ["QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH": "/tmp/claude-creds.json"])
        try self.expect(path.path == "/tmp/claude-creds.json", "Claude credentials path override")
    }

    private func claudeOAuthCredentialsFileLoad() async throws {
        let temp = try Self.makeTempDirectory()
        let credentialsFile = temp.appendingPathComponent(".credentials.json")
        let json = """
        {"claudeAiOauth":{"accessToken":"claude-file-access","refreshToken":"refresh","expiresAt":1800000000000,"scopes":["user:profile"]}}
        """
        try Data(json.utf8).write(to: credentialsFile)
        let credentials = try ClaudeOAuthCredentialsStore.load(
            env: ["QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH": credentialsFile.path])
        try self.expect(credentials.accessToken == "claude-file-access", "Claude credentials file loaded")

        do {
            _ = try ClaudeOAuthCredentialsStore.load(
                env: ["QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH": temp.appendingPathComponent("missing.json").path])
            throw HarnessFailure("expected missing credentials failure")
        } catch let error as ClaudeUsageProviderError {
            try self.expect(error == .missingCredentials, "missing Claude credentials fail closed")
        }
    }

    private func claudeOAuthCredentialDiscoverySources() async throws {
        let temp = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let credentialsFile = temp.appendingPathComponent(".credentials.json")
        let cacheFile = temp.appendingPathComponent("cache.json")
        try Data(Self.claudeCredentialsJSON(accessToken: "file-access").utf8).write(to: credentialsFile)
        try Data(Self.claudeCredentialsJSON(accessToken: "cache-access").utf8).write(to: cacheFile)

        let fileRecord = try ClaudeOAuthCredentialsStore.loadRecord(
            env: [
                "QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH": credentialsFile.path,
                "QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH": cacheFile.path,
                "QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN": "1",
            ],
            keychainReader: StubClaudeKeychainReader(data: Data(Self.claudeCredentialsJSON(accessToken: "keychain-access").utf8)))
        try self.expect(fileRecord.source == .credentialsFile, "credential file has highest priority")
        try self.expect(fileRecord.credentials.accessToken == "file-access", "credential file token selected")

        let missingExplicitPath = temp.appendingPathComponent("missing.json")
        do {
            _ = try ClaudeOAuthCredentialsStore.loadRecord(
                env: [
                    "QUOTA_PULSE_CLAUDE_CREDENTIALS_PATH": missingExplicitPath.path,
                    "QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH": cacheFile.path,
                ],
                keychainReader: StubClaudeKeychainReader(data: Data(Self.claudeCredentialsJSON(accessToken: "keychain-access").utf8)))
            throw HarnessFailure("expected explicit missing credential path to fail closed")
        } catch let error as ClaudeUsageProviderError {
            try self.expect(error == .missingCredentials, "explicit missing credential path fails closed")
        }

        let cacheRecord = try ClaudeOAuthCredentialsStore.loadRecord(
            env: [
                "HOME": temp.path,
                "QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH": cacheFile.path,
            ],
            keychainReader: StubClaudeKeychainReader(data: Data(Self.claudeCredentialsJSON(accessToken: "keychain-access").utf8)))
        try self.expect(cacheRecord.source == .appOAuthCache, "app-owned OAuth cache is second priority")
        try self.expect(cacheRecord.credentials.accessToken == "cache-access", "app-owned OAuth cache token selected")

        let keychainRecord = try ClaudeOAuthCredentialsStore.loadRecord(
            env: [
                "HOME": temp.path,
                "QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH": temp.appendingPathComponent("missing-cache.json").path,
                "QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN": "1",
            ],
            keychainReader: StubClaudeKeychainReader(data: Data(Self.claudeCredentialsJSON(accessToken: "keychain-access").utf8)))
        try self.expect(keychainRecord.source == .claudeCodeKeychain, "opt-in Keychain is third priority")
        try self.expect(keychainRecord.credentials.accessToken == "keychain-access", "Keychain token selected")
    }

    private func claudeOAuthKeychainFailClosedDiscovery() async throws {
        let temp = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let counter = KeychainReadCounter()
        do {
            _ = try ClaudeOAuthCredentialsStore.loadRecord(
                env: [
                    "HOME": temp.path,
                    "QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH": temp.appendingPathComponent("missing-cache.json").path,
                ],
                keychainReader: StubClaudeKeychainReader(
                    data: Data(Self.claudeCredentialsJSON(accessToken: "keychain-access").utf8),
                    counter: counter))
            throw HarnessFailure("expected missing credentials with Keychain disabled")
        } catch let error as ClaudeUsageProviderError {
            try self.expect(error == .missingCredentials, "Keychain disabled fails as missing credentials")
            try self.expect(counter.calls == 0, "Keychain reader is not called unless explicitly enabled")
        }

        do {
            _ = try ClaudeOAuthCredentialsStore.loadRecord(
                env: [
                    "HOME": temp.path,
                    "QUOTA_PULSE_CLAUDE_OAUTH_CACHE_PATH": temp.appendingPathComponent("missing-cache.json").path,
                    "QUOTA_PULSE_ENABLE_CLAUDE_KEYCHAIN": "1",
                ],
                keychainReader: StubClaudeKeychainReader(error: ClaudeUsageProviderError.keychainAccessDenied))
            throw HarnessFailure("expected denied Keychain access to fail closed")
        } catch let error as ClaudeUsageProviderError {
            try self.expect(error == .keychainAccessDenied, "denied Keychain access fails closed")
        }
    }

    private func claudeOAuthUsageMapping() async throws {
        let json = """
        {"five_hour":{"utilization":15,"resets_at":"2027-01-15T03:12:00Z"},"seven_day":{"utilization":"42","resets_at":"2027-01-18T02:00:00.000Z"}}
        """
        let snapshot = try OAuthClaudeUsageProvider<StubHTTPClient>.mapUsageResponse(
            Data(json.utf8),
            source: .oauth,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try self.expect(snapshot.sessionPercentRemaining == 85, "Claude session remaining")
        try self.expect(snapshot.weeklyPercentRemaining == 58, "Claude weekly remaining")
        try self.expect(snapshot.sessionResetAt != nil, "Claude session reset parsed")
        try self.expect(snapshot.weeklyResetAt != nil, "Claude weekly reset parsed")
        try self.expect(snapshot.source == .oauth, "Claude OAuth source")
    }

    private func claudeOAuthExtraWindowsMapping() async throws {
        let json = """
        {
          "five_hour":{"utilization":15,"resets_at":"2027-01-15T03:12:00Z"},
          "seven_day":{"utilization":"42","resets_at":"2027-01-18T02:00:00.000Z"},
          "seven_day_sonnet":{"utilization":35,"resets_at":"2027-01-18T02:00:00.000Z"},
          "seven_day_opus":{"utilization":66,"resets_at":"2027-01-18T02:00:00.000Z"},
          "seven_day_routines":{"utilization":20,"resets_at":"2027-01-16T00:00:00Z"},
          "extra_usage":{"is_enabled":true,"used_credits":1250,"monthly_limit":5000,"currency":"USD","utilization":25}
        }
        """
        let snapshot = try OAuthClaudeUsageProvider<StubHTTPClient>.mapUsageResponse(
            Data(json.utf8),
            source: .oauth,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try self.expect(snapshot.extraWindows.count == 4, "Claude OAuth extra windows are mapped")
        try self.expect(snapshot.extraWindows.map(\.title).contains("Claude Sonnet Weekly"), "Sonnet weekly mapped")
        try self.expect(snapshot.extraWindows.map(\.title).contains("Claude Opus Weekly"), "Opus weekly mapped")
        try self.expect(snapshot.extraWindows.map(\.title).contains("Daily Routines"), "Daily Routines mapped")
        let extra = snapshot.extraWindows.first { $0.id == "claude-extra-usage" }
        try self.expect(extra?.window.remainingPercent == 75, "Extra usage remaining mapped")
        try self.expect(extra?.detail == "Monthly cap USD 12.50 / USD 50.00", "Extra usage detail mapped")
    }

    private func claudeOAuthRequestHeaders() async throws {
        let credentials = ClaudeOAuthCredentials(
            accessToken: "claude-secret",
            refreshToken: nil,
            expiresAt: nil,
            scopes: ["user:profile"])
        let body = #"{"five_hour":{"utilization":20,"resets_at":"2027-01-15T03:12:00Z"}}"#
        let client = StubHTTPClient(statusCode: 200, body: body)
        let provider = OAuthClaudeUsageProvider(
            credentials: credentials,
            env: [
                "QUOTA_PULSE_CLAUDE_USAGE_URL": "https://example.test/claude-usage",
                "QUOTA_PULSE_CLAUDE_CODE_VERSION": "2.2.3 Claude Code",
            ],
            httpClient: client,
            now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let snapshot = try await provider.fetchUsage()
        try self.expect(snapshot.sessionPercentRemaining == 80, "Claude provider maps body")
        try self.expect(
            client.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer claude-secret",
            "Claude Authorization header sent")
        try self.expect(
            client.lastRequest?.value(forHTTPHeaderField: "anthropic-beta") == OAuthClaudeUsageProvider<StubHTTPClient>.betaHeaderValue,
            "Claude beta header sent")
        try self.expect(
            client.lastRequest?.value(forHTTPHeaderField: "User-Agent") == "claude-code/2.2.3",
            "Claude OAuth User-Agent follows Claude Code format")
        try self.expect(
            client.lastRequest?.value(forHTTPHeaderField: "Content-Type") == "application/json",
            "Claude OAuth content type sent")
        try self.expect(
            OAuthClaudeUsageProvider<StubHTTPClient>.claudeCodeUserAgent(env: [:]) == "claude-code/2.1.0",
            "Claude OAuth User-Agent has fallback version")
    }

    private func claudeOAuthCredentialReloadRetry() async throws {
        let resolver = SequencedClaudeCredentialResolver(records: [
            Self.claudeCredentialRecord(accessToken: "old-credential"),
            Self.claudeCredentialRecord(accessToken: "new-credential"),
        ])
        let client = SequencedHTTPClient(responses: [
            (401, "{}"),
            (200, #"{"five_hour":{"utilization":20,"resets_at":"2027-01-15T03:12:00Z"}}"#),
        ])
        let provider = ReloadingClaudeOAuthUsageProvider(
            env: ["QUOTA_PULSE_CLAUDE_USAGE_URL": "https://example.test/claude-usage"],
            httpClient: client,
            credentialResolver: resolver,
            now: { Date(timeIntervalSince1970: 1_800_000_000) })

        let snapshot = try await provider.fetchUsage()

        try self.expect(snapshot.source == .oauth, "reloaded credential retry keeps OAuth source")
        try self.expect(snapshot.sessionPercentRemaining == 80, "reloaded credential retry succeeds")
        try self.expect(resolver.loadCount == 2, "credentials are reloaded after unauthorized")
        try self.expect(client.requestCount == 2, "OAuth request is retried once")
        try self.expect(client.authorizationValues.count == 2, "retry uses two credential attempts")
        try self.expect(client.authorizationValues.first != client.authorizationValues.last, "retry uses reloaded credential")
    }

    private func claudeOAuthCredentialReloadBoundedFailure() async throws {
        let resolver = SequencedClaudeCredentialResolver(records: [
            Self.claudeCredentialRecord(accessToken: "old-credential"),
            Self.claudeCredentialRecord(accessToken: "still-expired-credential"),
            Self.claudeCredentialRecord(accessToken: "unused-credential"),
        ])
        let client = SequencedHTTPClient(responses: [
            (401, "{}"),
            (401, "{}"),
            (200, #"{"five_hour":{"utilization":20,"resets_at":"2027-01-15T03:12:00Z"}}"#),
        ])
        let provider = ReloadingClaudeOAuthUsageProvider(
            env: ["QUOTA_PULSE_CLAUDE_USAGE_URL": "https://example.test/claude-usage"],
            httpClient: client,
            credentialResolver: resolver,
            now: { Date(timeIntervalSince1970: 1_800_000_000) })

        do {
            _ = try await provider.fetchUsage()
            throw HarnessFailure("expected bounded Claude OAuth retry failure")
        } catch {
            let message = error.localizedDescription
            try self.expect(UsageSnapshot.isAuthFailureMessage(message), "bounded retry surfaces auth failure")
            try self.expect(client.requestCount == 2, "bounded retry stops after one retry")
            try self.expect(resolver.loadCount == 2, "bounded retry reloads credentials once")
            try self.expect(!message.contains("old-credential"), "bounded retry error redacts first credential")
            try self.expect(!message.contains("still-expired-credential"), "bounded retry error redacts reloaded credential")
        }
    }

    private func claudeOAuthRateLimitCooldown() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let resolver = SequencedClaudeCredentialResolver(records: [
            Self.claudeCredentialRecord(accessToken: "rate-limit-credential"),
        ])
        let client = SequencedHTTPClient(responsesWithHeaders: [
            (
                200,
                #"{"five_hour":{"utilization":0,"resets_at":"2027-01-15T03:12:00Z"}}"#,
                [:]
            ),
            (
                429,
                "{}",
                ["Retry-After": "120"]
            ),
            (
                200,
                #"{"five_hour":{"utilization":40,"resets_at":"2027-01-15T03:12:00Z"}}"#,
                [:]
            ),
        ])
        let provider = ReloadingClaudeOAuthUsageProvider(
            env: ["QUOTA_PULSE_CLAUDE_USAGE_URL": "https://example.test/claude-usage"],
            httpClient: client,
            credentialResolver: resolver,
            now: { clock.now })
        let store = UsageStore(provider: provider, cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))

        let initialRefresh = await store.refresh()
        try self.expect(initialRefresh, "initial Claude OAuth refresh succeeds")
        try self.expect(store.snapshot.sessionPercentRemaining == 100, "initial Claude value is cached")

        let rateLimitedRefresh = await store.refresh()
        try self.expect(rateLimitedRefresh, "429 refresh completes as stale failure")
        try self.expect(store.snapshot.isStale, "429 marks Claude snapshot stale")
        try self.expect(store.snapshot.sessionPercentRemaining == 100, "429 preserves last good Claude value")
        try self.expect(store.snapshot.hasRateLimitError, "429 snapshot has rate-limit error")
        try self.expect(store.snapshot.errorMessage?.contains("Rate limited. Try again in 2m.") == true, "Retry-After cooldown is shown")
        try self.expect(client.requestCount == 2, "429 performs the second OAuth request")

        clock.now = clock.now.addingTimeInterval(60)
        let cooldownRefresh = await store.refresh()
        try self.expect(cooldownRefresh, "cooldown refresh completes as local stale failure")
        try self.expect(client.requestCount == 2, "cooldown refresh does not call Claude OAuth")
        try self.expect(store.snapshot.errorMessage?.contains("Rate limited. Try again in 1m.") == true, "cooldown countdown is updated")

        clock.now = clock.now.addingTimeInterval(61)
        let afterCooldownRefresh = await store.refresh()
        try self.expect(afterCooldownRefresh, "cooldown expiry allows refresh")
        try self.expect(client.requestCount == 3, "cooldown expiry calls Claude OAuth again")
        try self.expect(!store.snapshot.isStale, "successful refresh clears stale state")
        try self.expect(store.snapshot.sessionPercentRemaining == 60, "successful refresh updates Claude value")
    }

    private func claudeSourcePlanner() async throws {
        let oauthOnly = ClaudeUsageSourcePlanner.plan(
            hasOAuthCredentials: true,
            oauthCredentialErrorMessage: nil,
            cliFallbackEnabled: false)
        try self.expect(oauthOnly.orderedSources == [.oauth], "OAuth credentials default to OAuth only")
        try self.expect(oauthOnly.usesOAuth, "OAuth plan uses OAuth")
        try self.expect(!oauthOnly.usesCLI, "OAuth default does not include CLI")

        let missingCredentials = ClaudeUsageSourcePlanner.plan(
            hasOAuthCredentials: false,
            oauthCredentialErrorMessage: nil,
            cliFallbackEnabled: false)
        try self.expect(missingCredentials.orderedSources == [.disabled], "missing OAuth without CLI is disabled")
        try self.expect(!missingCredentials.usesCLI, "missing OAuth without CLI does not use CLI")

        let cliOptIn = ClaudeUsageSourcePlanner.plan(
            hasOAuthCredentials: false,
            oauthCredentialErrorMessage: nil,
            cliFallbackEnabled: true)
        try self.expect(cliOptIn.orderedSources == [.cli], "missing OAuth with CLI flag allows CLI")
        try self.expect(cliOptIn.usesCLI, "CLI opt-in plan uses CLI")

        let invalidOAuth = ClaudeUsageSourcePlanner.plan(
            hasOAuthCredentials: false,
            oauthCredentialErrorMessage: "Bearer secret-token invalid",
            cliFallbackEnabled: false)
        try self.expect(invalidOAuth.orderedSources == [.failure], "invalid OAuth without CLI shows failure")
        try self.expect(invalidOAuth.failureMessage?.contains("secret-token") == false, "planner redacts OAuth error")

        let deniedKeychainWithCLI = ClaudeUsageSourcePlanner.plan(
            hasOAuthCredentials: false,
            oauthCredentialErrorMessage: "Claude OAuth Keychain access was denied.",
            cliFallbackEnabled: true)
        try self.expect(
            deniedKeychainWithCLI.orderedSources == [.failure],
            "Keychain denial fails closed instead of falling back to CLI")

        let oauthWithManualFallback = ClaudeUsageSourcePlanner.plan(
            hasOAuthCredentials: true,
            oauthCredentialErrorMessage: nil,
            cliFallbackEnabled: true)
        try self.expect(oauthWithManualFallback.orderedSources == [.oauth, .cli], "CLI flag adds manual fallback after OAuth")
    }

    private func claudeOAuthRateLimitCache() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let counter = CountingProvider()
        let provider = RateLimitedUsageProvider(
            provider: counter,
            minimumInterval: 300,
            now: { clock.now })

        let first = try await provider.fetchUsage()
        clock.now = clock.now.addingTimeInterval(60)
        let second = try await provider.fetchUsage()
        let countAfterSecondFetch = await counter.count()
        try self.expect(countAfterSecondFetch == 1, "second fetch inside rate limit uses cache")
        try self.expect(first.updatedAt == second.updatedAt, "cached snapshot returned inside interval")

        clock.now = clock.now.addingTimeInterval(301)
        let third = try await provider.fetchUsage()
        let countAfterThirdFetch = await counter.count()
        try self.expect(countAfterThirdFetch == 2, "fetch after interval refreshes provider")
        try self.expect(third.updatedAt != second.updatedAt, "snapshot updates after interval")
    }

    private func claudeWeeklyOnlyNotPrimary() async throws {
        let json = #"{"seven_day":{"utilization":44,"resets_at":"2027-01-18T02:00:00Z"}}"#
        let snapshot = try OAuthClaudeUsageProvider<StubHTTPClient>.mapUsageResponse(
            Data(json.utf8),
            source: .oauth,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try self.expect(snapshot.sessionPercentRemaining == nil, "Claude weekly-only should leave session unavailable")
        try self.expect(snapshot.weeklyPercentRemaining == 56, "Claude weekly-only weekly remaining")
        try self.expect(snapshot.primaryDisplayText == "No 5h", "Claude main display should not reuse weekly")
    }

    private func claudeCLIUsageMapping() async throws {
        let output = """
        Usage
        Current session
        82% left
        Resets at 9:45 PM

        Current week
        64% remaining
        Resets Jan 15, 3:12 AM
        """
        let snapshot = try ClaudeCLIUsageProvider.mapUsageOutput(
            output,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try self.expect(snapshot.source == .claudeCLI, "Claude CLI source")
        try self.expect(snapshot.sessionPercentRemaining == 82, "Claude CLI session remaining")
        try self.expect(snapshot.weeklyPercentRemaining == 64, "Claude CLI weekly remaining")
        try self.expect(snapshot.primaryDisplayText == "82%", "Claude CLI primary display")
    }

    private func claudeCLIWeeklyMissing() async throws {
        let output = """
        Current session
        71% remaining
        Resets at 11:30 PM
        """
        let snapshot = try ClaudeCLIUsageProvider.mapUsageOutput(output)
        try self.expect(snapshot.source == .claudeCLI, "Claude CLI source without weekly")
        try self.expect(snapshot.sessionPercentRemaining == 71, "Claude CLI session parses without weekly")
        try self.expect(snapshot.weeklyPercentRemaining == nil, "Claude CLI weekly can be unavailable")
    }

    private func claudeCLIMalformedOutput() async throws {
        do {
            _ = try ClaudeCLIUsageProvider.mapUsageOutput("Usage loaded but no labeled windows. 42% left.")
            throw HarnessFailure("expected malformed Claude CLI output to fail closed")
        } catch let error as ClaudeUsageProviderError {
            try self.expect(
                error.localizedDescription.contains("Current session"),
                "malformed Claude CLI output reports missing session")
        }
    }

    private func claudeCLIProviderStub() async throws {
        let stub = try Self.makeStubClaudeUsage()
        let home = try Self.makeTempDirectory()
        let probe = try Self.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: stub)
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: probe)
        }
        let provider = ClaudeCLIUsageProvider(
            env: [
                "QUOTA_PULSE_CLAUDE_CLI_PATH": stub.path,
                "QUOTA_PULSE_CLAUDE_PROBE_CWD": probe.path,
                "HOME": home.path,
            ],
            timeout: 2,
            now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let snapshot = try await provider.fetchUsage()
        try self.expect(snapshot.source == .claudeCLI, "Claude CLI provider stub source")
        try self.expect(snapshot.sessionPercentRemaining == 77, "Claude CLI provider stub session")
        try self.expect(snapshot.weeklyPercentRemaining == 66, "Claude CLI provider stub weekly")
    }

    private func claudeCLITimeout() async throws {
        let stub = try Self.makeHungStubClaude()
        let home = try Self.makeTempDirectory()
        let probe = try Self.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: stub)
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: probe)
        }
        let provider = ClaudeCLIUsageProvider(
            env: [
                "QUOTA_PULSE_CLAUDE_CLI_PATH": stub.path,
                "QUOTA_PULSE_CLAUDE_PROBE_CWD": probe.path,
                "HOME": home.path,
            ],
            timeout: 0.2)
        do {
            _ = try await provider.fetchUsage()
            throw HarnessFailure("expected Claude CLI timeout")
        } catch let error as ClaudeUsageProviderError {
            try self.expect(
                error.localizedDescription.contains("timed out"),
                "Claude CLI timeout fails closed")
        }
    }

    private func claudeCLIAllowsPracticalStateUpdate() async throws {
        let stub = try Self.makeMutatingStubClaude(relativePath: ".claude.json")
        let home = try Self.makeTempDirectory()
        let probe = try Self.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: stub)
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: probe)
        }
        let provider = ClaudeCLIUsageProvider(
            env: [
                "QUOTA_PULSE_CLAUDE_CLI_PATH": stub.path,
                "QUOTA_PULSE_CLAUDE_PROBE_CWD": probe.path,
                "HOME": home.path,
            ],
            timeout: 2)
        let snapshot = try await provider.fetchUsage()
        try self.expect(snapshot.source == .claudeCLI, "Claude CLI practical state update source")
        try self.expect(snapshot.sessionPercentRemaining == 79, "Claude CLI practical state update session")
        try self.expect(snapshot.weeklyPercentRemaining == 62, "Claude CLI practical state update weekly")
    }

    private func claudeCLIProtectedStateMutationGuard() async throws {
        let cases = [
            ".claude/settings.json",
            ".claude/.credentials.json",
            ".codex/auth.json",
            ".codex/config.toml",
        ]
        for relativePath in cases {
            let stub = try Self.makeMutatingStubClaude(relativePath: relativePath)
            let home = try Self.makeTempDirectory()
            let probe = try Self.makeTempDirectory()
            defer {
                try? FileManager.default.removeItem(at: stub)
                try? FileManager.default.removeItem(at: home)
                try? FileManager.default.removeItem(at: probe)
            }
            let provider = ClaudeCLIUsageProvider(
                env: [
                    "QUOTA_PULSE_CLAUDE_CLI_PATH": stub.path,
                    "QUOTA_PULSE_CLAUDE_PROBE_CWD": probe.path,
                    "HOME": home.path,
                ],
                timeout: 2)
            do {
                _ = try await provider.fetchUsage()
                throw HarnessFailure("expected protected state mutation guard for \(relativePath)")
            } catch let error as ClaudeUsageProviderError {
                try self.expect(
                    error.localizedDescription.contains("changed protected local state"),
                    "Claude CLI protected state mutation fails closed for \(relativePath)")
            }
        }
    }

    private func cliRPCUsageMapping() async throws {
        let stub = try Self.makeStubCodex()
        defer { try? FileManager.default.removeItem(at: stub) }
        let provider = CLIRPCCodexUsageProvider(
            env: ["QUOTA_PULSE_CODEX_PATH": stub.path],
            initializeTimeout: 2,
            requestTimeout: 2,
            now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let snapshot = try await provider.fetchUsage()
        try self.expect(snapshot.source == .cliRPC, "CLI source")
        try self.expect(snapshot.sessionPercentRemaining == 70, "CLI session remaining")
        try self.expect(snapshot.weeklyPercentRemaining == 55, "CLI weekly remaining")
    }

    private func cliRPCTimeout() async throws {
        let stub = try Self.makeHungStubCodex()
        defer { try? FileManager.default.removeItem(at: stub) }
        let provider = CLIRPCCodexUsageProvider(
            env: ["QUOTA_PULSE_CODEX_PATH": stub.path],
            initializeTimeout: 2,
            requestTimeout: 0.2)
        do {
            _ = try await provider.fetchUsage()
            throw HarnessFailure("expected timeout")
        } catch let error as CodexUsageProviderError {
            try self.expect(error == .timedOut("account/rateLimits/read"), "timeout surfaced")
        }
    }

    private func localFallbackUsageFile() async throws {
        let home = try Self.makeTempDirectory()
        let usage = home.appendingPathComponent(".codex/notchy/usage")
        try FileManager.default.createDirectory(at: usage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("25\t1800003600\t70\t1800864000\n".utf8).write(to: usage)
        let provider = LocalCodexUsageProvider(
            env: ["HOME": home.path],
            now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let snapshot = try await provider.fetchUsage()
        try self.expect(snapshot.source == .localFallback, "local source")
        try self.expect(snapshot.sessionPercentRemaining == 75, "local session remaining")
        try self.expect(snapshot.weeklyPercentRemaining == 30, "local weekly remaining")
    }

    private func localFallbackSessionScan() async throws {
        let home = try Self.makeTempDirectory()
        let sessions = home.appendingPathComponent(".codex/sessions/2026/06/19")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("session.jsonl")
        let jsonl = """
        {"type":"event_msg","payload":{"type":"other"}}
        {"type":"event_msg","payload":{"type":"token_count","rate_limits":{"five_hour":{"used_percentage":44,"resets_at":1800007200},"seven_day":{"used_percentage":68,"resets_at":1800864000}}}}
        """
        try Data(jsonl.utf8).write(to: file)
        let provider = LocalCodexUsageProvider(
            env: ["HOME": home.path],
            now: { Date(timeIntervalSince1970: 1_800_000_000) })
        let snapshot = try await provider.fetchUsage()
        try self.expect(snapshot.sessionPercentRemaining == 56, "session log session remaining")
        try self.expect(snapshot.weeklyPercentRemaining == 32, "session log weekly remaining")
    }

    private func refreshCadenceAndBackoff() async throws {
        let policy = RefreshBackoffPolicy(maximumDelay: 300)
        try self.expect(RefreshCadence.fast.interval == 30, "fast cadence")
        try self.expect(RefreshCadence.normal.interval == 60, "normal cadence")
        try self.expect(RefreshCadence.batterySaver.interval == 300, "battery saver cadence")
        try self.expect(policy.delay(base: 60, consecutiveFailures: 0) == 60, "no failure delay")
        try self.expect(policy.delay(base: 60, consecutiveFailures: 1) == 120, "first failure backoff")
        try self.expect(policy.delay(base: 60, consecutiveFailures: 10) == 300, "backoff cap")
    }

    private func refreshGateNoOverlap() async throws {
        let gate = RefreshGate()
        async let first = gate.run {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let second = await gate.run {}
        try self.expect(second == false, "second refresh skipped while first running")
        let firstResult = await first
        try self.expect(firstResult == true, "first refresh ran")
    }

    private func refreshJitterBounds() async throws {
        let minimum = RefreshJitter(randomUnit: { 0 })
        let maximum = RefreshJitter(randomUnit: { 1 })
        let cases: [(TimeInterval, TimeInterval)] = [
            (30, 5),
            (60, 10),
            (300, 30),
            (600, 60),
        ]
        for (base, bound) in cases {
            try self.expect(minimum.delay(base: base) == base - bound, "minimum jitter for \(base)")
            try self.expect(maximum.delay(base: base) == base + bound, "maximum jitter for \(base)")
        }
        try self.expect(RefreshJitter(randomUnit: { 0 }).delay(base: 2) == 1, "jitter never goes below one second")
    }

    private func smartRefreshSeparateProviderModes() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let codexStore = UsageStore(
            provider: FixtureCodexUsageProvider(mode: .success, now: { clock.now }),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let claudeStore = UsageStore(
            provider: FixtureClaudeUsageProvider(mode: .success, now: { clock.now }),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let scheduler = RefreshScheduler(
            stores: [codexStore, claudeStore],
            jitter: .none,
            now: { clock.now })

        scheduler.setMode(.seconds30, for: .codex)
        scheduler.setMode(.tenMinutes, for: .claude)

        try self.expect(scheduler.mode(for: .codex) == .seconds30, "Codex mode is independent")
        try self.expect(scheduler.mode(for: .claude) == .tenMinutes, "Claude mode is independent")
        try self.expect(Self.secondsUntil(scheduler.codexState.nextRefreshAt, from: clock.now) == 30, "Codex next refresh uses 30s")
        try self.expect(Self.secondsUntil(scheduler.claudeState.nextRefreshAt, from: clock.now) == 600, "Claude next refresh uses 10m")

        scheduler.setMode(.manual, for: .claude)
        try self.expect(scheduler.claudeState.nextRefreshAt == nil, "Claude manual mode has no automatic next refresh")
    }

    private func smartRefreshAutoPolicy() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let codexStore = UsageStore(
            provider: FixtureCodexUsageProvider(mode: .success, now: { clock.now }),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let claudeStore = UsageStore(
            provider: FixtureClaudeUsageProvider(mode: .success, now: { clock.now }),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let scheduler = RefreshScheduler(
            stores: [codexStore, claudeStore],
            jitter: .none,
            now: { clock.now })

        scheduler.setMode(.auto, for: .codex)
        scheduler.setMode(.auto, for: .claude)
        try self.expect(Self.secondsUntil(scheduler.codexState.nextRefreshAt, from: clock.now) == 30, "Codex Auto active uses fast refresh")
        try self.expect(Self.secondsUntil(scheduler.claudeState.nextRefreshAt, from: clock.now) == 300, "Claude Auto baseline is 5m")

        scheduler.setDashboardVisible(true)
        try self.expect(Self.secondsUntil(scheduler.claudeState.nextRefreshAt, from: clock.now) == 30, "Claude Auto watching dashboard can use fast refresh")

        scheduler.updatePresence(.idle)
        try self.expect(Self.secondsUntil(scheduler.codexState.nextRefreshAt, from: clock.now) == 60, "Codex Auto idle slows to 1m")
        try self.expect(Self.secondsUntil(scheduler.claudeState.nextRefreshAt, from: clock.now) == 300, "Claude Auto idle uses baseline")
    }

    private func smartRefreshPresencePauseAndWake() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let codexStore = UsageStore(
            provider: FixtureCodexUsageProvider(mode: .success, now: { clock.now }),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let claudeStore = UsageStore(
            provider: FixtureClaudeUsageProvider(mode: .success, now: { clock.now }),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let scheduler = RefreshScheduler(
            stores: [codexStore, claudeStore],
            jitter: .none,
            now: { clock.now })

        scheduler.setMode(.auto, for: .codex)
        scheduler.setMode(.auto, for: .claude)
        scheduler.updatePresence(.locked)
        try self.expect(scheduler.summaryText == "Paused: screen locked", "locked state reports paused")
        try self.expect(scheduler.codexState.nextRefreshAt == nil, "locked pauses Codex auto refresh")
        try self.expect(scheduler.claudeState.nextRefreshAt == nil, "locked pauses Claude auto refresh")

        scheduler.updatePresence(.active)
        try self.expect(Self.secondsUntil(scheduler.codexState.nextRefreshAt, from: clock.now) == 6, "unlock schedules delayed Codex refresh")
        try self.expect(Self.secondsUntil(scheduler.claudeState.nextRefreshAt, from: clock.now) == 6, "unlock schedules delayed Claude refresh")

        scheduler.updatePresence(.asleep)
        try self.expect(scheduler.summaryText == "Paused: asleep", "display sleep reports paused")
    }

    private func smartRefreshClaudeUnchangedBaseline() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let codexStore = UsageStore(
            provider: FixtureCodexUsageProvider(mode: .success, now: { clock.now }),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let claudeStore = UsageStore(
            provider: FixtureClaudeUsageProvider(mode: .success, now: { clock.now }),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let scheduler = RefreshScheduler(
            stores: [codexStore, claudeStore],
            jitter: .none,
            now: { clock.now })
        scheduler.setDashboardVisible(true)

        await scheduler.refreshProviderForTesting(ProviderKind.claude)
        await scheduler.refreshProviderForTesting(ProviderKind.claude)
        await scheduler.refreshProviderForTesting(ProviderKind.claude)
        await scheduler.refreshProviderForTesting(ProviderKind.claude)

        try self.expect(scheduler.claudeState.unchangedSuccesses >= 3, "Claude unchanged successful polls are counted")
        try self.expect(Self.secondsUntil(scheduler.claudeState.nextRefreshAt, from: clock.now) == 300, "Claude returns to 5m after unchanged polls")
    }

    private func smartRefreshManualCooldownSkip() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let resolver = SequencedClaudeCredentialResolver(records: [
            Self.claudeCredentialRecord(accessToken: "rate-limit-credential"),
        ])
        let client = SequencedHTTPClient(responsesWithHeaders: [
            (
                200,
                #"{"five_hour":{"utilization":0,"resets_at":"2027-01-15T03:12:00Z"}}"#,
                [:]
            ),
            (
                429,
                "{}",
                ["Retry-After": "120"]
            ),
        ])
        let codexStore = UsageStore(
            provider: FixtureCodexUsageProvider(mode: .success, now: { clock.now }),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let claudeProvider = ReloadingClaudeOAuthUsageProvider(
            env: ["QUOTA_PULSE_CLAUDE_USAGE_URL": "https://example.test/claude-usage"],
            httpClient: client,
            credentialResolver: resolver,
            now: { clock.now })
        let claudeStore = UsageStore(provider: claudeProvider, cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let scheduler = RefreshScheduler(
            stores: [codexStore, claudeStore],
            jitter: .none,
            now: { clock.now })

        await scheduler.refreshProviderForTesting(.claude)
        await scheduler.refreshProviderForTesting(.claude)
        try self.expect(client.requestCount == 2, "Claude OAuth sees initial success and 429")
        try self.expect(scheduler.claudeState.cooldownUntil != nil, "scheduler records Claude cooldown")

        scheduler.refresh(provider: .claude, manual: true)
        try self.expect(client.requestCount == 2, "manual refresh during cooldown does not call Claude OAuth")
        try self.expect(scheduler.summaryText.contains("Claude cooldown"), "manual cooldown skip is visible")
    }

    private func smartRefreshCountdownTextUsesSuppliedNow() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let codexStore = UsageStore(
            provider: FixtureCodexUsageProvider(mode: .success, now: { clock.now }),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let claudeStore = UsageStore(
            provider: FixtureClaudeUsageProvider(mode: .success, now: { clock.now }),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let scheduler = RefreshScheduler(
            stores: [codexStore, claudeStore],
            jitter: .none,
            now: { clock.now })

        scheduler.setMode(.seconds30, for: .codex)
        scheduler.setMode(.fiveMinutes, for: .claude)

        try self.expect(
            scheduler.summaryText(now: clock.now).contains("Codex 30s"),
            "countdown starts at scheduled delay")
        try self.expect(
            scheduler.nextText(for: .codex, now: clock.now.addingTimeInterval(7)) == "23s",
            "countdown text updates when the view supplies a later time")
        try self.expect(
            scheduler.summaryText(now: clock.now.addingTimeInterval(7)).contains("Codex 23s"),
            "summary text uses supplied render time")
    }

    private func smartRefreshSchedulerDebounce() async throws {
        let provider = DelayedCountingProvider(delayNanoseconds: 150_000_000)
        let store = UsageStore(provider: provider, cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let scheduler = RefreshScheduler(stores: [store], jitter: .none)
        scheduler.setMode(.manual, for: .codex)

        scheduler.refresh(provider: .codex, manual: true)
        try self.expect(scheduler.codexState.isRefreshing, "scheduler enters refreshing state immediately")

        scheduler.refresh(provider: .codex, manual: true)
        try self.expect(scheduler.codexState.isRefreshing, "duplicate refresh keeps scheduler refreshing")

        let deadline = Date().addingTimeInterval(1)
        while await provider.count() == 0, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        let startedFetchCount = await provider.count()
        try self.expect(startedFetchCount == 1, "only one provider fetch starts during duplicate refresh")

        scheduler.refresh(provider: .codex, manual: true)
        try self.expect(scheduler.codexState.isRefreshing, "duplicate refresh after fetch start stays refreshing")
        try await Task.sleep(nanoseconds: 220_000_000)
        let completedFetchCount = await provider.count()
        try self.expect(completedFetchCount == 1, "duplicate refresh does not start another provider fetch")
        try self.expect(!scheduler.codexState.isRefreshing, "scheduler exits refreshing after original fetch finishes")
        try self.expect(store.snapshot.sessionPercentRemaining == 73, "original fetch stores latest snapshot")
    }

    private func usageStoreRefreshFeedbackDebounce() async throws {
        let store = UsageStore(
            provider: DelayedProvider(delayNanoseconds: 150_000_000),
            cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))

        async let firstRefresh = store.refresh()
        let deadline = Date().addingTimeInterval(1)
        while !store.isRefreshing, Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        try self.expect(store.isRefreshing, "store enters visible refreshing state")
        let secondRefresh = await store.refresh()
        try self.expect(!secondRefresh, "repeated refresh is ignored while running")
        let firstResult = await firstRefresh
        try self.expect(firstResult, "first refresh completes")
        try self.expect(!store.isRefreshing, "store exits refreshing state")
        try self.expect(store.snapshot.sessionPercentRemaining == 74, "refresh stores latest snapshot")
    }

    private func usageStoreStaleLastGood() async throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-pulse-cache-\(UUID().uuidString).json")
        let cache = UsageSnapshotCache(url: cacheURL)
        let good = try await FixtureCodexUsageProvider(mode: .success).fetchUsage()
        cache.save(good)
        let store = UsageStore(provider: FailingProvider(), cache: cache)
        _ = await store.refresh()
        try self.expect(store.snapshot.isStale, "failed refresh marks stale")
        try self.expect(store.snapshot.sessionPercentRemaining == good.sessionPercentRemaining, "last good retained")
        try self.expect(store.consecutiveFailures == 1, "failure counted")
    }

    private func codexRefreshWhileClaudeRateLimited() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let codexProvider = CountingProvider()
        let claudeResolver = SequencedClaudeCredentialResolver(records: [
            Self.claudeCredentialRecord(accessToken: "rate-limit-credential"),
        ])
        let claudeClient = SequencedHTTPClient(responsesWithHeaders: [
            (
                200,
                #"{"five_hour":{"utilization":10,"resets_at":"2027-01-15T03:12:00Z"}}"#,
                [:]
            ),
            (
                429,
                "{}",
                ["Retry-After": "300"]
            ),
        ])
        let claudeProvider = ReloadingClaudeOAuthUsageProvider(
            env: ["QUOTA_PULSE_CLAUDE_USAGE_URL": "https://example.test/claude-usage"],
            httpClient: claudeClient,
            credentialResolver: claudeResolver,
            now: { clock.now })
        let codexStore = UsageStore(provider: codexProvider, cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))
        let claudeStore = UsageStore(provider: claudeProvider, cache: UsageSnapshotCache(url: Self.makeTempCacheURL()))

        let initialCodexRefresh = await codexStore.refresh()
        let initialClaudeRefresh = await claudeStore.refresh()
        try self.expect(initialCodexRefresh, "initial Codex refresh succeeds")
        try self.expect(initialClaudeRefresh, "initial Claude refresh succeeds")

        let secondCodexRefresh = await codexStore.refresh()
        let secondClaudeRefresh = await claudeStore.refresh()
        let codexFetchCount = await codexProvider.count()
        try self.expect(secondCodexRefresh, "Codex refresh succeeds while Claude becomes rate-limited")
        try self.expect(secondClaudeRefresh, "Claude rate-limit refresh completes as stale failure")
        try self.expect(codexFetchCount == 2, "Codex provider is called independently")
        try self.expect(codexStore.snapshot.sessionPercentRemaining == 88, "Codex snapshot updates while Claude is rate-limited")
        try self.expect(claudeStore.snapshot.isStale, "Claude snapshot is stale after rate limit")
        try self.expect(claudeStore.snapshot.sessionPercentRemaining == 90, "Claude stale snapshot preserves last good value")
        try self.expect(claudeClient.requestCount == 2, "Claude OAuth was only called for initial and 429 attempts")
    }

    private func dualProviderIndependentFailure() async throws {
        let codexCache = UsageSnapshotCache(url: Self.makeTempCacheURL())
        let claudeCache = UsageSnapshotCache(url: Self.makeTempCacheURL())
        let codexStore = UsageStore(provider: FixtureCodexUsageProvider(mode: .success), cache: codexCache)
        let claudeStore = UsageStore(provider: FailingProvider(), cache: claudeCache)

        _ = await codexStore.refresh()
        _ = await claudeStore.refresh()

        try self.expect(codexStore.snapshot.sessionPercentRemaining == 63, "Codex remains visible")
        try self.expect(claudeStore.snapshot.primaryDisplayText == "ERR", "Claude failure is provider-specific")
        try self.expect(claudeStore.snapshot.errorMessage?.contains("secret-token") == false, "Claude error redacted")
    }

    private func dualProviderTitleFormatter() async throws {
        let codex = try await FixtureCodexUsageProvider(mode: .success).fetchUsage()
        let claude = try await FixtureClaudeUsageProvider(mode: .success).fetchUsage()
        let title = UsageDisplayFormatter.title(codex: codex, claude: claude)
        let compact = UsageDisplayFormatter.compactTitle(codex: codex, claude: claude)
        let multiline = UsageDisplayFormatter.menuBarMultilineText(codex: codex, claude: claude)
        try self.expect(title.contains("Codex 63%"), "title includes Codex")
        try self.expect(title.contains("Claude 85%"), "title includes Claude")
        try self.expect(compact.contains("Cx 63%"), "compact title includes Codex")
        try self.expect(compact.contains("Cl 85%"), "compact title includes Claude")
        try self.expect(multiline == "Cx 63%\nCl 85%", "menu bar multiline text includes both providers")

        let errorText = UsageDisplayFormatter.menuBarCompactText(
            codex: UsageSnapshot.error("codex unavailable"),
            claude: claude)
        try self.expect(errorText.contains("Cx ERR"), "Codex error is isolated in menu bar text")
        try self.expect(errorText.contains("Cl 85%"), "Claude remains visible when Codex errors")
        try self.expect(UsageDisplayFormatter.progressFraction(forRemainingPercent: 63) == 0.63, "progress maps percent")
        try self.expect(UsageDisplayFormatter.progressFraction(forRemainingPercent: -10) == 0, "progress clamps low")
        try self.expect(UsageDisplayFormatter.progressFraction(forRemainingPercent: 120) == 1, "progress clamps high")
        try self.expect(UsageDisplayFormatter.progressFraction(forRemainingPercent: nil) == nil, "progress allows unavailable")
    }

    private static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeTempCacheURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-pulse-cache-\(UUID().uuidString).json")
    }

    private static func secondsUntil(_ date: Date?, from now: Date) -> Int? {
        date.map { Int(round($0.timeIntervalSince(now))) }
    }

    private static func claudeCredentialsJSON(accessToken: String) -> String {
        """
        {"claudeAiOauth":{"accessToken":"\(accessToken)","refreshToken":"refresh","expiresAt":1800000000000,"scopes":["user:profile"]}}
        """
    }

    private static func claudeCredentialRecord(accessToken: String) -> ClaudeOAuthCredentialRecord {
        ClaudeOAuthCredentialRecord(
            credentials: ClaudeOAuthCredentials(
                accessToken: accessToken,
                refreshToken: nil,
                expiresAt: nil,
                scopes: ["user:profile"]),
            source: .claudeCodeKeychain)
    }

    private static func makeStubCodex() throws -> URL {
        let script = """
        #!/usr/bin/python3 -S
        import json
        import sys
        if "app-server" not in sys.argv:
            sys.exit(92)
        for line in sys.stdin:
            if not line.strip():
                continue
            message = json.loads(line)
            method = message.get("method")
            if method == "initialized":
                continue
            identifier = message.get("id")
            if method == "initialize":
                payload = {"id": identifier, "result": {}}
            elif method == "account/rateLimits/read":
                payload = {"id": identifier, "result": {"rateLimits": {"primary": {"usedPercent": 30, "windowDurationMins": 300, "resetsAt": 1800003600}, "secondary": {"usedPercent": 45, "windowDurationMins": 10080, "resetsAt": 1800864000}}}}
            else:
                payload = {"id": identifier, "result": {}}
            print(json.dumps(payload), flush=True)
        """
        return try Self.writeExecutable(script)
    }

    private static func makeHungStubCodex() throws -> URL {
        let script = """
        #!/usr/bin/python3 -S
        import json
        import time
        import sys
        if "app-server" not in sys.argv:
            sys.exit(92)
        for line in sys.stdin:
            if not line.strip():
                continue
            message = json.loads(line)
            method = message.get("method")
            if method == "initialized":
                continue
            identifier = message.get("id")
            if method == "initialize":
                print(json.dumps({"id": identifier, "result": {}}), flush=True)
            elif method == "account/rateLimits/read":
                time.sleep(30)
        """
        return try Self.writeExecutable(script)
    }

    private static func makeStubClaudeUsage() throws -> URL {
        let script = """
        #!/usr/bin/python3 -S
        import sys
        _ = sys.stdin.read()
        print("Usage")
        print("Current session")
        print("77% left")
        print("Resets at 9:45 PM")
        print("Current week")
        print("66% remaining")
        print("Resets Jan 15, 3:12 AM")
        """
        return try Self.writeExecutable(script)
    }

    private static func makeHungStubClaude() throws -> URL {
        let script = """
        #!/usr/bin/python3 -S
        import time
        time.sleep(30)
        """
        return try Self.writeExecutable(script)
    }

    private static func makeMutatingStubClaude(relativePath: String) throws -> URL {
        let escapedPath = relativePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        #!/usr/bin/python3 -S
        import os
        import sys
        _ = sys.stdin.read()
        home = os.environ.get("HOME")
        if home:
            path = os.path.join(home, "\(escapedPath)")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as handle:
                handle.write("{\\"mutated\\":true}\\n")
        print("Usage")
        print("Current session")
        print("79% left")
        print("Current week")
        print("62% remaining")
        """
        return try Self.writeExecutable(script)
    }

    private static func writeExecutable(_ script: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("codex-stub-\(UUID().uuidString)")
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}

private struct HarnessFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { self.message }
}

private final class TestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

private final class KeychainReadCounter: @unchecked Sendable {
    var calls = 0
}

private struct StubClaudeKeychainReader: ClaudeOAuthKeychainReading {
    let data: Data?
    let error: Error?
    let counter: KeychainReadCounter?

    init(data: Data? = nil, error: Error? = nil, counter: KeychainReadCounter? = nil) {
        self.data = data
        self.error = error
        self.counter = counter
    }

    func readClaudeOAuthCredentialData(allowUserPrompt: Bool) throws -> Data? {
        self.counter?.calls += 1
        if let error {
            throw error
        }
        return self.data
    }
}

private actor CountingProvider: CodexUsageProviding {
    private var fetchCount = 0

    func fetchUsage() async throws -> UsageSnapshot {
        self.fetchCount += 1
        return UsageSnapshot(
            sessionPercentRemaining: Double(90 - self.fetchCount),
            weeklyPercentRemaining: 70,
            sessionResetAt: nil,
            weeklyResetAt: nil,
            source: .oauth,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(self.fetchCount)))
    }

    func count() -> Int {
        self.fetchCount
    }
}

private actor DelayedCountingProvider: CodexUsageProviding {
    private let delayNanoseconds: UInt64
    private var fetchCount = 0

    init(delayNanoseconds: UInt64) {
        self.delayNanoseconds = delayNanoseconds
    }

    func fetchUsage() async throws -> UsageSnapshot {
        self.fetchCount += 1
        try await Task.sleep(nanoseconds: self.delayNanoseconds)
        return UsageSnapshot(
            sessionPercentRemaining: Double(74 - self.fetchCount),
            weeklyPercentRemaining: 55,
            sessionResetAt: nil,
            weeklyResetAt: nil,
            source: .fixture,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(self.fetchCount)))
    }

    func count() -> Int {
        self.fetchCount
    }
}

private struct DelayedProvider: CodexUsageProviding, Sendable {
    let delayNanoseconds: UInt64

    func fetchUsage() async throws -> UsageSnapshot {
        try await Task.sleep(nanoseconds: self.delayNanoseconds)
        return UsageSnapshot(
            sessionPercentRemaining: 74,
            weeklyPercentRemaining: 55,
            sessionResetAt: nil,
            weeklyResetAt: nil,
            source: .fixture,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}

private final class StubHTTPClient: UsageHTTPClient, @unchecked Sendable {
    private let statusCode: Int
    private let body: String
    private(set) var lastRequest: URLRequest?

    init(statusCode: Int = 200, body: String = "{}") {
        self.statusCode = statusCode
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.lastRequest = request
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: self.statusCode,
            httpVersion: nil,
            headerFields: nil)!
        return (Data(self.body.utf8), response)
    }
}

private final class SequencedHTTPClient: UsageHTTPClient, @unchecked Sendable {
    private struct Response {
        let statusCode: Int
        let body: String
        let headers: [String: String]
    }

    private var responses: [Response]
    private(set) var requests: [URLRequest] = []

    init(responses: [(Int, String)]) {
        self.responses = responses.map {
            Response(statusCode: $0.0, body: $0.1, headers: [:])
        }
    }

    init(responsesWithHeaders: [(Int, String, [String: String])]) {
        self.responses = responsesWithHeaders.map {
            Response(statusCode: $0.0, body: $0.1, headers: $0.2)
        }
    }

    var requestCount: Int {
        self.requests.count
    }

    var authorizationValues: [String] {
        self.requests.compactMap { $0.value(forHTTPHeaderField: "Authorization") }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.requests.append(request)
        let responsePayload = self.responses.isEmpty
            ? Response(statusCode: 500, body: "{}", headers: [:])
            : self.responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responsePayload.statusCode,
            httpVersion: nil,
            headerFields: responsePayload.headers)!
        return (Data(responsePayload.body.utf8), response)
    }
}

private final class SequencedClaudeCredentialResolver: ClaudeOAuthCredentialResolving, @unchecked Sendable {
    private var records: [ClaudeOAuthCredentialRecord]
    private(set) var loadCount = 0

    init(records: [ClaudeOAuthCredentialRecord]) {
        self.records = records
    }

    func loadRecord(env: [String: String]) throws -> ClaudeOAuthCredentialRecord {
        self.loadCount += 1
        guard !self.records.isEmpty else {
            throw ClaudeUsageProviderError.missingCredentials
        }
        return self.records.removeFirst()
    }
}

private struct FailingProvider: CodexUsageProviding {
    func fetchUsage() async throws -> UsageSnapshot {
        throw CodexUsageProviderError.processFailed("Bearer secret-token")
    }
}
