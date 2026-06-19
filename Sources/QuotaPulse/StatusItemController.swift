import AppKit
import QuotaPulseCore
import Combine
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let codexStore: UsageStore
    private let claudeStore: UsageStore
    private let scheduler: RefreshScheduler
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

    init(codexStore: UsageStore, claudeStore: UsageStore, scheduler: RefreshScheduler) {
        self.codexStore = codexStore
        self.claudeStore = claudeStore
        self.scheduler = scheduler
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
                self.refreshPopoverContent()
            },
            claudeStore.$snapshot.sink { [weak self] snapshot in
                guard let self else { return }
                self.latestClaudeSnapshot = snapshot
                self.updateTitle()
                self.refreshPopoverContent()
            },
        ]
        self.updateTitle()
    }

    convenience init(store: UsageStore, scheduler: RefreshScheduler) {
        self.init(
            codexStore: store,
            claudeStore: UsageStore(provider: DisabledClaudeUsageProvider()),
            scheduler: scheduler)
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
    }

    private func configurePopover() {
        self.refreshPopoverContent()
    }

    private func updateTitle() {
        let lines = UsageDisplayFormatter.menuBarLines(
            codex: self.latestCodexSnapshot,
            claude: self.latestClaudeSnapshot)
        let compactText = UsageDisplayFormatter.menuBarCompactText(
            codex: self.latestCodexSnapshot,
            claude: self.latestClaudeSnapshot)
        let accessibilityText = UsageDisplayFormatter.menuBarAccessibilityText(
            codex: self.latestCodexSnapshot,
            claude: self.latestClaudeSnapshot)

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
        self.statusItem.button?.toolTip = nil
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
            cadence: self.scheduler.cadence,
            isPinned: self.isPinned,
            maxPanelHeight: self.currentPanelMaxHeight,
            onRefresh: { [weak self] in self?.scheduler.refreshNow() },
            onTogglePin: { [weak self] in self?.togglePinned() },
            onCadenceChange: { [weak self] cadence in self?.setCadence(cadence) },
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
    }

    private func preferredPanelSizeChanged(_ preferredSize: CGSize) {
        guard abs(self.currentPanelSize.width - preferredSize.width) > 0.5
            || abs(self.currentPanelSize.height - preferredSize.height) > 0.5
        else { return }

        self.currentPanelSize = preferredSize
        self.panel?.contentViewController?.preferredContentSize = preferredSize
        self.panel?.setContentSize(preferredSize)
        if let button = self.statusItem.button, self.panel?.isVisible == true {
            self.positionPanel(relativeTo: button, preferredSize: preferredSize)
        }
    }

    private func statusItemHoverChanged(_ hovering: Bool) {
        self.isHoveringStatusItem = hovering
        hovering ? self.showPopover() : self.scheduleClose()
    }

    private func popoverHoverChanged(_ hovering: Bool) {
        self.isHoveringPopover = hovering
        hovering ? self.closeWorkItem?.cancel() : self.scheduleClose()
    }

    private func showPopover() {
        self.closeWorkItem?.cancel()
        guard let button = self.statusItem.button else { return }
        self.currentPanelMaxHeight = self.maxPanelHeight(relativeTo: button)
        self.refreshPopoverContent()
        self.positionPanel(relativeTo: button)
        self.panel?.orderFrontRegardless()
    }

    private func positionPanel(relativeTo button: NSStatusBarButton, preferredSize: CGSize? = nil) {
        guard let panel = self.panel,
              let window = button.window
        else { return }

        let statusFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let preferredSize = preferredSize ?? self.currentPanelSize
        let screenFrame = window.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let frame = StatusPanelPositioner.frame(
            statusFrame: statusFrame,
            visibleFrame: screenFrame,
            preferredSize: preferredSize)
        panel.setFrame(frame, display: true)
    }

    private func maxPanelHeight(relativeTo button: NSStatusBarButton) -> CGFloat {
        let screenFrame = button.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 760, height: 760)
        return HoverPanelView.maxPanelHeight(for: screenFrame)
    }

    private func scheduleClose() {
        guard !self.isPinned else { return }
        self.closeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  !self.isHoveringStatusItem,
                  !self.isHoveringPopover
            else { return }
            self.panel?.orderOut(nil)
        }
        self.closeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func togglePinned() {
        self.isPinned.toggle()
        self.refreshPopoverContent()
        if self.isPinned {
            self.showPopover()
        }
    }

    private func setCadence(_ cadence: RefreshCadence) {
        self.scheduler.setCadence(cadence)
        self.refreshPopoverContent()
    }

    func titleForTesting() -> String {
        self.updateTitle()
        switch self.displayMode {
        case .twoLineCustom:
            return UsageDisplayFormatter.menuBarMultilineText(
                codex: self.latestCodexSnapshot,
                claude: self.latestClaudeSnapshot)
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
                claude: self.latestClaudeSnapshot)
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

    static func menuBarWidthForTesting(values: [String]) -> CGFloat {
        MenuBarMeterView.measurement(for: values).width
    }

    @objc
    private func handleClick() {
        self.isPinned = false
        self.showPopover()
    }
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
