import AppKit
import QuotaPulseCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let automaticTerminationReason = "QuotaPulse menu bar status item is active."
    private static let claudeOAuthMinimumInterval: TimeInterval = 5 * 60
    private var codexStore: UsageStore?
    private var claudeStore: UsageStore?
    private var scheduler: RefreshScheduler?
    private var statusItemController: StatusItemController?
    private var notchPillController: NotchPillController?
    private var wakeObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(self.automaticTerminationReason)

        let providers = Self.makeProviders()
        let codexStore = UsageStore(provider: providers.codex)
        let claudeStore = UsageStore(
            provider: providers.claude,
            cache: UsageSnapshotCache(url: Self.claudeCacheURL()))
        let scheduler = RefreshScheduler(stores: [codexStore, claudeStore])

        self.codexStore = codexStore
        self.claudeStore = claudeStore
        self.scheduler = scheduler
        self.statusItemController = StatusItemController(
            codexStore: codexStore,
            claudeStore: claudeStore,
            scheduler: scheduler)
        if Self.shouldShowNotchPill() {
            self.notchPillController = NotchPillController(
                codexStore: codexStore,
                claudeStore: claudeStore,
                scheduler: scheduler)
            self.notchPillController?.showIfAvailable()
        }

        self.wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.scheduler?.refreshNow()
                }
            }

        if self.notchPillController != nil {
            self.screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        self?.notchPillController?.showIfAvailable()
                    }
                }
        }

        scheduler.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.scheduler?.stop()
        ProcessInfo.processInfo.enableAutomaticTermination(self.automaticTerminationReason)
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    private static func makeProviders() -> (codex: any CodexUsageProviding, claude: any CodexUsageProviding) {
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        let fixtureValue = QuotaPulseEnvironment.value("QUOTA_PULSE_FIXTURE", in: env)
            ?? args.dropFirst().first { $0.hasPrefix("--fixture=") }?.replacingOccurrences(of: "--fixture=", with: "")

        if let fixtureValue {
            let mode = FixtureCodexUsageProvider.Mode(rawValue: fixtureValue) ?? .success
            let claudeMode = FixtureClaudeUsageProvider.Mode(rawValue: fixtureValue) ?? .success
            return (
                FixtureCodexUsageProvider(mode: mode),
                FixtureClaudeUsageProvider(mode: claudeMode))
        }

        let claudeFixtureValue = QuotaPulseEnvironment.value("QUOTA_PULSE_CLAUDE_FIXTURE", in: env)
            ?? args.dropFirst().first { $0.hasPrefix("--claude-fixture=") }?
                .replacingOccurrences(of: "--claude-fixture=", with: "")
        let claudeProvider: any CodexUsageProviding
        if let claudeFixtureValue {
            let mode = FixtureClaudeUsageProvider.Mode(rawValue: claudeFixtureValue) ?? .success
            claudeProvider = FixtureClaudeUsageProvider(mode: mode)
        } else {
            claudeProvider = Self.makeClaudeProvider(env: env)
        }

        return (CascadingCodexUsageProvider(providers: [
            OAuthCodexUsageProvider(env: env, httpClient: URLSessionUsageHTTPClient()),
            CLIRPCCodexUsageProvider(env: env),
            LocalCodexUsageProvider(env: env),
        ]), claudeProvider)
    }

    private static func makeClaudeProvider(env: [String: String]) -> any CodexUsageProviding {
        let cliFallbackEnabled = QuotaPulseEnvironment.isEnabled("QUOTA_PULSE_ENABLE_CLAUDE_CLI", in: env)
        if QuotaPulseEnvironment.isEnabled("QUOTA_PULSE_DISABLE_CLAUDE_OAUTH", in: env) {
            if cliFallbackEnabled {
                return ClaudeCLIUsageProvider(env: env)
            }
            return DisabledClaudeUsageProvider(
                message: "Claude OAuth is disabled by QUOTA_PULSE_DISABLE_CLAUDE_OAUTH=1 and CLI fallback is disabled.")
        }

        let credentialsResult: Result<ClaudeOAuthCredentialRecord, Error> = Result {
            try ClaudeOAuthCredentialsStore.loadRecord(env: env)
        }
        let credentials = try? credentialsResult.get().credentials
        let credentialErrorMessage: String? = {
            guard credentials == nil else { return nil }
            if case let .failure(error) = credentialsResult {
                if let claudeError = error as? ClaudeUsageProviderError,
                   claudeError == .missingCredentials
                {
                    return nil
                }
                return error.localizedDescription
            }
            return nil
        }()
        let plan = ClaudeUsageSourcePlanner.plan(
            hasOAuthCredentials: credentials != nil,
            oauthCredentialErrorMessage: credentialErrorMessage,
            cliFallbackEnabled: cliFallbackEnabled)

        var providers: [any CodexUsageProviding] = []
        for source in plan.orderedSources {
            switch source {
            case .oauth:
                guard let credentials else { continue }
                providers.append(RateLimitedUsageProvider(
                    provider: OAuthClaudeUsageProvider(
                        credentials: credentials,
                        env: env,
                        httpClient: URLSessionUsageHTTPClient()),
                    minimumInterval: Self.claudeOAuthMinimumInterval))
            case .cli:
                providers.append(ClaudeCLIUsageProvider(env: env))
            case .disabled:
                providers.append(DisabledClaudeUsageProvider())
            case .failure:
                providers.append(ImmediateFailureUsageProvider(
                    message: plan.failureMessage ?? "Claude OAuth credentials could not be used."))
            }
        }

        if providers.count == 1, let provider = providers.first {
            return provider
        }
        if providers.isEmpty {
            return DisabledClaudeUsageProvider()
        }
        return CascadingCodexUsageProvider(providers: providers)
    }

    private static func claudeCacheURL() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/QuotaPulse/last-claude-snapshot.json")
    }

    private static func shouldShowNotchPill(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        QuotaPulseEnvironment.isEnabled("QUOTA_PULSE_SHOW_NOTCH", in: env)
    }
}
