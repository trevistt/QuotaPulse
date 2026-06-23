import AppKit
import QuotaPulseCore
import SwiftUI

@MainActor
enum VisualQAFixtureRunner {
    enum Variant: Equatable {
        case standard
        case compactOverview
        case tallContent
        case constrainedHeight
        case codexAnalyticsOnly
        case claudeAnalyticsError
        case noAnalytics
        case claudeFirst
        case claudeAuthBlocked
        case claudeAuthUnavailable

        var canvasSize: CGSize {
            switch self {
            case .standard, .claudeFirst:
                CGSize(width: 760, height: 1_320)
            case .compactOverview:
                CGSize(width: 760, height: 600)
            case .tallContent:
                CGSize(width: 760, height: 1_360)
            case .constrainedHeight:
                CGSize(width: 760, height: 560)
            case .codexAnalyticsOnly, .claudeAnalyticsError, .noAnalytics, .claudeAuthBlocked, .claudeAuthUnavailable:
                CGSize(width: 760, height: 1_060)
            }
        }

        var maxPanelHeight: CGFloat? {
            switch self {
            case .standard, .claudeFirst:
                1_080
            case .compactOverview:
                520
            case .tallContent:
                1_080
            case .constrainedHeight:
                430
            case .codexAnalyticsOnly, .claudeAnalyticsError, .noAnalytics, .claudeAuthBlocked, .claudeAuthUnavailable:
                860
            }
        }

        var title: String {
            switch self {
            case .standard:
                "Comprehensive QA"
            case .compactOverview:
                "Compact Overview QA"
            case .tallContent:
                "Tall Content QA"
            case .constrainedHeight:
                "Constrained Height QA"
            case .codexAnalyticsOnly:
                "Codex Analytics Only QA"
            case .claudeAnalyticsError:
                "Claude Analytics Error QA"
            case .noAnalytics:
                "No Analytics Data QA"
            case .claudeFirst:
                "Claude First QA"
            case .claudeAuthBlocked:
                "Claude Auth Blocked QA"
            case .claudeAuthUnavailable:
                "Claude Login Unavailable QA"
            }
        }

        var providerOrder: [ProviderKind] {
            switch self {
            case .claudeFirst:
                [.claude, .codex]
            default:
                ProviderKind.defaultOrder
            }
        }

        var initialTab: DashboardTab {
            switch self {
            case .codexAnalyticsOnly:
                .codex
            case .claudeAnalyticsError, .claudeAuthBlocked, .claudeAuthUnavailable:
                .claude
            default:
                .overview
            }
        }

        var codexAnalyticsMode: FixtureLocalUsageAnalyticsProvider.Mode {
            switch self {
            case .noAnalytics:
                .empty
            default:
                .full
            }
        }

        var claudeAnalyticsMode: FixtureLocalUsageAnalyticsProvider.Mode {
            switch self {
            case .codexAnalyticsOnly, .noAnalytics:
                .empty
            case .claudeAnalyticsError:
                .error
            default:
                .full
            }
        }
    }

