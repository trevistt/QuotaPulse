import AppKit
import QuotaPulseCore
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let codexStore: UsageStore
    private let claudeStore: UsageStore
    private let scheduler: RefreshScheduler
    private let codexAnalyticsStore: LocalUsageAnalyticsStore
    private let claudeAnalyticsStore: LocalUsageAnalyticsStore
    private let analyticsScheduler: LocalUsageAnalyticsScheduler
    private let providerOrderStore: ProviderOrderStore
    private let onRepairClaudeLogin: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: StatusPanel?
    private let menuBarView = MenuBarMeterView()
    private let displayMode: MenuBarDisplayMode
    private var latestCodexSnapshot: UsageSnapshot
    private var latestClaudeSnapshot: UsageSnapshot
    private var cancellables: [AnyCancellable] = []
    private var hoverObserver: StatusButtonHoverObserver?
    private var closeWorkItem: DispatchWorkItem?
    private var isPinned = false
    private var isHoveringStatusItem = false
    private var isHoveringPopover = false
    private var currentPanelSize = HoverPanelView.preferredContentSize
    private var currentPanelMaxHeight = HoverPanelView.preferredContentSize.height
    private var lastValidStatusFrame: CGRect?
    private var hoverPollTimer: Timer?
    private var repositionWorkItem: DispatchWorkItem?
    private var latestStatusToolTip = ""

    init(
        codexStore: UsageStore,
        claudeStore: UsageStore,
        scheduler: RefreshScheduler,
        codexAnalyticsStore: LocalUsageAnalyticsStore,
        claudeAnalyticsStore: LocalUsageAnalyticsStore,
        analyticsScheduler: LocalUsageAnalyticsScheduler,
        providerOrderStore: ProviderOrderStore,
        onRepairClaudeLogin: @escaping () -> Void = {})
    {
        self.codexStore = codexStore
        self.claudeStore = claudeStore
        self.scheduler = scheduler
        self.codexAnalyticsStore = codexAnalyticsStore
        self.claudeAnalyticsStore = claudeAnalyticsStore
        self.analyticsScheduler = analyticsScheduler
        self.providerOrderStore = providerOrderStore
        self.onRepairClaudeLogin = onRepairClaudeLogin
        self.latestCodexSnapshot = codexStore.snapshot
        self.latestClaudeSnapshot = claudeStore.snapshot
        self.displayMode = NSStatusBar.system.thickness >= 22 ? .twoLineCustom : .compactTitle
        super.init()
        self.configureStatusItem()
        self.configurePopover()
        self.cancellables = [
            codexStore.$snapshot.sink { [weak self] snapshot in
                guard let self else { return }
                self.latestCodexSnapshot = snapshot
                self.updateTitle()
            },
            claudeStore.$snapshot.sink { [weak self] snapshot in
                guard let self else { return }
                self.latestClaudeSnapshot = snapshot
                self.updateTitle()
            },
            providerOrderStore.$providers.sink { [weak self] _ in
                self?.updateTitle()
                self?.refreshPopoverContent()
            },
        ]
        self.updateTitle()
    }

    convenience init(store: UsageStore, scheduler: RefreshScheduler) {
        self.init(
            codexStore: store,
            claudeStore: UsageStore(provider: DisabledClaudeUsageProvider()),
            scheduler: scheduler,
            codexAnalyticsStore: LocalUsageAnalyticsStore(
                providerKind: .codex,
                provider: FixtureLocalUsageAnalyticsProvider(provider: .codex, mode: .empty),
                cacheURL: Self.tempAnalyticsCacheURL("codex-disabled")),
            claudeAnalyticsStore: LocalUsageAnalyticsStore(
                providerKind: .claude,
                provider: FixtureLocalUsageAnalyticsProvider(provider: .claude, mode: .empty),
                cacheURL: Self.tempAnalyticsCacheURL("claude-disabled")),
            analyticsScheduler: LocalUsageAnalyticsScheduler(stores: []),
            providerOrderStore: ProviderOrderStore(defaults: .standard, key: "QuotaPulse.providerOrder.disabled.\(UUID().uuidString)"))
    }

    private func configureStatusItem() {
        guard let button = self.statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.image = nil
        button.title = ""

        switch self.displayMode {
        case .twoLineCustom:
            self.statusItem.length = MenuBarMeterView.widthBounds.lowerBound
            self.menuBarView.onHover = { [weak self] hovering in
                self?.statusItemHoverChanged(hovering)
            }
            button.addSubview(self.menuBarView)
            self.menuBarView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                self.menuBarView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                self.menuBarView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                self.menuBarView.topAnchor.constraint(equalTo: button.topAnchor),
                self.menuBarView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        case .compactTitle:
            self.statusItem.length = NSStatusItem.variableLength
        }

        let observer = StatusButtonHoverObserver(
            onEnter: { [weak self] in self?.statusItemHoverChanged(true) },
            onExit: { [weak self] in self?.statusItemHoverChanged(false) })
        self.hoverObserver = observer
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: observer,
            userInfo: nil)
        button.addTrackingArea(area)
        self.startHoverPolling()
    }

    private func configurePopover() {
        self.refreshPopoverContent()
    }

    private func updateTitle() {
        let lines = UsageDisplayFormatter.menuBarLines(
            codex: self.latestCodexSnapshot,
            claude: self.latestClaudeSnapshot,
            providerOrder: self.providerOrderStore.providers)
        let compactText = UsageDisplayFormatter.menuBarCompactText(
            codex: self.latestCodexSnapshot,
            claude: self.latestClaudeSnapshot,
            providerOrder: self.providerOrderStore.providers)
        let accessibilityText = UsageDisplayFormatter.menuBarAccessibilityText(
            codex: self.latestCodexSnapshot,
            claude: self.latestClaudeSnapshot,
            providerOrder: self.providerOrderStore.providers)

        switch self.displayMode {
        case .twoLineCustom:
            self.statusItem.button?.title = ""
            let metrics = self.menuBarView.update(lines: lines)
            self.statusItem.length = metrics.width
            self.redrawMenuBarButton()
        case .compactTitle:
            self.statusItem.button?.title = compactText
            self.redrawMenuBarButton()
        }
        self.latestStatusToolTip = accessibilityText
        self.statusItem.button?.toolTip = self.panel?.isVisible == true ? nil : accessibilityText
        self.statusItem.button?.setAccessibilityLabel(accessibilityText)
    }

    private func redrawMenuBarButton() {
        guard let button = self.statusItem.button else { return }
        button.needsLayout = true
        button.needsDisplay = true
        button.layoutSubtreeIfNeeded()
        button.displayIfNeeded()
    }

    private func refreshPopoverContent() {
        let size = HoverPanelView.preferredContentSize(maxHeight: self.currentPanelMaxHeight)
        self.currentPanelSize = size
        let rootView = HoverPanelView(
            codexStore: self.codexStore,
            claudeStore: self.claudeStore,
            codexAnalyticsStore: self.codexAnalyticsStore,
            claudeAnalyticsStore: self.claudeAnalyticsStore,
            scheduler: self.scheduler,
            providerOrderStore: self.providerOrderStore,
            isPinned: self.isPinned,
            maxPanelHeight: self.currentPanelMaxHeight,
            onRefresh: { [weak self] in
                self?.scheduler.refreshNow()
                self?.analyticsScheduler.refreshNow()
            },
            onRepairClaudeLogin: { [weak self] in
                self?.onRepairClaudeLogin()
            },
            onTogglePin: { [weak self] in self?.togglePinned() },
            onQuit: { NSApp.terminate(nil) },
            onPreferredSizeChange: { [weak self] preferredSize in
                self?.preferredPanelSizeChanged(preferredSize)
            })
            .onHover { [weak self] hovering in
                self?.popoverHoverChanged(hovering)
            }
        let controller = NSHostingController(rootView: rootView)
        controller.preferredContentSize = size
        let panel = self.panel ?? StatusPanel(contentRect: CGRect(origin: .zero, size: size))
        panel.contentViewController = controller
        panel.setContentSize(size)
        self.panel = panel
        self.repositionVisiblePanel(preferredSize: size)
    }

    private func preferredPanelSizeChanged(_ preferredSize: CGSize) {
        guard abs(self.currentPanelSize.width - preferredSize.width) > 0.5
            || abs(self.currentPanelSize.height - preferredSize.height) > 0.5
        else { return }

        self.currentPanelSize = preferredSize
        self.panel?.contentViewController?.preferredContentSize = preferredSize
        guard let panel = self.panel else { return }
        if panel.isVisible {
            self.repositionVisiblePanel(preferredSize: preferredSize)
            self.scheduleVisiblePanelReposition(preferredSize: preferredSize)
        } else {
            panel.setContentSize(preferredSize)
        }
    }

    private func statusItemHoverChanged(_ hovering: Bool) {
        if self.isHoveringStatusItem == hovering {
            if hovering {
                self.closeWorkItem?.cancel()
                if self.panel?.isVisible != true {
                    self.showPopover()
                }
            }
            return
        }
        self.isHoveringStatusItem = hovering
        hovering ? self.showPopover() : self.scheduleClose()
    }

    private func popoverHoverChanged(_ hovering: Bool) {
        self.isHoveringPopover = hovering
        hovering ? self.closeWorkItem?.cancel() : self.scheduleClose()
    }

    private func startHoverPolling() {
        self.hoverPollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollHoverState()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.hoverPollTimer = timer
    }

    private func pollHoverState() {
        let points = Self.mouseLocationCandidates()
        let statusContains: Bool
        if let button = self.statusItem.button {
            statusContains = self.statusHitFrames(relativeTo: button).contains {
                Self.rect($0, insetBy: CGSize(width: -8, height: -8), containsAny: points)
            }
        } else {
            statusContains = false
        }

        let panelContains: Bool
        if let panelFrame = self.panel?.frame, self.panel?.isVisible == true {
            panelContains = Self.rect(panelFrame, insetBy: CGSize(width: -8, height: -8), containsAny: points)
        } else {
            panelContains = false
        }

        if statusContains != self.isHoveringStatusItem {
            self.statusItemHoverChanged(statusContains)
        } else if statusContains {
            self.closeWorkItem?.cancel()
            if self.panel?.isVisible != true {
                self.showPopover()
            }
        }

        if panelContains != self.isHoveringPopover {
            self.popoverHoverChanged(panelContains)
        }
    }

    private func showPopover() {
        self.closeWorkItem?.cancel()
        guard let button = self.statusItem.button else { return }
        self.scheduler.setDashboardVisible(true)
        self.currentPanelMaxHeight = self.maxPanelHeight(relativeTo: button)
        self.refreshPopoverContent()
        self.statusItem.button?.toolTip = nil
        self.positionPanel(relativeTo: button)
        self.panel?.orderFrontRegardless()
        self.scheduleVisiblePanelReposition()
    }

    private func positionPanel(relativeTo button: NSStatusBarButton, preferredSize: CGSize? = nil) {
        guard let panel = self.panel,
              let window = button.window
        else { return }

        let statusFrame = self.statusFrame(relativeTo: button)
            ?? self.lastValidStatusFrame
            ?? Self.mouseFallbackStatusFrame()
        guard let statusFrame else { return }
        self.lastValidStatusFrame = statusFrame
        let preferredSize = preferredSize ?? self.currentPanelSize
        let screenFrame = Self.visibleFrame(
            containing: statusFrame,
            fallback: window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
        let frame = StatusPanelPositioner.frame(
            statusFrame: statusFrame,
            visibleFrame: screenFrame,
            preferredSize: preferredSize)
        panel.setFrame(frame, display: true)
    }

    private func repositionVisiblePanel(preferredSize: CGSize? = nil) {
        guard self.panel?.isVisible == true,
              let button = self.statusItem.button
        else { return }
        self.currentPanelMaxHeight = self.maxPanelHeight(relativeTo: button)
        self.positionPanel(relativeTo: button, preferredSize: preferredSize)
    }

    private func scheduleVisiblePanelReposition(preferredSize: CGSize? = nil) {
        self.repositionWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.repositionVisiblePanel(preferredSize: preferredSize ?? self?.currentPanelSize)
            }
        }
        self.repositionWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: item)
    }

    private func statusFrame(relativeTo button: NSStatusBarButton) -> CGRect? {
        guard let window = button.window else { return nil }
        button.needsLayout = true
        button.layoutSubtreeIfNeeded()
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return Self.isUsableStatusFrame(frame) ? frame : nil
    }

    private static func isUsableStatusFrame(_ frame: CGRect) -> Bool {
        frame.width > 1
            && frame.height > 1
            && frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.width.isFinite
            && frame.height.isFinite
    }

    private static func mouseFallbackStatusFrame() -> CGRect? {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
        guard let screen else { return nil }
        let width: CGFloat = 44
        let height: CGFloat = min(24, max(18, NSStatusBar.system.thickness))
        let clampedX = min(max(point.x - width / 2, screen.frame.minX), screen.frame.maxX - width)
        let fallbackY = min(max(point.y - height / 2, screen.frame.minY), screen.frame.maxY - height)
        return CGRect(x: clampedX, y: fallbackY, width: width, height: height)
    }

    private static func visibleFrame(containing statusFrame: CGRect, fallback: CGRect?) -> CGRect {
        let screenFrames = NSScreen.screens.map { PanelScreenFrame(frame: $0.frame, visibleFrame: $0.visibleFrame) }
        return Self.visibleFrame(containing: statusFrame, fallback: fallback, screens: screenFrames)
    }

    private static func visibleFrame(
        containing statusFrame: CGRect,
        fallback: CGRect?,
        screens: [PanelScreenFrame])
        -> CGRect
    {
        let center = CGPoint(x: statusFrame.midX, y: statusFrame.midY)
        if let screen = screens.first(where: { $0.frame.contains(center) }) {
            return screen.visibleFrame
        }
        if let screen = screens.first(where: { $0.frame.intersects(statusFrame) }) {
            return screen.visibleFrame
        }
        if let fallback {
            return fallback
        }
        return NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 760, height: 760)
    }

    private func maxPanelHeight(relativeTo button: NSStatusBarButton) -> CGFloat {
        let statusFrame = self.statusFrame(relativeTo: button)
            ?? self.lastValidStatusFrame
            ?? Self.mouseFallbackStatusFrame()
        let screenFrame: CGRect
        if let statusFrame {
            screenFrame = Self.visibleFrame(
                containing: statusFrame,
                fallback: button.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
        } else {
            screenFrame = button.window?.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? CGRect(x: 0, y: 0, width: 760, height: 760)
        }
        return HoverPanelView.maxPanelHeight(for: screenFrame)
    }

    private func visiblePanelFramePreservingTopEdge(
        currentFrame: CGRect,
        preferredSize: CGSize,
        margin: CGFloat = 8)
        -> CGRect
    {
        let visibleFrame = Self.visibleFrame(
            containing: currentFrame,
            fallback: self.statusItem.button?.window?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame)
        let availableWidth = max(1, visibleFrame.width - margin * 2)
        let availableHeight = max(1, visibleFrame.height - margin * 2)
        let width = min(preferredSize.width, availableWidth)
        let height = min(preferredSize.height, availableHeight)

        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - width - margin)
        let x = min(max(currentFrame.minX, minX), maxX)

        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - height - margin)
        let yPreservingTop = currentFrame.maxY - height
        let y = min(max(yPreservingTop, minY), maxY)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func scheduleClose() {
        guard !self.isPinned else { return }
        self.closeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.isHoveringStatusItem,
                  !self.isHoveringPopover,
                  !self.mouseIsInInteractiveRegion()
            else { return }
            self.panel?.orderOut(nil)
            self.scheduler.setDashboardVisible(false)
            self.statusItem.button?.toolTip = self.latestStatusToolTip
        }
        self.closeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func mouseIsInInteractiveRegion() -> Bool {
        let points = Self.mouseLocationCandidates()
        if let panelFrame = self.panel?.frame,
           Self.rect(panelFrame, insetBy: CGSize(width: -6, height: -6), containsAny: points)
        {
            return true
        }
        if let button = self.statusItem.button,
           self.statusHitFrames(relativeTo: button).contains(where: {
               Self.rect($0, insetBy: CGSize(width: -8, height: -8), containsAny: points)
           })
        {
            return true
        }
        return false
    }

    private func statusHitFrames(relativeTo button: NSStatusBarButton) -> [CGRect] {
        var frames: [CGRect] = []
        if let statusFrame = self.statusFrame(relativeTo: button) ?? self.lastValidStatusFrame {
            frames.append(statusFrame)
        }
        let accessibilityFrame = button.accessibilityFrame()
        if Self.isUsableStatusFrame(accessibilityFrame) {
            frames.append(accessibilityFrame)
        }
        return frames
    }

    private static func mouseLocationCandidates() -> [CGPoint] {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: 0, dy: -64).contains(point) })
            ?? NSScreen.main
        else { return [point] }
        let flippedY = screen.frame.maxY - (point.y - screen.frame.minY)
        let flippedPoint = CGPoint(x: point.x, y: flippedY)
        guard abs(flippedPoint.y - point.y) > 0.5 else { return [point] }
        return [point, flippedPoint]
    }

    private static func rect(_ rect: CGRect, insetBy inset: CGSize, containsAny points: [CGPoint]) -> Bool {
        let insetRect = rect.insetBy(dx: inset.width, dy: inset.height)
        return points.contains { insetRect.contains($0) }
    }

    private func togglePinned() {
        self.isPinned.toggle()
        self.refreshPopoverContent()
        if self.isPinned {
            self.showPopover()
        }
    }

    func titleForTesting() -> String {
        self.updateTitle()
        switch self.displayMode {
        case .twoLineCustom:
            return UsageDisplayFormatter.menuBarMultilineText(
                codex: self.latestCodexSnapshot,
                claude: self.latestClaudeSnapshot,
                providerOrder: self.providerOrderStore.providers)
        case .compactTitle:
            return self.statusItem.button?.title ?? ""
        }
    }

    func displayModeForTesting() -> String {
        self.displayMode.rawValue
    }

    func measuredStatusItemWidthForTesting() -> CGFloat {
        self.statusItem.length
    }

    func menuBarValuesForTesting() -> (codex: String, claude: String) {
        switch self.displayMode {
        case .twoLineCustom:
            return self.menuBarView.renderedValuesForTesting()
        case .compactTitle:
            let lines = UsageDisplayFormatter.menuBarLines(
                codex: self.latestCodexSnapshot,
                claude: self.latestClaudeSnapshot,
                providerOrder: self.providerOrderStore.providers)
            let codex = lines.first { $0.provider == .codex }?.value ?? "--"
            let claude = lines.first { $0.provider == .claude }?.value ?? "--"
            return (codex, claude)
        }
    }

    func currentPanelSizeForTesting() -> CGSize {
        self.currentPanelSize
    }

    func preparePopoverForTesting() -> Bool {
        self.refreshPopoverContent()
        return self.panel?.contentViewController != nil
    }

    func simulateStatusItemHoverForTesting() -> Bool {
        self.statusItemHoverChanged(true)
        return self.panel?.contentViewController != nil
    }

    func simulateClickForTesting() -> Bool {
        self.handleClick()
        return self.panel?.contentViewController != nil
    }

    func visibleToolTipForTesting() -> String? {
        self.statusItem.button?.toolTip
    }

    static func panelFrameForTesting(
        statusFrame: CGRect,
        visibleFrame: CGRect,
        preferredSize: CGSize)
        -> CGRect
    {
        StatusPanelPositioner.frame(
            statusFrame: statusFrame,
            visibleFrame: visibleFrame,
            preferredSize: preferredSize)
    }

    static func visibleFrameForTesting(
        statusFrame: CGRect,
        fallback: CGRect?,
        screens: [PanelScreenFrame])
        -> CGRect
    {
        Self.visibleFrame(containing: statusFrame, fallback: fallback, screens: screens)
    }

    static func visiblePanelFramePreservingTopEdgeForTesting(
        currentFrame: CGRect,
        visibleFrame: CGRect,
        preferredSize: CGSize,
        margin: CGFloat = 8)
        -> CGRect
    {
        let availableWidth = max(1, visibleFrame.width - margin * 2)
        let availableHeight = max(1, visibleFrame.height - margin * 2)
        let width = min(preferredSize.width, availableWidth)
        let height = min(preferredSize.height, availableHeight)

        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - width - margin)
        let x = min(max(currentFrame.minX, minX), maxX)

        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - height - margin)
        let yPreservingTop = currentFrame.maxY - height
        let y = min(max(yPreservingTop, minY), maxY)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func menuBarWidthForTesting(values: [String]) -> CGFloat {
        MenuBarMeterView.measurement(for: values).width
    }

    private static func tempAnalyticsCacheURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-pulse-status-analytics-\(name)-\(UUID().uuidString).json")
    }

    @objc
    private func handleClick() {
        self.isPinned = false
        self.isHoveringStatusItem = true
        self.showPopover()
    }
}

