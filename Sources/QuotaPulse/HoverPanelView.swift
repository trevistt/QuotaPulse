import AppKit
import QuotaPulseCore
import SwiftUI

struct HoverPanelView: View {
    @ObservedObject var codexStore: UsageStore
    @ObservedObject var claudeStore: UsageStore
    @ObservedObject var codexAnalyticsStore: LocalUsageAnalyticsStore
    @ObservedObject var claudeAnalyticsStore: LocalUsageAnalyticsStore
    @ObservedObject var scheduler: RefreshScheduler
    @ObservedObject var providerOrderStore: ProviderOrderStore
    let isPinned: Bool
    let maxPanelHeight: CGFloat
    let onRefresh: () -> Void
    let onRepairClaudeLogin: () -> Void
    let onTogglePin: () -> Void
    let onQuit: () -> Void
    let onPreferredSizeChange: (CGSize) -> Void

    @State private var selectedTab: DashboardTab = .overview
    @State private var measuredTabBarHeight = DashboardLayout.defaultTabBarHeight
    @State private var measuredBodyHeight = DashboardLayout.defaultBodyHeight
    @State private var measuredControlsHeight = DashboardLayout.defaultControlsHeight
    @State private var countdownNow = Date()
    @State private var diagnosticsCopied = false

    static var preferredContentSize: CGSize {
        self.preferredContentSize(maxHeight: DashboardLayout.defaultMaxPanelHeight)
    }

    init(
        codexStore: UsageStore,
        claudeStore: UsageStore,
        codexAnalyticsStore: LocalUsageAnalyticsStore,
        claudeAnalyticsStore: LocalUsageAnalyticsStore,
        scheduler: RefreshScheduler,
        providerOrderStore: ProviderOrderStore,
        isPinned: Bool,
        maxPanelHeight: CGFloat = DashboardLayout.defaultMaxPanelHeight,
        initialTab: DashboardTab = .overview,
        onRefresh: @escaping () -> Void,
        onRepairClaudeLogin: @escaping () -> Void = {},
        onTogglePin: @escaping () -> Void,
        onQuit: @escaping () -> Void,
        onPreferredSizeChange: @escaping (CGSize) -> Void = { _ in })
    {
        self.codexStore = codexStore
        self.claudeStore = claudeStore
        self.codexAnalyticsStore = codexAnalyticsStore
        self.claudeAnalyticsStore = claudeAnalyticsStore
        self.scheduler = scheduler
        self.providerOrderStore = providerOrderStore
        self.isPinned = isPinned
        self.maxPanelHeight = maxPanelHeight
        self.onRefresh = onRefresh
        self.onRepairClaudeLogin = onRepairClaudeLogin
        self.onTogglePin = onTogglePin
        self.onQuit = onQuit
        self.onPreferredSizeChange = onPreferredSizeChange
        self._selectedTab = State(initialValue: initialTab)
    }

    static func preferredContentSize(maxHeight: CGFloat) -> CGSize {
        CGSize(
            width: DashboardLayout.panelWidth,
            height: DashboardLayout.panelHeight(
                bodyHeight: DashboardLayout.defaultBodyHeight + DashboardLayout.defaultControlsHeight + 1,
                tabBarHeight: DashboardLayout.defaultTabBarHeight,
                maxHeight: maxHeight))
    }

    static func maxPanelHeight(for visibleFrame: CGRect) -> CGFloat {
        DashboardLayout.maxPanelHeight(for: visibleFrame)
    }

    static func preferredContentSizeForTesting(
        bodyHeight: CGFloat,
        tabBarHeight: CGFloat,
        maxHeight: CGFloat)
        -> CGSize
    {
        CGSize(
            width: DashboardLayout.panelWidth,
            height: DashboardLayout.panelHeight(
                bodyHeight: bodyHeight,
                tabBarHeight: tabBarHeight,
                maxHeight: maxHeight))
    }

    static func stateMessageTextForTesting(provider: ProviderKind, snapshot: UsageSnapshot) -> String {
        self.stateMessageText(provider: provider, snapshot: snapshot)
    }

    static func refreshControlTextForTesting(isRefreshing: Bool) -> String {
        self.refreshControlText(isRefreshing: isRefreshing)
    }

    static func providerStatusTextForTesting(
        provider: ProviderKind,
        state: ProviderRefreshState,
        now: Date = Date())
        -> String
    {
        self.providerStatusText(provider: provider, state: state, now: now)
    }

    static func showsClaudeRepairActionForTesting(provider: ProviderKind, snapshot: UsageSnapshot) -> Bool {
        self.shouldShowClaudeRepairAction(provider: provider, snapshot: snapshot)
    }