    static func run(outputURL: URL, variant: Variant = .standard) -> Bool {
        let codexStore = UsageStore(
            provider: FixtureCodexUsageProvider(mode: .success),
            cache: UsageSnapshotCache(url: Self.tempCacheURL("codex")))
        let claudeStore = UsageStore(
            provider: FixtureClaudeUsageProvider(mode: .success),
            cache: UsageSnapshotCache(url: Self.tempCacheURL("claude")))
        let scheduler = RefreshScheduler(stores: [codexStore, claudeStore])
        let codexAnalyticsStore = LocalUsageAnalyticsStore(
            providerKind: .codex,
            provider: FixtureLocalUsageAnalyticsProvider(provider: .codex, mode: variant.codexAnalyticsMode),
            cacheURL: Self.tempCacheURL("codex-analytics"))
        let claudeAnalyticsStore = LocalUsageAnalyticsStore(
            providerKind: .claude,
            provider: FixtureLocalUsageAnalyticsProvider(provider: .claude, mode: variant.claudeAnalyticsMode),
            cacheURL: Self.tempCacheURL("claude-analytics"))

        guard Self.refresh(
            codexStore: codexStore,
            claudeStore: claudeStore,
            codexAnalyticsStore: codexAnalyticsStore,
            claudeAnalyticsStore: claudeAnalyticsStore)
        else {
            print("Visual QA failed: fixture stores did not refresh")
            return false
        }
        Self.applyVariant(
            variant,
            codexStore: codexStore,
            claudeStore: claudeStore,
            claudeAnalyticsStore: claudeAnalyticsStore,
            scheduler: scheduler)
        let providerOrderStore = ProviderOrderStore(
            defaults: .standard,
            key: "QuotaPulse.visualQA.providerOrder.\(UUID().uuidString)")
        providerOrderStore.set(variant.providerOrder)

        let size = variant.canvasSize
        let root = VisualQAFixtureView(
            codexStore: codexStore,
            claudeStore: claudeStore,
            codexAnalyticsStore: codexAnalyticsStore,
            claudeAnalyticsStore: claudeAnalyticsStore,
            providerOrderStore: providerOrderStore,
            scheduler: scheduler,
            variant: variant)
        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            print("Visual QA failed: could not create bitmap representation")
            return false
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            print("Visual QA failed: could not create PNG data")
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try png.write(to: outputURL, options: .atomic)
            print("Visual QA screenshot written: \(outputURL.path)")
            return true
        } catch {
            print("Visual QA failed: \(UsageSnapshot.sanitized(error.localizedDescription))")
            return false
        }
    }

    private static func refresh(
        codexStore: UsageStore,
        claudeStore: UsageStore,
        codexAnalyticsStore: LocalUsageAnalyticsStore,
        claudeAnalyticsStore: LocalUsageAnalyticsStore) -> Bool
    {
        let semaphore = DispatchSemaphore(value: 0)
        var passed = false
        Task { @MainActor in
            let codexPassed = await codexStore.refresh()
            let claudePassed = await claudeStore.refresh()
            let codexAnalyticsPassed = await codexAnalyticsStore.refresh()
            let claudeAnalyticsPassed = await claudeAnalyticsStore.refresh()
            passed = codexPassed && claudePassed && codexAnalyticsPassed && claudeAnalyticsPassed
            semaphore.signal()
        }
        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return passed
    }

    private static func applyVariant(
        _ variant: Variant,
        codexStore: UsageStore,
        claudeStore: UsageStore,
        claudeAnalyticsStore: LocalUsageAnalyticsStore,
        scheduler: RefreshScheduler)
    {
        if variant == .tallContent {
            codexStore.replaceSnapshotForTesting(Self.withExtraWindows(
                codexStore.snapshot,
                provider: .codex,
                count: 6))
            claudeStore.replaceSnapshotForTesting(Self.withExtraWindows(
                claudeStore.snapshot,
                provider: .claude,
                count: 7))
        }
        if variant == .claudeAnalyticsError {
            claudeAnalyticsStore.replaceSnapshotForTesting(
                claudeAnalyticsStore.snapshot.markedStale(
                    errorMessage: "Local Claude analytics scan failed: sanitized fixture error."))
        }
        if variant == .claudeAuthBlocked {
            claudeStore.replaceSnapshotForTesting(
                UsageSnapshot(
                    sessionPercentRemaining: 89,
                    weeklyPercentRemaining: 82,
                    sessionResetAt: Date().addingTimeInterval(2_400),
                    weeklyResetAt: Date().addingTimeInterval(2 * 86_400),
                    source: .oauth,
                    updatedAt: Date().addingTimeInterval(-3_600))
                    .markedStale(errorMessage: "OAuth unauthorized; run Claude to refresh login."))
            scheduler.markClaudeAuthBlockedForTesting()
        }
        if variant == .claudeAuthUnavailable {
            claudeStore.replaceSnapshotForTesting(
                UsageSnapshot(
                    sessionPercentRemaining: nil,
                    weeklyPercentRemaining: nil,
                    sessionResetAt: nil,
                    weeklyResetAt: nil,
                    source: .oauth,
                    updatedAt: Date().addingTimeInterval(-7_200),
                    isStale: true,
                    errorMessage: "OAuth unauthorized; run Claude to refresh login."))
            scheduler.markClaudeAuthBlockedForTesting()
        }
    }

    private static func withExtraWindows(_ snapshot: UsageSnapshot, provider: ProviderKind, count: Int) -> UsageSnapshot {
        let now = Date()
        let additions: [UsageNamedWindow] = (0..<count).map { index in
            let titlePrefix = provider == .codex ? "Codex Extra" : "Claude Extra"
            let resetAt = now.addingTimeInterval(TimeInterval((index + 2) * 3_600))
            let windowSeconds = index.isMultiple(of: 2) ? 18_000 : 604_800
            let detail = index.isMultiple(of: 3) ? "Fixture extra usage" : nil
            return UsageNamedWindow(
                id: "\(provider.rawValue)-fixture-extra-\(index)",
                title: "\(titlePrefix) \(index + 1)",
                window: UsageWindow(
                    usedPercent: Double((index * 11 + 17) % 89),
                    resetAt: resetAt,
                    windowSeconds: windowSeconds),
                detail: detail)
        }
        return UsageSnapshot(
            sessionPercentRemaining: snapshot.sessionPercentRemaining,
            weeklyPercentRemaining: snapshot.weeklyPercentRemaining,
            sessionResetAt: snapshot.sessionResetAt,
            weeklyResetAt: snapshot.weeklyResetAt,
            extraWindows: snapshot.extraWindows + additions,
            source: snapshot.source,
            updatedAt: snapshot.updatedAt,
            isStale: snapshot.isStale,
            errorMessage: snapshot.errorMessage,
            rateLimitRetryAt: snapshot.rateLimitRetryAt)
    }

    private static func tempCacheURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-pulse-visual-qa-\(name)-\(UUID().uuidString).json")
    }
}

