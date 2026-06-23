import Foundation
import Testing
import QuotaPulseCore

struct UsageCoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func testMenuBarDisplayStates() {
        let codex = UsageSnapshot(
            sessionPercentRemaining: 63,
            weeklyPercentRemaining: 39,
            sessionResetAt: nil,
            weeklyResetAt: nil,
            source: .oauth,
            updatedAt: self.now)

        let healthyClaude = UsageSnapshot(
            sessionPercentRemaining: 92,
            weeklyPercentRemaining: 82,
            sessionResetAt: self.now.addingTimeInterval(3_600),
            weeklyResetAt: nil,
            source: .oauth,
            updatedAt: self.now)
        #expect(
            UsageDisplayFormatter.menuBarCompactText(codex: codex, claude: healthyClaude, now: self.now)
                .contains("Cl 92%"))

        let staleClaude = UsageSnapshot(
            sessionPercentRemaining: 89,
            weeklyPercentRemaining: 82,
            sessionResetAt: self.now.addingTimeInterval(3_600),
            weeklyResetAt: nil,
            source: .oauth,
            updatedAt: self.now)
            .markedStale(errorMessage: "Claude OAuth usage failed: OAuth unauthorized; run Claude to refresh login.")
        let staleText = UsageDisplayFormatter.menuBarCompactText(codex: codex, claude: staleClaude, now: self.now)
        #expect(staleText.contains("Cl 89!"))
        #expect(!staleText.contains("Cl 89%"))
        #expect(!staleText.contains("Cl ERR"))

        let authBlockedUnavailable = UsageSnapshot.error("OAuth unauthorized; run Claude to refresh login.", updatedAt: self.now)
        #expect(
            UsageDisplayFormatter.menuBarCompactText(codex: codex, claude: authBlockedUnavailable, now: self.now)
                .contains("Cl --!"))

        let hardError = UsageSnapshot.error("Provider unavailable", updatedAt: self.now)
        #expect(
            UsageDisplayFormatter.menuBarCompactText(codex: codex, claude: hardError, now: self.now)
                .contains("Cl ERR"))
    }

    @Test
    func testPacingReserveDeficitAndProjection() throws {
        let reserveWindow = UsageWindow(
            usedPercent: 40,
            resetAt: self.now.addingTimeInterval(50),
            windowSeconds: 100)
        let reservePace = try #require(UsagePace(window: reserveWindow, now: self.now))
        #expect(reservePace.expectedUsedPercent == 50)
        #expect(reservePace.actualUsedPercent == 40)
        #expect(reservePace.balance == .reserve(10))
        #expect(UsagePaceFormatter.balanceText(reservePace) == "10% in reserve")
        #expect(reservePace.lastsUntilReset)
        #expect(UsagePaceFormatter.projectionText(reservePace, now: self.now) == "Lasts until reset")

        let deficitWindow = UsageWindow(
            usedPercent: 75,
            resetAt: self.now.addingTimeInterval(300),
            windowSeconds: 600)
        let deficitPace = try #require(UsagePace(window: deficitWindow, now: self.now))
        #expect(deficitPace.balance == .deficit(25))
        #expect(UsagePaceFormatter.balanceText(deficitPace) == "25% in deficit")
        #expect(UsagePaceFormatter.expectedUsedText(deficitPace) == "Expected 50% used")
        #expect(!deficitPace.lastsUntilReset)
        #expect(UsagePaceFormatter.projectionText(deficitPace, now: self.now) == "Runs out in 1m")
    }

    @Test
    func testResetCountdownEdgeCases() {
        #expect(UsageSnapshot.countdown(to: self.now.addingTimeInterval(61), now: self.now) == "1m")
        #expect(UsageSnapshot.countdown(to: self.now.addingTimeInterval(3_601), now: self.now) == "1h 0m")
        #expect(UsageSnapshot.countdown(to: self.now.addingTimeInterval(86_401), now: self.now) == "1d 0h")
        #expect(UsageSnapshot.countdown(to: self.now.addingTimeInterval(-1), now: self.now) == "0m")
    }

    @Test
    func testClaudeAuthStateClassification() {
        let authMessages = [
            "OAuth unauthorized; run Claude to refresh login.",
            "Claude login expired. Open Claude Code to refresh login, then press Refresh.",
            "HTTP 403 forbidden",
        ]
        for message in authMessages {
            #expect(UsageSnapshot.isAuthFailureMessage(message), Comment(rawValue: message))
            #expect(!UsageSnapshot.isRateLimitMessage(message), Comment(rawValue: message))
        }

        #expect(UsageSnapshot.isRateLimitMessage("OAuth rate limited; wait a few minutes, then refresh."))
        #expect(!UsageSnapshot.isAuthFailureMessage("OAuth rate limited; wait a few minutes, then refresh."))

        let disabled = UsageSnapshot(
            sessionPercentRemaining: nil,
            weeklyPercentRemaining: nil,
            sessionResetAt: nil,
            weeklyResetAt: nil,
            source: .disabled,
            updatedAt: self.now,
            errorMessage: "Claude usage is unavailable: OAuth credentials were not found and CLI fallback is disabled.")
        #expect(!disabled.isAuthBlocked)
        #expect(UsageDiagnosticsFormatter.errorCategory(provider: .claude, snapshot: disabled, lastErrorMessage: disabled.errorMessage) == "Credentials unavailable")
        #expect(UsageDiagnosticsFormatter.credentialMode(provider: .claude, snapshot: disabled) == "Safe startup: Claude login not checked")
    }

    @Test
    func testDiagnosticsSanitization() {
        let snapshot = UsageSnapshot.error("""
        Authorization: Bearer DUMMY
        Cookie: session=DUMMY
        sk-DUMMYKEY
        {"access_token":"DUMMY","refreshToken":"DUMMY","idToken":"DUMMY","authorization":"Bearer DUMMY","cookie":"DUMMY"}
        """, updatedAt: self.now)

        let message = snapshot.errorMessage ?? ""
        #expect(!message.localizedCaseInsensitiveContains("Authorization:"))
        #expect(!message.contains("Bearer DUMMY"))
        #expect(!message.contains("session=DUMMY"))
        #expect(!message.contains("sk-DUMMYKEY"))
        #expect(!message.contains(#""access_token":"DUMMY""#))
        #expect(!message.contains(#""refreshToken":"DUMMY""#))
        #expect(!message.contains(#""idToken":"DUMMY""#))

        let diagnostics = UsageDiagnosticsFormatter.sanitizedDiagnosticsText("""
        Authorization: Bearer DUMMY
        /Users/example/private/config-a.json
        /Users/example/private/config-b.json
        """)
        #expect(!diagnostics.localizedCaseInsensitiveContains("Authorization:"))
        #expect(!diagnostics.contains("Bearer DUMMY"))
        #expect(!diagnostics.contains("/Users/example"))
        #expect(diagnostics.contains("[path]"))
    }
}