    var body: some View {
        VStack(spacing: 0) {
            self.tabBar
                .readHeight(PanelTabBarHeightPreferenceKey.self)
            Divider().overlay(Color.white.opacity(0.10))
            ScrollView(showsIndicators: self.contentRequiresScroll) {
                VStack(alignment: .leading, spacing: 10) {
                    self.content
                }
                .padding(12)
                .readHeight(PanelBodyHeightPreferenceKey.self)
            }
            Divider().overlay(Color.white.opacity(0.10))
            self.controls
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .readHeight(PanelControlsHeightPreferenceKey.self)
        }
        .frame(width: DashboardLayout.panelWidth, height: self.panelHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.035, green: 0.038, blue: 0.048).opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75))
                .shadow(color: Color.black.opacity(0.45), radius: 18, y: 8))
        .foregroundStyle(.white)
        .onAppear {
            self.reportPreferredSize()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            guard self.isPinned || self.scheduler.dashboardVisible else { return }
            self.countdownNow = date
        }
        .onChange(of: self.panelHeight) { _, _ in
            self.reportPreferredSize()
        }
        .onPreferenceChange(PanelTabBarHeightPreferenceKey.self) { height in
            self.updateMeasuredHeight(&self.measuredTabBarHeight, height)
        }
        .onPreferenceChange(PanelBodyHeightPreferenceKey.self) { height in
            self.updateMeasuredHeight(&self.measuredBodyHeight, height)
        }
        .onPreferenceChange(PanelControlsHeightPreferenceKey.self) { height in
            self.updateMeasuredHeight(&self.measuredControlsHeight, height)
        }
    }

    private var panelHeight: CGFloat {
        DashboardLayout.panelHeight(
            bodyHeight: self.measuredBodyHeight + self.measuredControlsHeight + 1,
            tabBarHeight: self.measuredTabBarHeight,
            maxHeight: self.maxPanelHeight)
    }

    private var contentRequiresScroll: Bool {
        DashboardLayout.naturalPanelHeight(
            bodyHeight: self.measuredBodyHeight + self.measuredControlsHeight + 1,
            tabBarHeight: self.measuredTabBarHeight) > self.panelHeight + 1
    }

    private func updateMeasuredHeight(_ current: inout CGFloat, _ height: CGFloat) {
        guard height > 1, abs(current - height) > 0.5 else { return }
        current = height
    }

    private func reportPreferredSize() {
        self.onPreferredSizeChange(CGSize(width: DashboardLayout.panelWidth, height: self.panelHeight))
    }

    @ViewBuilder
    private var content: some View {
        switch self.selectedTab {
        case .overview:
            self.attentionRow
            ForEach(self.orderedProviders, id: \.self) { provider in
                providerOverviewSection(
                    provider: provider,
                    snapshot: self.snapshot(for: provider),
                    analytics: self.analyticsSnapshot(for: provider))
            }
            self.overviewAnalyticsSection
            self.diagnosticsSection
        case .codex:
            providerSection(
                provider: .codex,
                snapshot: self.codexStore.snapshot,
                analytics: self.codexAnalyticsStore.snapshot,
                showExtraWindows: true)
        case .claude:
            providerSection(
                provider: .claude,
                snapshot: self.claudeStore.snapshot,
                analytics: self.claudeAnalyticsStore.snapshot,
                showExtraWindows: true)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(DashboardTab.orderedTabs(providerOrder: self.orderedProviders)) { tab in
                Button {
                    self.selectedTab = tab
                } label: {
                    HStack(spacing: 5) {
                        self.tabIcon(tab)
                        Text(tab.label)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundStyle(tab == self.selectedTab ? .white : .white.opacity(0.62))
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(tab == self.selectedTab ? tab.accent.opacity(0.28) : Color.white.opacity(0.06)))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(tab == self.selectedTab ? tab.accent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func tabIcon(_ tab: DashboardTab) -> some View {
        if let provider = tab.provider {
            ProviderBrandIconView(
                provider: provider,
                size: 11,
                fallbackSystemImage: ProviderBrandIcon.fallbackSystemImage(for: provider))
        } else {
            Image(systemName: tab.systemImage)
                .font(.system(size: 10, weight: .semibold))
        }
    }

    private var attentionRow: some View {
        let snapshots = self.orderedProviders.map { ($0, self.snapshot(for: $0)) }
        let risks = snapshots.compactMap { provider, snapshot -> (ProviderKind, Double, String)? in
            guard let percent = snapshot.sessionPercentRemaining else { return nil }
            let reset = snapshot.sessionResetAt.map { "Reset \(UsageSnapshot.countdown(to: $0, now: self.countdownNow))" } ?? "Reset unknown"
            return (provider, percent, reset)
        }
        let riskiest = risks.min { lhs, rhs in lhs.1 < rhs.1 }
        return HStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.95))
            VStack(alignment: .leading, spacing: 2) {
                Text("Usage cockpit")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                if let riskiest {
                    Text("\(riskiest.0.displayName) closest to empty: \(Int(riskiest.1.rounded()))% remaining · \(riskiest.2)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                } else {
                    Text("Quota, extra windows, and estimated local log analytics.")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.75)))
    }

    private func providerOverviewSection(
        provider: ProviderKind,
        snapshot: UsageSnapshot,
        analytics: LocalUsageAnalyticsSnapshot) -> some View
    {
        let accent = Self.accent(for: provider)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                providerMark(provider, accent: accent)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(provider.displayName)
                            .font(.system(size: 13, weight: .bold))
                        sourceBadge(snapshot)
                    }
                    Text(Self.updatedText(snapshot.updatedAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer(minLength: 8)
                Text(Self.primaryDisplayText(snapshot: snapshot, now: self.countdownNow))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.primaryDisplayColor(snapshot: snapshot, now: self.countdownNow))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            progressRow(
                label: "Session",
                window: snapshot.sessionWindow(),
                remainingPercent: snapshot.sessionPercentRemaining,
                accent: accent)
            progressRow(
                label: "Weekly",
                window: snapshot.weeklyWindow(),
                remainingPercent: snapshot.weeklyPercentRemaining,
                accent: accent.opacity(0.72))

            if !snapshot.extraWindows.isEmpty {
                extraWindowsCompactList(provider: provider, windows: snapshot.extraWindows, accent: accent)
            }

            if snapshot.isStale || snapshot.errorMessage != nil {
                compactStateMessage(provider: provider, snapshot: snapshot)
            }

            if Self.shouldShowClaudeRepairAction(provider: provider, snapshot: snapshot) {
                claudeRepairAction(compact: true)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(accent.opacity(0.24), lineWidth: 0.75)))
    }

    private var overviewAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.cyan.opacity(0.92))
                Text("Local analytics")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.76))
                Text("Estimated")
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .foregroundStyle(.white.opacity(0.52))
                Spacer(minLength: 0)
            }

            ForEach(self.orderedProviders, id: \.self) { provider in
                self.overviewAnalyticsRow(
                    provider: provider,
                    analytics: self.analyticsSnapshot(for: provider))
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.75)))
    }

    private func overviewAnalyticsRow(
        provider: ProviderKind,
        analytics: LocalUsageAnalyticsSnapshot)
        -> some View
    {
        let accent = Self.accent(for: provider)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ProviderBrandIconView(
                    provider: provider,
                    size: 9.5,
                    fallbackSystemImage: ProviderBrandIcon.fallbackSystemImage(for: provider))
                    .foregroundStyle(accent)
                    .frame(width: 12)
                Text(provider.displayName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(LocalUsageAnalyticsFormatter.sourceText(analytics))
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .foregroundStyle(.white.opacity(0.52))
                Spacer(minLength: 0)
            }

            if analytics.hasAnyData {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                    ],
                    alignment: .leading,
                    spacing: 5)
                {
                    analyticsMetric(title: "Today", value: LocalUsageAnalyticsFormatter.costText(analytics.todayCostUSD))
                    analyticsMetric(title: "30d", value: LocalUsageAnalyticsFormatter.costText(analytics.last30DaysCostUSD))
                    analyticsMetric(title: "Today tokens", value: LocalUsageAnalyticsFormatter.tokenText(analytics.todayTokens))
                    analyticsMetric(title: "30d tokens", value: LocalUsageAnalyticsFormatter.tokenText(analytics.last30DaysTokens))
                    analyticsMetric(title: "Latest", value: LocalUsageAnalyticsFormatter.tokenText(analytics.latestTokens))
                    analyticsMetric(title: "Top model", value: analytics.topModel ?? "unknown")
                }
                overviewAnalyticsHistogram(snapshot: analytics, accent: accent)
            } else {
                Text(analytics.errorMessage ?? "No local analytics data found.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accent.opacity(0.16), lineWidth: 0.75)))
    }

    private func overviewAnalyticsHistogram(snapshot: LocalUsageAnalyticsSnapshot, accent: Color) -> some View {
        let buckets = snapshot.dailyHistory.suffix(14)
        let maxTokens = max(1, buckets.map(\.totalTokens).max() ?? 1)
        return HStack(alignment: .center, spacing: 6) {
            Text("14d")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.40))
                .frame(width: 24, alignment: .leading)
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                    RoundedRectangle(cornerRadius: 1.25, style: .continuous)
                        .fill(bucket.totalTokens > 0 ? accent.opacity(0.72) : Color.white.opacity(0.08))
                        .frame(
                            width: 5,
                            height: max(3, CGFloat(bucket.totalTokens) / CGFloat(maxTokens) * 20))
                        .accessibilityLabel("\(bucket.date) \(bucket.totalTokens) tokens")
                }
                Spacer(minLength: 0)
            }
            .frame(height: 22, alignment: .bottomLeading)
        }
        .padding(.top, 1)
        .accessibilityLabel("\(snapshot.provider.displayName) 14 day local analytics histogram")
    }

    private func providerSection(
        provider: ProviderKind,
        snapshot: UsageSnapshot,
        analytics: LocalUsageAnalyticsSnapshot,
        showExtraWindows: Bool) -> some View
    {
        let accent = Self.accent(for: provider)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                providerMark(provider, accent: accent)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(provider.displayName)
                            .font(.system(size: 13, weight: .bold))
                        sourceBadge(snapshot)
                    }
                    Text(Self.updatedText(snapshot.updatedAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer(minLength: 8)
                Text(Self.primaryDisplayText(snapshot: snapshot, now: self.countdownNow))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.primaryDisplayColor(snapshot: snapshot, now: self.countdownNow))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            progressRow(
                label: "Session",
                window: snapshot.sessionWindow(),
                remainingPercent: snapshot.sessionPercentRemaining,
                accent: accent)
            progressRow(
                label: "Weekly",
                window: snapshot.weeklyWindow(),
                remainingPercent: snapshot.weeklyPercentRemaining,
                accent: accent.opacity(0.72))

            if showExtraWindows, !snapshot.extraWindows.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Extra windows")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.48))
                    ForEach(snapshot.extraWindows) { extraWindow in
                        progressRow(
                            label: extraWindow.title,
                            window: extraWindow.window,
                            remainingPercent: extraWindow.window.remainingPercent,
                            accent: accent.opacity(0.56),
                            detail: extraWindow.detail)
                    }
                }
                .padding(.top, 2)
            }

            if snapshot.isStale || snapshot.errorMessage != nil {
                stateMessage(provider: provider, snapshot: snapshot)
            }

            if Self.shouldShowClaudeRepairAction(provider: provider, snapshot: snapshot) {
                claudeRepairAction(compact: false)
            }

            analyticsSummarySection(provider: provider, snapshot: analytics, accent: accent, compact: false)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(accent.opacity(0.24), lineWidth: 0.75)))
    }

    private func extraWindowsCompactList(
        provider: ProviderKind,
        windows: [UsageNamedWindow],
        accent: Color)
        -> some View
    {
        VStack(alignment: .leading, spacing: 5) {
            Text("Extra windows")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(.white.opacity(0.48))
            ForEach(windows.prefix(4)) { extraWindow in
                HStack(spacing: 7) {
                    ProviderBrandIconView(
                        provider: provider,
                        size: 8.5,
                        fallbackSystemImage: ProviderBrandIcon.fallbackSystemImage(for: provider))
                        .foregroundStyle(accent)
                        .frame(width: 10)
                    Text(extraWindow.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Self.percentText(extraWindow.window.remainingPercent))
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.82))
                    if let resetAt = extraWindow.window.resetAt {
                        Text(UsageSnapshot.countdown(to: resetAt, now: self.countdownNow))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.46))
                    }
                }
                ProgressBar(
                    fraction: UsageDisplayFormatter.progressFraction(forRemainingPercent: extraWindow.window.remainingPercent),
                    targetFraction: nil,
                    accent: accent.opacity(0.50))
                    .frame(height: 4)
            }
            if windows.count > 4 {
                Text("+\(windows.count - 4) more in provider tab")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
            }
        }
        .padding(.top, 2)
    }

    private func analyticsSummarySection(
        provider: ProviderKind,
        snapshot: LocalUsageAnalyticsSnapshot,
        accent: Color,
        compact: Bool)
        -> some View
    {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(accent)
                Text("Local analytics")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.74))
                Text(LocalUsageAnalyticsFormatter.sourceText(snapshot))
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(snapshot.isStale ? Color.orange.opacity(0.20) : Color.white.opacity(0.08)))
                    .foregroundStyle(snapshot.isStale ? Color.orange.opacity(0.92) : .white.opacity(0.58))
                Spacer(minLength: 0)
            }

            if snapshot.hasAnyData {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6),
                    ],
                    alignment: .leading,
                    spacing: 6)
                {
                    analyticsMetric(title: "Today", value: LocalUsageAnalyticsFormatter.costText(snapshot.todayCostUSD))
                    analyticsMetric(title: "30d", value: LocalUsageAnalyticsFormatter.costText(snapshot.last30DaysCostUSD))
                    analyticsMetric(title: "Tokens", value: LocalUsageAnalyticsFormatter.tokenText(snapshot.todayTokens))
                    analyticsMetric(title: "30d tokens", value: LocalUsageAnalyticsFormatter.tokenText(snapshot.last30DaysTokens))
                    analyticsMetric(title: "Latest", value: LocalUsageAnalyticsFormatter.tokenText(snapshot.latestTokens))
                    analyticsMetric(title: "Top model", value: snapshot.topModel ?? "unknown")
                }
                analyticsHistogram(snapshot: snapshot, accent: accent)
                Text(snapshot.estimateNote)
                    .font(.system(size: compact ? 8.4 : 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(0.78)
            } else {
                Text(snapshot.errorMessage ?? "No local analytics data found.")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.56))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message = snapshot.errorMessage, snapshot.hasAnyData {
                Text(message)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(snapshot.isStale ? Color.orange.opacity(0.9) : Color.red.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.040))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.075), lineWidth: 0.75)))
        .accessibilityLabel("\(provider.displayName) local analytics, estimated from local logs")
    }

    private func analyticsMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func analyticsHistogram(snapshot: LocalUsageAnalyticsSnapshot, accent: Color) -> some View {
        let buckets = snapshot.dailyHistory.suffix(14)
        let maxTokens = max(1, buckets.map(\.totalTokens).max() ?? 1)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(bucket.totalTokens > 0 ? accent.opacity(0.74) : Color.white.opacity(0.08))
                    .frame(
                        width: 6,
                        height: max(3, CGFloat(bucket.totalTokens) / CGFloat(maxTokens) * 28))
                    .accessibilityLabel("\(bucket.date) \(bucket.totalTokens) tokens")
            }
            Spacer(minLength: 0)
        }
        .frame(height: 30, alignment: .bottomLeading)
    }

    private func providerMark(_ provider: ProviderKind, accent: Color) -> some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.22))
            ProviderBrandIconView(
                provider: provider,
                size: 13,
                fallbackSystemImage: ProviderBrandIcon.fallbackSystemImage(for: provider))
        }
        .foregroundStyle(accent)
        .frame(width: 24, height: 24)
    }

    private func compactProgressRow(
        label: String,
        window: UsageWindow?,
        remainingPercent: Double?,
        accent: Color)
        -> some View
    {
        let pace = window.flatMap { UsagePace(window: $0) }
        let targetFraction = pace.map { $0.targetRemainingPercent / 100 }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.60))
                Spacer()
                if let pace {
                    Text(UsagePaceFormatter.balanceText(pace))
                        .font(.system(size: 9.2, weight: .semibold))
                        .foregroundStyle(Self.paceColor(pace))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Text(Self.percentText(remainingPercent))
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.86))
            }
            ProgressBar(
                fraction: UsageDisplayFormatter.progressFraction(forRemainingPercent: remainingPercent),
                targetFraction: targetFraction,
                accent: accent)
                .frame(height: 5)
        }
    }

    private func progressRow(
        label: String,
        window: UsageWindow?,
        remainingPercent: Double?,
        accent: Color,
        detail: String? = nil) -> some View
    {
        let pace = window.flatMap { UsagePace(window: $0) }
        let targetFraction = pace.map { $0.targetRemainingPercent / 100 }
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.60))
                Spacer()
                Text(Self.percentText(remainingPercent))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.86))
            }
            ProgressBar(
                fraction: UsageDisplayFormatter.progressFraction(forRemainingPercent: remainingPercent),
                targetFraction: targetFraction,
                accent: accent)
                .frame(height: 6)

            if let pace {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(UsagePaceFormatter.balanceText(pace))
                            .foregroundStyle(Self.paceColor(pace))
                        Text(UsagePaceFormatter.expectedUsedText(pace))
                            .foregroundStyle(.white.opacity(0.54))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                    HStack(spacing: 4) {
                        Image(systemName: pace.lastsUntilReset ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.system(size: 9, weight: .semibold))
                        Text(UsagePaceFormatter.projectionText(pace))
                        if let resetAt = window?.resetAt {
                            Text("Reset \(UsageSnapshot.countdown(to: resetAt))")
                                .foregroundStyle(.white.opacity(0.46))
                        }
                    }
                    .foregroundStyle(pace.lastsUntilReset ? .white.opacity(0.58) : Color.orange.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                }
                .font(.system(size: 9.5, weight: .medium))
            } else if let detail {
                Text(detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.54))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
    }

    private func sourceBadge(_ snapshot: UsageSnapshot) -> some View {
        Text(snapshot.sourceLabel)
            .font(.system(size: 9, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(snapshot.isStale ? Color.orange.opacity(0.24) : Color.white.opacity(0.09)))
            .foregroundStyle(snapshot.isStale ? Color.orange.opacity(0.95) : .white.opacity(0.70))
    }

    private func stateMessage(provider: ProviderKind, snapshot: UsageSnapshot) -> some View {
        let message = Self.stateMessageText(provider: provider, snapshot: snapshot)
        return Text(message)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Self.stateMessageColor(snapshot: snapshot))
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.06)))
    }

    private func compactStateMessage(provider: ProviderKind, snapshot: UsageSnapshot) -> some View {
        HStack(spacing: 5) {
            Image(systemName: snapshot.hasRateLimitError ? "clock" : (snapshot.hasAuthFailureError ? "person.crop.circle.badge.exclamationmark" : "exclamationmark.triangle"))
                .font(.system(size: 8.5, weight: .semibold))
            Text(Self.compactStateMessageText(provider: provider, snapshot: snapshot))
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(snapshot.errorMessage == nil ? Color.orange.opacity(0.92) : Color.red.opacity(0.9))
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.055)))
    }

    private static func compactStateMessageText(provider: ProviderKind, snapshot: UsageSnapshot) -> String {
        if snapshot.hasRateLimitError {
            return "Cached value; wait for cooldown."
        }
        if provider == .claude, snapshot.hasStaleAuthFailure {
            if snapshot.sessionPercentRemaining != nil {
                return "Login needs repair; showing cached quota."
            }
            return "Login needs repair."
        }
        if provider == .claude,
           snapshot.source == .disabled || UsageDiagnosticsFormatter.errorCategory(snapshot.errorMessage) == "Credentials unavailable"
        {
            return "Safe startup: Claude login not checked."
        }
        if snapshot.isStale {
            return "! means cached value."
        }
        return snapshot.errorMessage ?? "Usage unavailable."
    }

    private static func stateMessageText(provider: ProviderKind, snapshot: UsageSnapshot) -> String {
        if provider == .claude, snapshot.hasStaleAuthFailure {
            let firstLine = snapshot.sessionPercentRemaining == nil
                ? "Claude login needs repair. Quota is unavailable until repaired."
                : "Claude login needs repair. Showing last good quota."
            return "\(firstLine)\nClick Fix Claude Login while you are at this Mac.\nIf it stays blocked: open Claude Code, run /logout, then /login, return here, and press Refresh."
        }
        if provider == .claude,
           snapshot.source == .disabled || UsageDiagnosticsFormatter.errorCategory(snapshot.errorMessage) == "Credentials unavailable"
        {
            return "Safe startup did not check Claude login. Click Fix Claude Login only while you are at this Mac. Claude CLI remains off."
        }
        let message = snapshot.errorMessage ?? "Usage is stale; showing the last good reading."
        if snapshot.isStale,
           snapshot.hasRateLimitError,
           snapshot.hasUsableCachedSessionPercent()
        {
            return "\(message) ! means stale cached value."
        }
        return message
    }

    private static func stateMessageColor(snapshot: UsageSnapshot) -> Color {
        if snapshot.hasAuthFailureError || snapshot.hasRateLimitError || snapshot.isStale {
            return Color.orange.opacity(0.92)
        }
        return snapshot.errorMessage == nil ? Color.orange.opacity(0.92) : Color.red.opacity(0.9)
    }

    private static func shouldShowClaudeRepairAction(provider: ProviderKind, snapshot: UsageSnapshot) -> Bool {
        guard provider == .claude else { return false }
        return snapshot.hasAuthFailureError
            || snapshot.source == .disabled
            || UsageDiagnosticsFormatter.errorCategory(snapshot.errorMessage) == "Credentials unavailable"
    }

    private func claudeRepairAction(compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: compact ? 9 : 11, weight: .semibold))
                .foregroundStyle(Color.orange.opacity(0.95))
                .frame(width: compact ? 12 : 15)
            VStack(alignment: .leading, spacing: 2) {
                Text("Attended only. This may show a macOS Keychain prompt.")
                    .font(.system(size: compact ? 8.8 : 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(compact ? 1 : 2)
                    .minimumScaleFactor(0.76)
                if !compact {
                    Text("If repair still fails: open Claude Code, run /logout, then /login, return here, and press Refresh.")
                        .font(.system(size: 8.8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            Button {
                self.onRepairClaudeLogin()
            } label: {
                Label("Fix Claude Login...", systemImage: "wrench.and.screwdriver")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: compact ? 9 : 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.18))
                    .overlay(Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 0.75)))
            .foregroundStyle(Color.orange.opacity(0.96))
            .accessibilityLabel("Fix Claude Login")
            .accessibilityHint("Only use while you are at this Mac. This may show a macOS Keychain prompt.")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.orange.opacity(0.20), lineWidth: 0.75)))
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.95))
                Text("Status / Diagnostics")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.76))
                Spacer(minLength: 0)
                Button {
                    self.copyDiagnosticsToClipboard()
                } label: {
                    Label(self.diagnosticsCopied ? "Copied" : "Copy", systemImage: self.diagnosticsCopied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(self.diagnosticsCopied ? Color.green.opacity(0.92) : .white.opacity(0.68))
            }

            ForEach(self.orderedProviders, id: \.self) { provider in
                self.diagnosticProviderRow(state: self.diagnosticsState(for: provider))
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.75)))
    }

    private func diagnosticProviderRow(state: UsageDiagnosticsProviderState) -> some View {
        let accent = Self.accent(for: state.provider)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ProviderBrandIconView(
                    provider: state.provider,
                    size: 9.5,
                    fallbackSystemImage: ProviderBrandIcon.fallbackSystemImage(for: state.provider))
                    .foregroundStyle(accent)
                    .frame(width: 12)
                Text(state.provider.displayName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.76))
                Text(UsageDiagnosticsFormatter.credentialMode(provider: state.provider, snapshot: state.snapshot))
                    .font(.system(size: 8.5, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .foregroundStyle(.white.opacity(0.54))
                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 7),
                    GridItem(.flexible(), spacing: 7),
                ],
                alignment: .leading,
                spacing: 5)
            {
                diagnosticPair(
                    title: "Last success",
                    value: UsageDiagnosticsFormatter.lastSuccessfulText(state.lastSuccessfulRefreshAt, now: self.countdownNow))
                diagnosticPair(
                    title: "Last error",
                    value: UsageDiagnosticsFormatter.errorCategory(
                        provider: state.provider,
                        snapshot: state.snapshot,
                        lastErrorMessage: state.lastErrorMessage))
                diagnosticPair(
                    title: "Refresh",
                    value: "\(state.refreshState.mode.label) · \(UsageDiagnosticsFormatter.refreshText(state: state.refreshState, now: self.countdownNow))")
                diagnosticPair(
                    title: "Local logs",
                    value: UsageDiagnosticsFormatter.analyticsStatusText(
                        state.analytics,
                        lastSuccessfulRefreshAt: state.analyticsLastSuccessfulRefreshAt,
                        lastErrorMessage: state.analyticsLastErrorMessage,
                        now: self.countdownNow))
            }

            Text(UsageDiagnosticsFormatter.nextAction(provider: state.provider, snapshot: state.snapshot))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(accent.opacity(0.16), lineWidth: 0.75)))
    }

    private func diagnosticPair(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8.4, weight: .medium))
                .foregroundStyle(.white.opacity(0.40))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 9.3, weight: .semibold))
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diagnosticsState(for provider: ProviderKind) -> UsageDiagnosticsProviderState {
        switch provider {
        case .codex:
            UsageDiagnosticsProviderState(
                provider: provider,
                lastSuccessfulRefreshAt: self.codexStore.lastSuccessfulRefreshAt,
                lastErrorMessage: self.codexStore.lastErrorMessage,
                snapshot: self.codexStore.snapshot,
                refreshState: self.scheduler.state(for: provider),
                analytics: self.codexAnalyticsStore.snapshot,
                analyticsLastSuccessfulRefreshAt: self.codexAnalyticsStore.lastSuccessfulRefreshAt,
                analyticsLastErrorMessage: self.codexAnalyticsStore.lastErrorMessage)
        case .claude:
            UsageDiagnosticsProviderState(
                provider: provider,
                lastSuccessfulRefreshAt: self.claudeStore.lastSuccessfulRefreshAt,
                lastErrorMessage: self.claudeStore.lastErrorMessage,
                snapshot: self.claudeStore.snapshot,
                refreshState: self.scheduler.state(for: provider),
                analytics: self.claudeAnalyticsStore.snapshot,
                analyticsLastSuccessfulRefreshAt: self.claudeAnalyticsStore.lastSuccessfulRefreshAt,
                analyticsLastErrorMessage: self.claudeAnalyticsStore.lastErrorMessage)
        }
    }

    private func diagnosticsText(now: Date = Date()) -> String {
        UsageDiagnosticsFormatter.safeExport(
            states: self.orderedProviders.map { self.diagnosticsState(for: $0) },
            providerOrder: self.orderedProviders,
            now: now)
    }

    private func copyDiagnosticsToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(self.diagnosticsText(now: self.countdownNow), forType: .string)
        self.diagnosticsCopied = true
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: self.onRefresh) {
                    Label {
                        Text(Self.refreshControlText(isRefreshing: self.isRefreshing))
                    } icon: {
                        if self.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.58)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
                .disabled(self.isRefreshing)
                Button(action: self.onTogglePin) {
                    Label(self.isPinned ? "Unpin" : "Pin", systemImage: self.isPinned ? "pin.slash" : "pin")
                }
                Spacer()
                Button(action: self.onQuit) {
                    Label("Quit", systemImage: "power")
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .semibold))

            HStack(spacing: 6) {
                Text(self.schedulerSummaryText(now: self.countdownNow))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
            }

            self.providerOrderControls
            ForEach(self.orderedProviders, id: \.self) { provider in
                self.smartRefreshRow(provider: provider)
            }
        }
        .padding(.top, 2)
    }

    private var providerOrderControls: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.52))
                .frame(width: 12)
            Text("First")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.64))
                .frame(width: 38, alignment: .leading)
            ForEach(Array(self.orderedProviders.enumerated()), id: \.element) { index, provider in
                self.providerOrderChip(provider: provider, index: index)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 24)
    }

    private func providerOrderChip(provider: ProviderKind, index: Int) -> some View {
        let isFirst = index == 0
        return Button {
            guard !isFirst else { return }
            self.providerOrderStore.set([provider] + self.orderedProviders.filter { $0 != provider })
        } label: {
            HStack(spacing: 4) {
                ProviderBrandIconView(
                    provider: provider,
                    size: 8.5,
                    fallbackSystemImage: ProviderBrandIcon.fallbackSystemImage(for: provider))
                    .foregroundStyle(Self.accent(for: provider))
                    .frame(width: 10)
                Text(provider.compactName)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                Image(systemName: isFirst ? "checkmark" : "arrow.up")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isFirst ? Color.green.opacity(0.88) : .white.opacity(0.58))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isFirst ? Color.white.opacity(0.11) : Color.white.opacity(0.075)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFirst ? "\(provider.displayName) is first" : "Show \(provider.displayName) first")
        .accessibilityHint("Changes the menu bar, tabs, and overview order")
    }

    private func smartRefreshRow(provider: ProviderKind) -> some View {
        let state = self.scheduler.state(for: provider)
        return HStack(spacing: 6) {
            ProviderBrandIconView(
                provider: provider,
                size: 10,
                fallbackSystemImage: ProviderBrandIcon.fallbackSystemImage(for: provider))
                .foregroundStyle(Self.accent(for: provider))
                .frame(width: 12)
            Text(provider.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 38, alignment: .leading)
            Menu {
                ForEach(RefreshMode.allowedModes(for: provider)) { mode in
                    Button {
                        self.scheduler.setMode(mode, for: provider)
                    } label: {
                        if mode == state.mode {
                            Label(mode.label, systemImage: "checkmark")
                        } else {
                            Text(mode.label)
                        }
                    }
                }
            } label: {
                Text(state.mode.label)
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.10)))
                    .foregroundStyle(.white.opacity(0.86))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            Spacer(minLength: 4)
            Text(Self.providerStatusText(provider: provider, state: state, now: self.countdownNow))
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(height: 22)
    }

    private func schedulerSummaryText(now: Date) -> String {
        if let paused = self.scheduler.presence.pausedText {
            return paused
        }
        return self.orderedProviders.map { provider in
            "\(provider.displayName) \(Self.providerStatusText(provider: provider, state: self.scheduler.state(for: provider), now: now))"
        }.joined(separator: " · ")
    }

    private var orderedProviders: [ProviderKind] {
        ProviderKind.normalizedOrder(self.providerOrderStore.providers)
    }

    private func snapshot(for provider: ProviderKind) -> UsageSnapshot {
        switch provider {
        case .codex:
            self.codexStore.snapshot
        case .claude:
            self.claudeStore.snapshot
        }
    }

    private func analyticsSnapshot(for provider: ProviderKind) -> LocalUsageAnalyticsSnapshot {
        switch provider {
        case .codex:
            self.codexAnalyticsStore.snapshot
        case .claude:
            self.claudeAnalyticsStore.snapshot
        }
    }

    private static func providerStatusText(
        provider: ProviderKind,
        state: ProviderRefreshState,
        now: Date = Date())
        -> String
    {
        if state.isRefreshing { return "Refreshing..." }
        if let paused = state.pausedReason?.pausedText {
            return paused.replacingOccurrences(of: "Paused: ", with: "Paused ")
        }
        if state.authBlockedReason != nil {
            if let next = state.nextRefreshAt, next > now {
                return "Auto retry \(Self.timeText(next)) · \(RefreshScheduler.refreshCountdown(to: next, now: now))"
            }
            return "Login repair needed"
        }
        if provider == .claude,
           let cooldown = state.cooldownUntil,
           cooldown > now
        {
            return "Cooldown until \(Self.timeText(cooldown)) · \(RefreshScheduler.refreshCountdown(to: cooldown, now: now))"
        }
        if state.mode == .manual { return "Manual" }
        if let next = state.nextRefreshAt {
            return "Next \(Self.timeText(next)) · \(RefreshScheduler.refreshCountdown(to: next, now: now))"
        }
        return state.lastStatusText
    }

    private var isRefreshing: Bool {
        self.codexStore.isRefreshing
            || self.claudeStore.isRefreshing
    }

    private static func accent(for provider: ProviderKind) -> Color {
        switch provider {
        case .codex:
            Color(red: 0.22, green: 0.82, blue: 0.90)
        case .claude:
            Color(red: 1.00, green: 0.55, blue: 0.25)
        }
    }

    private static func paceColor(_ pace: UsagePace) -> Color {
        switch pace.balance {
        case .reserve:
            Color.green.opacity(0.9)
        case .deficit:
            Color.orange.opacity(0.95)
        case .onTarget:
            .white.opacity(0.62)
        }
    }

    private static func primaryDisplayText(snapshot: UsageSnapshot, now: Date) -> String {
        if snapshot.hasStaleAuthFailure,
           let value = snapshot.sessionPercentRemaining,
           snapshot.hasUsableCachedSessionPercent(now: now)
        {
            return "\(Int(value.rounded()))% cached"
        }
        if snapshot.hasAuthFailureError,
           snapshot.sessionPercentRemaining == nil
        {
            return "Login needed"
        }
        return snapshot.primaryDisplayText
    }

    private static func primaryDisplayColor(snapshot: UsageSnapshot, now: Date) -> Color {
        if snapshot.hasStaleAuthFailure,
           snapshot.hasUsableCachedSessionPercent(now: now)
        {
            return Color.orange.opacity(0.95)
        }
        if snapshot.errorMessage == nil {
            return .white
        }
        if snapshot.hasAuthFailureError {
            return Color.orange.opacity(0.95)
        }
        return Color.red.opacity(0.92)
    }

    private static func percentText(_ value: Double?) -> String {
        guard let value else { return "unavailable" }
        return "\(Int(value.rounded()))%"
    }

    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func updatedText(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 {
            return "Updated just now"
        }
        return "Updated \(Self.timeText(date))"
    }

    private static func refreshControlText(isRefreshing: Bool) -> String {
        isRefreshing ? "Refreshing..." : "Refresh"
    }
}