private struct VisualQAFixtureView: View {
    @ObservedObject var codexStore: UsageStore
    @ObservedObject var claudeStore: UsageStore
    @ObservedObject var codexAnalyticsStore: LocalUsageAnalyticsStore
    @ObservedObject var claudeAnalyticsStore: LocalUsageAnalyticsStore
    @ObservedObject var providerOrderStore: ProviderOrderStore
    let scheduler: RefreshScheduler
    let variant: VisualQAFixtureRunner.Variant

    var body: some View {
        VStack(spacing: 18) {
            self.previewMenuBar
            HoverPanelView(
                codexStore: self.codexStore,
                claudeStore: self.claudeStore,
                codexAnalyticsStore: self.codexAnalyticsStore,
                claudeAnalyticsStore: self.claudeAnalyticsStore,
                scheduler: self.scheduler,
                providerOrderStore: self.providerOrderStore,
                isPinned: true,
                maxPanelHeight: self.variant.maxPanelHeight ?? HoverPanelView.preferredContentSize.height,
                initialTab: self.variant.initialTab,
                onRefresh: {},
                onTogglePin: {},
                onQuit: {})
        }
        .padding(28)
        .frame(width: self.variant.canvasSize.width, height: self.variant.canvasSize.height)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.060, blue: 0.075),
                    Color(red: 0.018, green: 0.020, blue: 0.028),
                ],
                startPoint: .top,
                endPoint: .bottom))
    }

    private var previewMenuBar: some View {
        HStack {
            Text(self.variant.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            MenuBarMeterMock(
                codex: self.codexStore.snapshot,
                claude: self.claudeStore.snapshot,
                providerOrder: self.providerOrderStore.providers)
        }
        .padding(.horizontal, 18)
        .frame(width: 640, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.13, green: 0.15, blue: 0.20).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)))
    }
}

private struct MenuBarMeterMock: View {
    let codex: UsageSnapshot
    let claude: UsageSnapshot
    let providerOrder: [ProviderKind]

    var body: some View {
        let lines = UsageDisplayFormatter.menuBarLines(
            codex: self.codex,
            claude: self.claude,
            providerOrder: self.providerOrder)
        let width = StatusItemController.menuBarWidthForTesting(values: lines.map(\.value))
        VStack(alignment: .leading, spacing: 1) {
            ForEach(lines, id: \.provider) { line in
                meterRow(
                    provider: line.provider,
                    value: line.value)
            }
        }
        .frame(width: width, height: 34)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.86))
                .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.75)))
    }

    private func meterRow(provider: ProviderKind, value: String) -> some View {
        HStack(spacing: 2) {
            ProviderBrandIconView(
                provider: provider,
                size: 10.5,
                fallbackSystemImage: ProviderBrandIcon.fallbackSystemImage(for: provider))
            Text(value)
                .font(.system(size: 10.2, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(.white)
    }
}
