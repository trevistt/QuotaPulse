import AppKit
import QuotaPulseCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let automaticTerminationReason = "QuotaPulse menu bar status item is active."
    private var codexStore: UsageStore?
    private var claudeStore: UsageStore?
    private var scheduler: RefreshScheduler?
    private var codexAnalyticsStore: LocalUsageAnalyticsStore?
    private var claudeAnalyticsStore: LocalUsageAnalyticsStore?
    private var analyticsScheduler: LocalUsageAnalyticsScheduler?
    private var providerOrderStore: ProviderOrderStore?
    private var statusItemController: StatusItemController?
    private var notchPillController: NotchPillController?
    private let claudePromptGate = ClaudeOAuthPromptGate()
    private var presenceMonitor: UserPresenceMonitor?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination(self.automaticTerminationReason)

        let providers = Self.makeProviders(claudePromptGate: self.claudePromptGate)
        let codexStore = UsageStore(provider: providers.codex)
        let claudeStore = UsageStore(
            provider: providers.claude,
            cache: UsageSnapshotCache(url: Self.claudeCacheURL()))
        let scheduler = RefreshScheduler(stores: [codexStore, claudeStore])
        let env = ProcessInfo.processInfo.environment
        let codexAnalyticsStore = LocalUsageAnalyticsStore(
            providerKind: .codex,
            provider: CodexLocalLogAnalyticsProvider(env: env))
        let claudeAnalyticsStore = LocalUsageAnalyticsStore(
            providerKind: .claude,
            provider: ClaudeLocalLogAnalyticsProvider(env: env))
        let analyticsScheduler = LocalUsageAnalyticsScheduler(stores: [codexAnalyticsStore, claudeAnalyticsStore])
        let providerOrderStore = ProviderOrderStore()

        self.codexStore = codexStore
        self.claudeStore = claudeStore
        self.scheduler = scheduler
        self.codexAnalyticsStore = codexAnalyticsStore
        self.claudeAnalyticsStore = claudeAnalyticsStore
        self.analyticsScheduler = analyticsScheduler
        self.providerOrderStore = providerOrderStore
        self.statusItemController = StatusItemController(
            codexStore: codexStore,
            claudeStore: claudeStore,
            scheduler: scheduler,
            codexAnalyticsStore: codexAnalyticsStore,
            claudeAnalyticsStore: claudeAnalyticsStore,
            analyticsScheduler: analyticsScheduler,
            providerOrderStore: providerOrderStore,
            onRepairClaudeLogin: { [weak self, weak scheduler] in
                self?.claudePromptGate.allowNextPrompt()
                scheduler?.repairClaudeLogin()
            })
        self.presenceMonitor = UserPresenceMonitor { [weak scheduler] state in
            scheduler?.updatePresence(state)
        }
        self.presenceMonitor?.start()
        if Self.shouldShowNotchPill() {
            self.notchPillController = NotchPillController(
                codexStore: codexStore,
                claudeStore: claudeStore,
                scheduler: scheduler,
                codexAnalyticsStore: codexAnalyticsStore,
                claudeAnalyticsStore: claudeAnalyticsStore,
                analyticsScheduler: analyticsScheduler,
                providerOrderStore: providerOrderStore)
            self.notchPillController?.showIfAvailable()
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
        analyticsScheduler.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.scheduler?.stop()
        self.analyticsScheduler?.stop()
        self.presenceMonitor?.stop()
        ProcessInfo.processInfo.enableAutomaticTermination(self.automaticTerminationReason)
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    private static func makeProviders(claudePromptGate: ClaudeOAuthPromptGate? = nil) -> (codex: any CodexUsageProviding, claude: any CodexUsageProviding) {
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
            claudeProvider = Self.makeClaudeProvider(env: env, promptGate: claudePromptGate)
        }

        return (CascadingCodexUsageProvider(providers: [
            OAuthCodexUsageProvider(env: env, httpClient: URLSessionUsageHTTPClient()),
            CLIRPCCodexUsageProvider(env: env),
            LocalCodexUsageProvider(env: env),
        ]), claudeProvider)
    }

    private static func makeClaudeProvider(env: [String: String], promptGate: ClaudeOAuthPromptGate?) -> any CodexUsageProviding {
        let cliFallbackEnabled = QuotaPulseEnvironment.isEnabled("QUOTA_PULSE_ENABLE_CLAUDE_CLI", in: env)
            && QuotaPulseEnvironment.isEnabled("QUOTA_PULSE_LAUNCHER_ENABLE_CLAUDE_CLI", in: env)
        if QuotaPulseEnvironment.isEnabled("QUOTA_PULSE_DISABLE_CLAUDE_OAUTH", in: env) {
            if cliFallbackEnabled {
                return ClaudeCLIUsageProvider(env: env)
            }
            return DisabledClaudeUsageProvider(
                message: "Claude OAuth is disabled by QUOTA_PULSE_DISABLE_CLAUDE_OAUTH=1 and CLI fallback is disabled.")
        }

        let credentialsResult: Result<ClaudeOAuthCredentialRecord, Error> = Result {
            try ClaudeOAuthCredentialsStore.loadRecord(env: env, allowUserPromptOverride: false)
        }
        let credentialRecord = try? credentialsResult.get()
        let credentials = credentialRecord?.credentials
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
                providers.append(
                    ReloadingClaudeOAuthUsageProvider(
                        initialRecord: credentialRecord,
                        env: env,
                        httpClient: URLSessionUsageHTTPClient(),
                        credentialResolver: ClaudeOAuthCredentialsStoreResolver(promptGate: promptGate)))
            case .cli:
                providers.append(ClaudeCLIUsageProvider(env: env))
            case .disabled:
                providers.append(
                    ReloadingClaudeOAuthUsageProvider(
                        initialRecord: nil,
                        env: env,
                        httpClient: URLSessionUsageHTTPClient(),
                        credentialResolver: ClaudeOAuthCredentialsStoreResolver(promptGate: promptGate)))
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
            return CascadingCodexUsageProvider(providers: [
                ReloadingClaudeOAuthUsageProvider(
                    initialRecord: nil,
                    env: env,
                    httpClient: URLSessionUsageHTTPClient(),
                    credentialResolver: ClaudeOAuthCredentialsStoreResolver(promptGate: promptGate)),
                DisabledClaudeUsageProvider(),
            ])
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