private enum DashboardLayout {
    static let panelWidth: CGFloat = 370
    static let defaultTabBarHeight: CGFloat = 45
    static let defaultBodyHeight: CGFloat = 620
    static let defaultControlsHeight: CGFloat = 132
    static let minPanelHeight: CGFloat = 680
    static let stablePanelHeight: CGFloat = 980
    static let maxPanelHeightCap: CGFloat = 1080
    static let screenMargin: CGFloat = 8

    static var defaultMaxPanelHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 760
        return min(self.maxPanelHeightCap, max(self.minPanelHeight, visibleHeight - self.screenMargin * 2))
    }

    static func maxPanelHeight(for visibleFrame: CGRect) -> CGFloat {
        let availableHeight = max(1, visibleFrame.height - self.screenMargin * 2)
        return min(self.maxPanelHeightCap, availableHeight)
    }

    static func naturalPanelHeight(bodyHeight: CGFloat, tabBarHeight: CGFloat) -> CGFloat {
        ceil(tabBarHeight + 1 + bodyHeight)
    }

    static func panelHeight(bodyHeight: CGFloat, tabBarHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        let maxHeight = max(1, maxHeight)
        let minHeight = min(self.minPanelHeight, maxHeight)
        let stableHeight = min(self.stablePanelHeight, maxHeight)
        let naturalHeight = min(self.naturalPanelHeight(bodyHeight: bodyHeight, tabBarHeight: tabBarHeight), maxHeight)
        return max(minHeight, max(stableHeight, naturalHeight))
    }
}

