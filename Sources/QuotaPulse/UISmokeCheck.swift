import QuotaPulseCore
import Foundation

@MainActor
enum UISmokeCheck {
    static func run() -> Bool {
        let codexStore = UsageStore(
            provider: FixtureCodexUsageProvider(mode: .success),
            cache: UsageSnapshotCache(url: Self.tempCacheURL("codex")))
        let claudeStore = UsageStore(
            provider: FixtureClaudeUsageProvider(mode: .success),
            cache: UsageSnapshotCache(url: Self.tempCacheURL("claude")))
        let scheduler = RefreshScheduler(stores: [codexStore, claudeStore])
        let controller = StatusItemController(
            codexStore: codexStore,
            claudeStore: claudeStore,
            scheduler: scheduler)

        let semaphore = DispatchSemaphore(value: 0)
        Task { @MainActor in
            _ = await codexStore.refresh()
            _ = await claudeStore.refresh()
            semaphore.signal()
        }
        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        let display = controller.titleForTesting()
        let mode = controller.displayModeForTesting()
        guard display.contains("Cx 63%") else {
            print("UI smoke failed: expected menu bar display to contain `Cx 63%`, got `\(display)`")
            return false
        }
        guard display.contains("Cl 85%") else {
            print("UI smoke failed: expected menu bar display to contain `Cl 85%`, got `\(display)`")
            return false
        }
        let measuredWidth = controller.measuredStatusItemWidthForTesting()
        guard measuredWidth <= 48 else {
            print("UI smoke failed: expected menu bar status item width <= 48, got \(measuredWidth)")
            return false
        }
        guard !display.contains("Codex") && !display.contains("Claude") else {
            print("UI smoke failed: expected compact menu bar display without long provider names, got `\(display)`")
            return false
        }
        guard self.menuBarWidthSmokePassed() else {
            return false
        }
        guard self.menuBarSnapshotSyncSmokePassed() else {
            return false
        }
        guard controller.preparePopoverForTesting() else {
            print("UI smoke failed: hover panel content was not created")
            return false
        }
        guard controller.simulateStatusItemHoverForTesting() else {
            print("UI smoke failed: status item hover did not create dashboard panel content")
            return false
        }
        guard controller.simulateClickForTesting() else {
            print("UI smoke failed: status item click did not create dashboard panel content")
            return false
        }
        guard controller.visibleToolTipForTesting() == nil else {
            print("UI smoke failed: visible tooltip should not compete with hover dashboard")
            return false
        }
        guard ProviderBrandIcon.isAvailable(for: .codex),
              ProviderBrandIcon.isAvailable(for: .claude)
        else {
            print("UI smoke failed: expected bundled OpenAI and Claude brand icons to be available")
            return false
        }
        guard self.panelHeightSmokePassed() else {
            return false
        }
        guard self.panelPositionSmokePassed() else {
            return false
        }
        print("UI smoke passed: menu bar display mode `\(mode)`, display `\(display)`, width \(Int(measuredWidth.rounded()))pt, brand icons loaded, hover panel content created")
        return true
    }

    private static func menuBarSnapshotSyncSmokePassed() -> Bool {
        let codexStore = UsageStore(
            provider: SequencedUsageProvider(snapshots: [
                self.snapshot(sessionRemaining: 63, weeklyRemaining: 39),
                self.snapshot(sessionRemaining: 44, weeklyRemaining: 39),
            ]),
            cache: UsageSnapshotCache(url: Self.tempCacheURL("codex-sync")))
        let claudeStore = UsageStore(
            provider: SequencedUsageProvider(snapshots: [
                self.snapshot(sessionRemaining: 100, weeklyRemaining: 83),
                self.snapshot(sessionRemaining: 92, weeklyRemaining: 83),
            ]),
            cache: UsageSnapshotCache(url: Self.tempCacheURL("claude-sync")))
        let scheduler = RefreshScheduler(stores: [codexStore, claudeStore])
        let controller = StatusItemController(
            codexStore: codexStore,
            claudeStore: claudeStore,
            scheduler: scheduler)

        guard self.refreshStores([codexStore, claudeStore]) else {
            print("UI smoke failed: initial sync refresh did not complete")
            return false
        }
        guard self.waitForMenuBarValues(controller, codex: "63%", claude: "100%") else {
            let values = controller.menuBarValuesForTesting()
            print("UI smoke failed: initial rendered menu bar values were stale, got \(values), store Claude \(claudeStore.snapshot.primaryDisplayText)")
            return false
        }

        guard self.refreshStores([claudeStore]) else {
            print("UI smoke failed: Claude sync refresh did not complete")
            return false
        }
        guard self.waitForMenuBarValues(controller, codex: "63%", claude: "92%") else {
            let values = controller.menuBarValuesForTesting()
            print("UI smoke failed: rendered Claude menu bar value did not update to latest snapshot, got \(values), store Claude \(claudeStore.snapshot.primaryDisplayText)")
            return false
        }

        guard self.refreshStores([codexStore]) else {
            print("UI smoke failed: Codex sync refresh did not complete")
            return false
        }
        guard self.waitForMenuBarValues(controller, codex: "44%", claude: "92%") else {
            let values = controller.menuBarValuesForTesting()
            print("UI smoke failed: rendered Codex menu bar value did not update independently, got \(values), store Codex \(codexStore.snapshot.primaryDisplayText)")
            return false
        }

        guard controller.measuredStatusItemWidthForTesting() <= 48 else {
            print("UI smoke failed: synced menu bar width exceeded 48pt")
            return false
        }
        guard controller.visibleToolTipForTesting() == nil else {
            print("UI smoke failed: sync path restored visible tooltip")
            return false
        }
        return true
    }

