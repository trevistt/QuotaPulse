import AppKit
import QuotaPulseCore
import SwiftUI

@MainActor
enum VisualQAFixtureRunner {
    static func run(outputURL: URL) -> Bool {
        let codexStore = UsageStore(
            provider: FixtureCodexUsageProvider(mode: .success),
            cache: UsageSnapshotCache(url: Self.tempCacheURL("codex")))
        let claudeStore = UsageStore(
            provider: FixtureClaudeUsageProvider(mode: .success),
            cache: UsageSnapshotCache(url: Self.tempCacheURL("claude")))
        let scheduler = RefreshScheduler(stores: [codexStore, claudeStore])

        guard Self.refresh(codexStore: codexStore, claudeStore: claudeStore) else {
            print("Visual QA failed: fixture stores did not refresh")
            return false
        }

        let size = CGSize(width: 760, height: 680)
        let root = VisualQAFixtureView(
            codexStore: codexStore,
            claudeStore: claudeStore,
            scheduler: scheduler)
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

    private static func refresh(codexStore: UsageStore, claudeStore: UsageStore) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var passed = false
        Task { @MainActor in
            let codexPassed = await codexStore.refresh()
            let claudePassed = await claudeStore.refresh()
            passed = codexPassed && claudePassed
            semaphore.signal()
        }
        while semaphore.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return passed
    }

    private static func tempCacheURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-pulse-visual-qa-\(name)-\(UUID().uuidString).json")
    }
}

private struct VisualQAFixtureView: View {
    @ObservedObject var codexStore: UsageStore
    @ObservedObject var claudeStore: UsageStore
    let scheduler: RefreshScheduler

    var body: some View {
        VStack(spacing: 18) {
            self.previewMenuBar
            HoverPanelView(
                codexStore: self.codexStore,
                claudeStore: self.claudeStore,
                cadence: self.scheduler.cadence,
                isPinned: true,
                onRefresh: {},
                onTogglePin: {},
                onCadenceChange: { _ in },
                onQuit: {})
        }
        .padding(28)
        .frame(width: 760, height: 680)
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
            Text("Fixture Visual QA")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            MenuBarMeterMock(
                codex: self.codexStore.snapshot,
                claude: self.claudeStore.snapshot)
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

    var body: some View {
        let values = UsageDisplayFormatter.menuBarLines(codex: self.codex, claude: self.claude).map(\.value)
        let width = StatusItemController.menuBarWidthForTesting(values: values)
        VStack(alignment: .leading, spacing: 1) {
            meterRow(
                provider: .codex,
                value: values[0])
            meterRow(
                provider: .claude,
                value: values[1])
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
