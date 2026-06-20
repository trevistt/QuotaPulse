import AppKit
import QuotaPulseCore
import SwiftUI

@MainActor
final class NotchPillController {
    private let codexStore: UsageStore
    private let claudeStore: UsageStore
    private let scheduler: RefreshScheduler
    private var pillPanel: NSPanel?
    private var detailPanel: NSPanel?
    private var isPinned = false
    private var isHoveringPill = false
    private var isHoveringDetail = false
    private var closeWorkItem: DispatchWorkItem?

    init(codexStore: UsageStore, claudeStore: UsageStore, scheduler: RefreshScheduler) {
        self.codexStore = codexStore
        self.claudeStore = claudeStore
        self.scheduler = scheduler
    }

    func showIfAvailable() {
        guard let screen = NSScreen.main, screen.quotaPulseHasNotch else {
            self.pillPanel?.orderOut(nil)
            self.detailPanel?.orderOut(nil)
            return
        }

        let size = CGSize(width: 184, height: 28)
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height)

        if self.pillPanel == nil {
            let panel = MeterPanel(contentRect: frame)
            panel.contentView = NSHostingView(rootView: NotchPillView(
                codexStore: self.codexStore,
                claudeStore: self.claudeStore,
                onHover: { [weak self] hovering in self?.pillHoverChanged(hovering) },
                onClick: { [weak self] in self?.togglePinned() }))
            self.pillPanel = panel
        }
        self.pillPanel?.setFrame(frame, display: true)
        self.pillPanel?.orderFrontRegardless()
    }

    private func pillHoverChanged(_ hovering: Bool) {
        self.isHoveringPill = hovering
        hovering ? self.showDetail() : self.scheduleClose()
    }

    private func detailHoverChanged(_ hovering: Bool) {
        self.isHoveringDetail = hovering
        if hovering {
            self.closeWorkItem?.cancel()
        } else {
            self.scheduleClose()
        }
    }

    private func showDetail() {
        self.closeWorkItem?.cancel()
        guard let screen = NSScreen.main else { return }

        let maxPanelHeight = HoverPanelView.maxPanelHeight(for: screen.visibleFrame)
        let size = HoverPanelView.preferredContentSize(maxHeight: maxPanelHeight)
        let frame = self.detailFrame(size: size, screen: screen)

        let root = HoverPanelView(
            codexStore: self.codexStore,
            claudeStore: self.claudeStore,
            scheduler: self.scheduler,
            isPinned: self.isPinned,
            maxPanelHeight: maxPanelHeight,
            onRefresh: { [weak self] in self?.scheduler.refreshNow() },
            onTogglePin: { [weak self] in self?.togglePinned() },
            onQuit: { NSApp.terminate(nil) },
            onPreferredSizeChange: { [weak self] preferredSize in
                guard let self, let screen = NSScreen.main else { return }
                self.detailPanel?.setFrame(self.detailFrame(size: preferredSize, screen: screen), display: true)
            })
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onHover { [weak self] hovering in
                self?.detailHoverChanged(hovering)
            }

        if self.detailPanel == nil {
            let panel = MeterPanel(contentRect: frame)
            self.detailPanel = panel
        }
        self.detailPanel?.contentView = NSHostingView(rootView: root)
        self.detailPanel?.setFrame(frame, display: true)
        self.detailPanel?.orderFrontRegardless()
        self.scheduler.setDashboardVisible(true)
    }

    private func detailFrame(size: CGSize, screen: NSScreen) -> CGRect {
        CGRect(
            x: screen.frame.midX - size.width / 2,
            y: max(screen.visibleFrame.minY + 8, screen.frame.maxY - 28 - size.height - 8),
            width: size.width,
            height: min(size.height, max(1, screen.visibleFrame.height - 16)))
    }

    private func scheduleClose() {
        guard !self.isPinned else { return }
        self.closeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isHoveringPill, !self.isHoveringDetail else { return }
            self.detailPanel?.orderOut(nil)
            self.scheduler.setDashboardVisible(false)
        }
        self.closeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
    }

    private func togglePinned() {
        self.isPinned.toggle()
        if self.isPinned {
            self.showDetail()
        } else {
            self.scheduleClose()
        }
    }

}

private final class MeterPanel: NSPanel {
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
        self.level = .init(Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct NotchPillView: View {
    @ObservedObject var codexStore: UsageStore
    @ObservedObject var claudeStore: UsageStore
    let onHover: (Bool) -> Void
    let onClick: () -> Void

    var body: some View {
        Button(action: self.onClick) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.system(size: 11, weight: .semibold))
                Text(UsageDisplayFormatter.compactTitle(
                    codex: self.codexStore.snapshot,
                    claude: self.claudeStore.snapshot))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .foregroundStyle(.white)
            .background(
                Capsule()
                    .fill(Color.black)
                    .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
        .onHover(perform: self.onHover)
    }
}

private extension NSScreen {
    var quotaPulseHasNotch: Bool {
        self.safeAreaInsets.top > 0
    }
}