    private static func menuBarWidthSmokePassed() -> Bool {
        let cases: [(String, [String])] = [
            ("zero", ["0%", "0%"]),
            ("single-digit", ["9%", "9%"]),
            ("normal", ["35%", "95%"]),
            ("hundred", ["100%", "100%"]),
            ("error", ["ERR", "95%"]),
            ("unavailable", ["--", "--"]),
            ("stale", ["35%", "ERR"]),
        ]
        for testCase in cases {
            let width = StatusItemController.menuBarWidthForTesting(values: testCase.1)
            guard width <= 48 else {
                print("UI smoke failed: menu bar width case `\(testCase.0)` measured \(width), expected <= 48")
                return false
            }
        }
        return true
    }

    private static func panelHeightSmokePassed() -> Bool {
        let overviewSize = HoverPanelView.preferredContentSizeForTesting(
            bodyHeight: 392,
            tabBarHeight: 45,
            maxHeight: 560)
        guard overviewSize.height < 500 else {
            print("UI smoke failed: overview panel height should be content-aware, got \(overviewSize.height)")
            return false
        }
        guard overviewSize.height >= 430 else {
            print("UI smoke failed: overview panel height should not clip expected controls, got \(overviewSize.height)")
            return false
        }

        let tallSize = HoverPanelView.preferredContentSizeForTesting(
            bodyHeight: 820,
            tabBarHeight: 45,
            maxHeight: 520)
        guard tallSize.height == 520 else {
            print("UI smoke failed: tall panel content should clamp to max height, got \(tallSize.height)")
            return false
        }
        return true
    }

    private static func panelPositionSmokePassed() -> Bool {
        let visibleFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let preferredSize = HoverPanelView.preferredContentSizeForTesting(
            bodyHeight: 392,
            tabBarHeight: 45,
            maxHeight: 560)
        let rightEdgeFrame = StatusItemController.panelFrameForTesting(
            statusFrame: CGRect(x: 730, y: 578, width: 54, height: 22),
            visibleFrame: visibleFrame,
            preferredSize: preferredSize)
        guard self.frame(rightEdgeFrame, fitsInside: visibleFrame) else {
            print("UI smoke failed: panel frame escaped visible screen near right edge: \(rightEdgeFrame)")
            return false
        }

        let smallVisibleFrame = CGRect(x: 0, y: 0, width: 320, height: 260)
        let smallFrame = StatusItemController.panelFrameForTesting(
            statusFrame: CGRect(x: 260, y: 238, width: 54, height: 22),
            visibleFrame: smallVisibleFrame,
            preferredSize: preferredSize)
        guard self.frame(smallFrame, fitsInside: smallVisibleFrame) else {
            print("UI smoke failed: panel frame escaped small visible screen: \(smallFrame)")
            return false
        }
        guard smallFrame.width <= smallVisibleFrame.width - 16,
              smallFrame.height <= smallVisibleFrame.height - 16
        else {
            print("UI smoke failed: panel frame did not shrink for small visible screen: \(smallFrame)")
            return false
        }
        return true
    }

    private static func frame(_ frame: CGRect, fitsInside visibleFrame: CGRect) -> Bool {
        frame.minX >= visibleFrame.minX
            && frame.maxX <= visibleFrame.maxX
            && frame.minY >= visibleFrame.minY
            && frame.maxY <= visibleFrame.maxY
    }

    private static func snapshot(sessionRemaining: Double, weeklyRemaining: Double) -> UsageSnapshot {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return UsageSnapshot(
            sessionPercentRemaining: sessionRemaining,
            weeklyPercentRemaining: weeklyRemaining,
            sessionResetAt: now.addingTimeInterval(3_600),
            weeklyResetAt: now.addingTimeInterval(86_400),
            source: .fixture,
            updatedAt: now)
    }

    private static func refreshStores(_ stores: [UsageStore]) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var passed = false
        Task { @MainActor in
            var allPassed = true
            for store in stores {
                allPassed = await store.refresh() && allPassed
            }
            passed = allPassed
            semaphore.signal()
        }
        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        return passed
    }

    private static func waitForMenuBarValues(
        _ controller: StatusItemController,
        codex: String,
        claude: String,
        timeout: TimeInterval = 1.0)
        -> Bool
    {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let values = controller.menuBarValuesForTesting()
            if values.codex == codex, values.claude == claude {
                return true
            }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        } while Date() < deadline
        return false
    }

    private static func tempCacheURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-pulse-smoke-\(name)-\(UUID().uuidString).json")
    }
}

private actor SequencedUsageProvider: CodexUsageProviding {
    private var snapshots: [UsageSnapshot]
    private var lastSnapshot: UsageSnapshot?

    init(snapshots: [UsageSnapshot]) {
        self.snapshots = snapshots
    }

    func fetchUsage() async throws -> UsageSnapshot {
        if !self.snapshots.isEmpty {
            let snapshot = self.snapshots.removeFirst()
            self.lastSnapshot = snapshot
            return snapshot
        }
        if let lastSnapshot {
            return lastSnapshot
        }
        throw CodexUsageProviderError.noUsageWindows
    }
}
