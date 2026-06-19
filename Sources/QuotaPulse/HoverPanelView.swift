import AppKit
import QuotaPulseCore
import SwiftUI

struct HoverPanelView: View {
    @ObservedObject var codexStore: UsageStore
    @ObservedObject var claudeStore: UsageStore
    let cadence: RefreshCadence
    let isPinned: Bool
    let maxPanelHeight: CGFloat
    let onRefresh: () -> Void
    let onTogglePin: () -> Void
    let onCadenceChange: (RefreshCadence) -> Void
    let onQuit: () -> Void
    let onPreferredSizeChange: (CGSize) -> Void

    @State private var selectedTab: DashboardTab = .overview
    @State private var measuredTabBarHeight = DashboardLayout.defaultTabBarHeight
    @State private var measuredBodyHeight = DashboardLayout.defaultBodyHeight

    static var preferredContentSize: CGSize {
        self.preferredContentSize(maxHeight: DashboardLayout.defaultMaxPanelHeight)
    }

    init(
        codexStore: UsageStore,
        claudeStore: UsageStore,
        cadence: RefreshCadence,
        isPinned: Bool,
        maxPanelHeight: CGFloat = DashboardLayout.defaultMaxPanelHeight,
        onRefresh: @escaping () -> Void,
        onTogglePin: @escaping () -> Void,
        onCadenceChange: @escaping (RefreshCadence) -> Void,
        onQuit: @escaping () -> Void,
        onPreferredSizeChange: @escaping (CGSize) -> Void = { _ in })
    {
        self.codexStore = codexStore
        self.claudeStore = claudeStore
        self.cadence = cadence
        self.isPinned = isPinned
        self.maxPanelHeight = maxPanelHeight
        self.onRefresh = onRefresh
        self.onTogglePin = onTogglePin
        self.onCadenceChange = onCadenceChange
        self.onQuit = onQuit
        self.onPreferredSizeChange = onPreferredSizeChange
    }

    static func preferredContentSize(maxHeight: CGFloat) -> CGSize {
        CGSize(
            width: DashboardLayout.panelWidth,
            height: DashboardLayout.panelHeight(
                bodyHeight: DashboardLayout.defaultBodyHeight,
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

    var body: some View {
        VStack(spacing: 0) {
            self.tabBar
                .readHeight(PanelTabBarHeightPreferenceKey.self)
            Divider().overlay(Color.white.opacity(0.10))
            ScrollView(showsIndicators: self.contentRequiresScroll) {
                VStack(alignment: .leading, spacing: 10) {
                    self.content
                    self.controls
                }
                .padding(12)
                .readHeight(PanelBodyHeightPreferenceKey.self)
            }
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
        .onChange(of: self.panelHeight) { _, _ in
            self.reportPreferredSize()
        }
        .onPreferenceChange(PanelTabBarHeightPreferenceKey.self) { height in
            self.updateMeasuredHeight(&self.measuredTabBarHeight, height)
        }
        .onPreferenceChange(PanelBodyHeightPreferenceKey.self) { height in
            self.updateMeasuredHeight(&self.measuredBodyHeight, height)
        }
    }

    private var panelHeight: CGFloat {
        DashboardLayout.panelHeight(
            bodyHeight: self.measuredBodyHeight,
            tabBarHeight: self.measuredTabBarHeight,
            maxHeight: self.maxPanelHeight)
    }

    private var contentRequiresScroll: Bool {
        DashboardLayout.naturalPanelHeight(
            bodyHeight: self.measuredBodyHeight,
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
            providerSection(provider: .codex, snapshot: self.codexStore.snapshot, showExtraWindows: false)
            providerSection(provider: .claude, snapshot: self.claudeStore.snapshot, showExtraWindows: false)
        case .codex:
            providerSection(provider: .codex, snapshot: self.codexStore.snapshot, showExtraWindows: true)
        case .claude:
            providerSection(provider: .claude, snapshot: self.claudeStore.snapshot, showExtraWindows: true)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(DashboardTab.allCases) { tab in
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

    private func providerSection(
        provider: ProviderKind,
        snapshot: UsageSnapshot,
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
                    Text("Updated \(Self.timeText(snapshot.updatedAt))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer(minLength: 8)
                Text(snapshot.primaryDisplayText)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.errorMessage == nil ? .white : Color.red.opacity(0.92))
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
                stateMessage(snapshot)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(accent.opacity(0.24), lineWidth: 0.75)))
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

    private func stateMessage(_ snapshot: UsageSnapshot) -> some View {
        let message = snapshot.errorMessage ?? "Usage is stale; showing the last good reading."
        return Text(message)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(snapshot.errorMessage == nil ? Color.orange.opacity(0.92) : Color.red.opacity(0.9))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.06)))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: self.onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
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
                ForEach(RefreshCadence.allCases) { option in
                    Button(option.label) {
                        self.onCadenceChange(option)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: option == self.cadence ? .bold : .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(option == self.cadence ? Color.white.opacity(0.18) : Color.white.opacity(0.06)))
                }
                Spacer()
            }
        }
        .padding(.top, 2)
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
}

private enum DashboardLayout {
    static let panelWidth: CGFloat = 370
    static let defaultTabBarHeight: CGFloat = 45
    static let defaultBodyHeight: CGFloat = 392
    static let minPanelHeight: CGFloat = 360
    static let maxPanelHeightCap: CGFloat = 560
    static let screenMargin: CGFloat = 8

    static var defaultMaxPanelHeight: CGFloat {
        let visibleHeight = NSScreen.main?.visibleFrame.height ?? 760
        return min(self.maxPanelHeightCap, max(self.minPanelHeight, visibleHeight - 120))
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
        return min(max(self.naturalPanelHeight(bodyHeight: bodyHeight, tabBarHeight: tabBarHeight), minHeight), maxHeight)
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

private enum DashboardTab: String, CaseIterable, Identifiable {
    case overview
    case codex
    case claude

    var id: String { self.rawValue }

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