struct PanelScreenFrame {
    let frame: CGRect
    let visibleFrame: CGRect
}

private enum StatusPanelPositioner {
    static func frame(
        statusFrame: CGRect,
        visibleFrame: CGRect,
        preferredSize: CGSize,
        margin: CGFloat = 8)
        -> CGRect
    {
        let availableWidth = max(1, visibleFrame.width - margin * 2)
        let availableHeight = max(1, visibleFrame.height - margin * 2)
        let width = min(preferredSize.width, availableWidth)
        let height = min(preferredSize.height, availableHeight)

        let minX = visibleFrame.minX + margin
        let maxX = max(minX, visibleFrame.maxX - width - margin)
        let proposedX = statusFrame.midX - width / 2
        let x = min(max(proposedX, minX), maxX)

        let minY = visibleFrame.minY + margin
        let maxY = max(minY, visibleFrame.maxY - height - margin)
        let proposedY = statusFrame.minY - height - margin
        let y = min(max(proposedY, minY), maxY)

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private final class StatusPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        self.isFloatingPanel = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .init(Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private enum MenuBarDisplayMode: String {
    case twoLineCustom = "two-line-custom"
    case compactTitle = "compact-title"
}

private final class MenuBarMeterView: NSView {
    static let widthBounds: ClosedRange<CGFloat> = 38...48
    private static let iconWidth: CGFloat = 10.5
    private static let iconHeight: CGFloat = 10
    private static let rowSpacing: CGFloat = 2
    private static let outerPadding: CGFloat = 1
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 10.2, weight: .semibold)

    fileprivate struct Metrics {
        let width: CGFloat
        let usesUltraCompactNumbers: Bool
    }

    private let codexMark = NSImageView()
    private let codexValue = NSTextField(labelWithString: "--")
    private let claudeMark = NSImageView()
    private let claudeValue = NSTextField(labelWithString: "--")
    fileprivate var onHover: ((Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @discardableResult
    func update(lines: [UsageDisplayFormatter.ProviderLine]) -> Metrics {
        let metrics = Self.measurement(for: lines.map(\.value))
        for line in lines {
            let value = metrics.usesUltraCompactNumbers ? Self.ultraCompactValue(line.value) : line.value
            switch line.provider {
            case .codex:
                self.codexValue.stringValue = value
            case .claude:
                self.claudeValue.stringValue = value
            }
        }
        self.invalidateIntrinsicContentSize()
        self.forceRedraw()
        return metrics
    }

    func renderedValuesForTesting() -> (codex: String, claude: String) {
        (self.codexValue.stringValue, self.claudeValue.stringValue)
    }

    static func measurement(for values: [String]) -> Metrics {
        let fullWidth = self.contentWidth(for: values)
        if fullWidth <= self.widthBounds.upperBound {
            return Metrics(width: self.clampedStatusWidth(fullWidth), usesUltraCompactNumbers: false)
        }
        let compactWidth = self.contentWidth(for: values.map(Self.ultraCompactValue))
        return Metrics(width: self.clampedStatusWidth(compactWidth), usesUltraCompactNumbers: true)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.widthBounds.lowerBound, height: NSView.noIntrinsicMetric)
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            self.removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil)
        self.addTrackingArea(area)
        self.hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        self.onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        self.onHover?(false)
    }

    private func configure() {
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true

        let codexSymbol = ProviderBrandIcon.image(
            for: .codex,
            size: NSSize(width: Self.iconWidth, height: Self.iconWidth))
            ?? NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "Codex")
            ?? NSImage(systemSymbolName: "gauge.medium", accessibilityDescription: "Codex")
        self.configureSymbolView(self.codexMark, image: codexSymbol)

        let claudeSymbol = ProviderBrandIcon.image(
            for: .claude,
            size: NSSize(width: Self.iconWidth, height: Self.iconWidth))
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Claude")
            ?? NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Claude")
        self.configureSymbolView(self.claudeMark, image: claudeSymbol)

        self.configureValueLabel(self.codexValue)
        self.configureValueLabel(self.claudeValue)

        let codexRow = self.row(mark: self.codexMark, value: self.codexValue)
        let claudeRow = self.row(mark: self.claudeMark, value: self.claudeValue)
        let stack = NSStackView(views: [codexRow, claudeRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(stack)

        NSLayoutConstraint.activate([
            self.codexMark.widthAnchor.constraint(equalToConstant: Self.iconWidth),
            self.codexMark.heightAnchor.constraint(equalToConstant: Self.iconHeight),
            self.claudeMark.widthAnchor.constraint(equalToConstant: Self.iconWidth),
            self.claudeMark.heightAnchor.constraint(equalToConstant: Self.iconHeight),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: self.leadingAnchor, constant: Self.outerPadding),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: -Self.outerPadding),
            stack.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            stack.heightAnchor.constraint(lessThanOrEqualTo: self.heightAnchor),
        ])
    }

    private func row(mark: NSView, value: NSTextField) -> NSStackView {
        let row = NSStackView(views: [mark, value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Self.rowSpacing
        row.distribution = .gravityAreas
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func configureSymbolView(_ imageView: NSImageView, image: NSImage?) {
        image?.isTemplate = true
        imageView.image = image
        imageView.contentTintColor = .labelColor
        imageView.imageScaling = .scaleProportionallyDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func configureValueLabel(_ label: NSTextField) {
        label.font = Self.valueFont
        label.textColor = .labelColor
        label.lineBreakMode = .byClipping
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func forceRedraw() {
        for view in [self.codexValue, self.claudeValue, self.codexMark, self.claudeMark] {
            view.needsLayout = true
            view.needsDisplay = true
        }
        self.needsLayout = true
        self.needsDisplay = true
        self.superview?.needsLayout = true
        self.superview?.needsDisplay = true
        self.layoutSubtreeIfNeeded()
        self.displayIfNeeded()
    }

    private static func contentWidth(for values: [String]) -> CGFloat {
        let maxTextWidth = values
            .map { value in
                ceil((value as NSString).size(withAttributes: [.font: Self.valueFont]).width)
            }
            .max() ?? 0
        return Self.outerPadding * 2 + Self.iconWidth + Self.rowSpacing + maxTextWidth
    }

    private static func clampedStatusWidth(_ contentWidth: CGFloat) -> CGFloat {
        min(max(ceil(contentWidth), Self.widthBounds.lowerBound), Self.widthBounds.upperBound)
    }

    private static func ultraCompactValue(_ value: String) -> String {
        value.hasSuffix("%") ? String(value.dropLast()) : value
    }
}

private final class StatusButtonHoverObserver: NSObject {
    private let onEnter: () -> Void
    private let onExit: () -> Void

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
    }

    func mouseEntered(with event: NSEvent) {
        self.onEnter()
    }

    func mouseExited(with event: NSEvent) {
        self.onExit()
    }
}
