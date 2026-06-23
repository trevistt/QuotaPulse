import AppKit
import Darwin

@main
enum QuotaPulseMain {
    @MainActor
    private static var appDelegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        if ProcessInfo.processInfo.arguments.contains("--smoke-check") {
            app.setActivationPolicy(.accessory)
            let passed = UISmokeCheck.run()
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if let outputPath = Self.argument(after: "--visual-qa-fixture") {
            app.setActivationPolicy(.accessory)
            let passed = VisualQAFixtureRunner.run(outputURL: URL(fileURLWithPath: outputPath), variant: .standard)
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if let outputPath = Self.argument(after: "--visual-qa-fixture-compact") {
            app.setActivationPolicy(.accessory)
            let passed = VisualQAFixtureRunner.run(outputURL: URL(fileURLWithPath: outputPath), variant: .compactOverview)
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if let outputPath = Self.argument(after: "--visual-qa-fixture-tall") {
            app.setActivationPolicy(.accessory)
            let passed = VisualQAFixtureRunner.run(outputURL: URL(fileURLWithPath: outputPath), variant: .tallContent)
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if let outputPath = Self.argument(after: "--visual-qa-fixture-constrained") {
            app.setActivationPolicy(.accessory)
            let passed = VisualQAFixtureRunner.run(outputURL: URL(fileURLWithPath: outputPath), variant: .constrainedHeight)
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if let outputPath = Self.argument(after: "--visual-qa-fixture-codex-analytics-only") {
            app.setActivationPolicy(.accessory)
            let passed = VisualQAFixtureRunner.run(outputURL: URL(fileURLWithPath: outputPath), variant: .codexAnalyticsOnly)
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if let outputPath = Self.argument(after: "--visual-qa-fixture-claude-analytics-error") {
            app.setActivationPolicy(.accessory)
            let passed = VisualQAFixtureRunner.run(outputURL: URL(fileURLWithPath: outputPath), variant: .claudeAnalyticsError)
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if let outputPath = Self.argument(after: "--visual-qa-fixture-no-analytics") {
            app.setActivationPolicy(.accessory)
            let passed = VisualQAFixtureRunner.run(outputURL: URL(fileURLWithPath: outputPath), variant: .noAnalytics)
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if let outputPath = Self.argument(after: "--visual-qa-fixture-claude-first") {
            app.setActivationPolicy(.accessory)
            let passed = VisualQAFixtureRunner.run(outputURL: URL(fileURLWithPath: outputPath), variant: .claudeFirst)
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if let outputPath = Self.argument(after: "--visual-qa-fixture-claude-auth-blocked") {
            app.setActivationPolicy(.accessory)
            let passed = VisualQAFixtureRunner.run(outputURL: URL(fileURLWithPath: outputPath), variant: .claudeAuthBlocked)
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if let outputPath = Self.argument(after: "--visual-qa-fixture-claude-auth-unavailable") {
            app.setActivationPolicy(.accessory)
            let passed = VisualQAFixtureRunner.run(outputURL: URL(fileURLWithPath: outputPath), variant: .claudeAuthUnavailable)
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        let delegate = AppDelegate()
        Self.appDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private static func argument(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: flag),
              args.indices.contains(index + 1)
        else { return nil }
        return args[index + 1]
    }
}
