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
            let passed = VisualQAFixtureRunner.run(outputURL: URL(fileURLWithPath: outputPath))
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