private protocol PanelHeightPreferenceKey: PreferenceKey where Value == CGFloat {}

private struct PanelTabBarHeightPreferenceKey: PanelHeightPreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PanelBodyHeightPreferenceKey: PanelHeightPreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PanelControlsHeightPreferenceKey: PanelHeightPreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func readHeight<Key: PanelHeightPreferenceKey>(_ key: Key.Type) -> some View {
        self.background(
            GeometryReader { proxy in
                Color.clear.preference(key: key, value: proxy.size.height)
            })
    }
}

private struct ProgressBar: View {
    let fraction: Double?
    let targetFraction: Double?
    let accent: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                if let fraction {
                    Capsule()
                        .fill(self.accent)
                        .frame(width: max(3, width * fraction))
                }
                if let targetFraction {
                    Rectangle()
                        .fill(Color.white.opacity(0.82))
                        .frame(width: 1.25)
                        .offset(x: min(max(0, width * targetFraction), width - 1.25))
                }
            }
        }
        .accessibilityLabel(self.fraction == nil ? "Unavailable" : "\(Int((self.fraction ?? 0) * 100)) percent")
    }
}

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case codex
    case claude

    var id: String { self.rawValue }

    static func orderedTabs(providerOrder: [ProviderKind]) -> [DashboardTab] {
        [.overview] + ProviderKind.normalizedOrder(providerOrder).map { provider in
            switch provider {
            case .codex:
                .codex
            case .claude:
                .claude
            }
        }
    }

    var label: String {
        switch self {
        case .overview:
            "Overview"
        case .codex:
            "Codex"
        case .claude:
            "Claude"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "square.grid.2x2"
        case .codex:
            "gauge.with.dots.needle.50percent"
        case .claude:
            "sparkles"
        }
    }

    var provider: ProviderKind? {
        switch self {
        case .overview:
            nil
        case .codex:
            .codex
        case .claude:
            .claude
        }
    }

    var accent: Color {
        switch self {
        case .overview:
            Color.orange
        case .codex:
            Color(red: 0.22, green: 0.82, blue: 0.90)
        case .claude:
            Color(red: 1.00, green: 0.55, blue: 0.25)
        }
    }
}
