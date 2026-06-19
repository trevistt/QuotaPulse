import Darwin
import Foundation

public struct ClaudeCLIUsageProvider: CodexUsageProviding, Sendable {
    private let env: [String: String]
    private let executable: String
    private let timeout: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        env: [String: String] = ProcessInfo.processInfo.environment,
        executable: String = "claude",
        timeout: TimeInterval = 12,
        now: @escaping @Sendable () -> Date = Date.init)
    {
        self.env = env
        self.executable = executable
        self.timeout = timeout
        self.now = now
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) {
            try self.fetchUsageBlocking()
        }.value
    }

    public static func mapUsageOutput(_ raw: String, updatedAt: Date = Date()) throws -> UsageSnapshot {
        let clean = Self.stripANSICodes(raw)
        if let prompt = Self.interactivePromptError(in: clean) {
            throw ClaudeUsageProviderError.processFailed(prompt)
        }

        let lines = clean.components(separatedBy: .newlines)
        guard let session = Self.window(
            label: "Current session",
            lines: lines,
            seconds: 18_000)
        else {
            throw ClaudeUsageProviderError.invalidResponse("Claude CLI /usage output did not include Current session usage.")
        }

        let weekly = Self.window(
            label: "Current week",
            lines: lines,
            seconds: 604_800)

        return UsageSnapshot.fromWindows(
            primary: session,
            secondary: weekly,
            source: .claudeCLI,
            updatedAt: updatedAt)
    }

    public static func probeWorkingDirectory(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = QuotaPulseEnvironment.value("QUOTA_PULSE_CLAUDE_PROBE_CWD", in: env) {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/QuotaPulse/ClaudeProbe", isDirectory: true)
    }

    public static func executablePath(env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let override = QuotaPulseEnvironment.value("QUOTA_PULSE_CLAUDE_CLI_PATH", in: env) {
            return override
        }
        if let override = env["CLAUDE_CLI_PATH"], !override.isEmpty {
            return override
        }
        return "claude"
    }

    public static func cleanupProbeArtifacts(
        probeDirectory: URL = Self.probeWorkingDirectory(),
        env: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default) -> [URL]
    {
        let projectDirectoryName = Self.claudeProjectDirectoryName(for: probeDirectory)
        var removed: [URL] = []
        for root in Self.claudeConfigRoots(env: env, fileManager: fileManager) {
            let directory = root
                .appendingPathComponent("projects", isDirectory: true)
                .appendingPathComponent(projectDirectoryName, isDirectory: true)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles])
            else { continue }

            for entry in entries where entry.pathExtension == "jsonl" {
                let values = try? entry.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                if (try? fileManager.removeItem(at: entry)) != nil {
                    removed.append(entry)
                }
            }
            if (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? fileManager.removeItem(at: directory)
            }
        }
        return removed
    }

    private func fetchUsageBlocking() throws -> UsageSnapshot {
        let executable = Self.executablePath(env: self.env)
        let probeDirectory = Self.probeWorkingDirectory(env: self.env)
        try FileManager.default.createDirectory(at: probeDirectory, withIntermediateDirectories: true)

        let stateBefore = Self.captureProtectedState(env: self.env)
        let output = try Self.runClaudeUsage(
            executable: executable,
            env: self.env,
            probeDirectory: probeDirectory,
            timeout: self.timeout)
        _ = Self.cleanupProbeArtifacts(probeDirectory: probeDirectory, env: self.env)
        let stateAfter = Self.captureProtectedState(env: self.env)
        let changed = Self.changedStateFiles(before: stateBefore, after: stateAfter)
        guard changed.isEmpty else {
            throw ClaudeUsageProviderError.processFailed(
                "Claude CLI changed protected local state (\(changed.joined(separator: ", "))); live CLI fallback stopped.")
        }
        return try Self.mapUsageOutput(output, updatedAt: self.now())
    }

    private static func runClaudeUsage(
        executable: String,
        env: [String: String],
        probeDirectory: URL,
        timeout: TimeInterval) throws -> String
    {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable, "--allowed-tools", ""]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.currentDirectoryURL = probeDirectory
        process.environment = Self.scrubbedEnvironment(env, probeDirectory: probeDirectory)

        do {
            try process.run()
        } catch {
            throw ClaudeUsageProviderError.processFailed("Claude CLI launch failed: \(error.localizedDescription)")
        }

        stdin.fileHandleForWriting.write(Data("/usage\n/exit\n".utf8))
        try? stdin.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            throw ClaudeUsageProviderError.processFailed("Claude CLI /usage timed out.")
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data + errorData, encoding: .utf8) ?? ""
        if let prompt = Self.interactivePromptError(in: output) {
            throw ClaudeUsageProviderError.processFailed(prompt)
        }
        guard process.terminationStatus == 0 || !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClaudeUsageProviderError.processFailed("Claude CLI exited with status \(process.terminationStatus).")
        }
        return output
    }

    private static func scrubbedEnvironment(_ env: [String: String], probeDirectory: URL) -> [String: String] {
        var output = env
        output["PWD"] = probeDirectory.path
        if output["PATH"] == nil || output["PATH"]?.isEmpty == true {
            output["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        }
        for key in output.keys where key.hasPrefix("ANTHROPIC_") {
            output.removeValue(forKey: key)
        }
        return output
    }

    private static func window(label: String, lines: [String], seconds: Int) -> UsageWindow? {
        let normalizedLabel = Self.normalized(label)
        for (index, line) in lines.enumerated() where Self.normalized(line).contains(normalizedLabel) {
            let section = Array(lines.dropFirst(index).prefix(14))
            guard let percentLeft = section.compactMap(Self.percentLeft).first else { return nil }
            let resetAt = section.compactMap { Self.resetDate(from: $0) }.first
            return UsageWindow(
                usedPercent: 100 - Double(percentLeft),
                resetAt: resetAt,
                windowSeconds: seconds)
        }
        return nil
    }

    private static func percentLeft(from line: String) -> Int? {
        guard !Self.normalized(line).contains("context") else { return nil }
        let pattern = #"([0-9]{1,3}(?:\.[0-9]+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: line),
              let rawValue = Double(line[valueRange]) else { return nil }
        let value = min(100, max(0, rawValue))
        let lower = line.lowercased()
        if ["left", "remaining", "available"].contains(where: lower.contains) {
            return Int(value.rounded())
        }
        if ["used", "spent", "consumed"].contains(where: lower.contains) {
            return Int((100 - value).rounded())
        }
        return nil
    }

    private static func resetDate(from line: String, now: Date = Date()) -> Date? {
        guard let range = line.range(of: "resets", options: [.caseInsensitive]) else { return nil }
        var raw = String(line[range.lowerBound...])
        raw = raw.replacingOccurrences(of: #"(?i)^resets?:?\s*"#, with: "", options: .regularExpression)
        raw = raw.replacingOccurrences(of: " at ", with: " ", options: .caseInsensitive)
        raw = raw.replacingOccurrences(of: " on ", with: " ", options: .caseInsensitive)
        raw = raw.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
        raw = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".:")))
        guard !raw.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.defaultDate = now
        let calendar = Calendar.current
        let formats = [
            "MMM d, h:mma",
            "MMM d h:mma",
            "MMM d, h:mm a",
            "MMM d h:mm a",
            "h:mma",
            "h:mm a",
            "HH:mm",
            "H:mm",
        ]
        for format in formats {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: raw) else { continue }
            if format.contains("MMM") {
                return parsed
            }
            var components = calendar.dateComponents([.hour, .minute], from: parsed)
            components.year = calendar.component(.year, from: now)
            components.month = calendar.component(.month, from: now)
            components.day = calendar.component(.day, from: now)
            guard let today = calendar.date(from: components) else { return nil }
            return today >= now ? today : calendar.date(byAdding: .day, value: 1, to: today)
        }
        return nil
    }

    private static func interactivePromptError(in text: String) -> String? {
        let clean = Self.stripANSICodes(text)
        let lower = clean.lowercased()
        let promptNeedles = [
            "do you trust the files",
            "yes, i trust",
            "ready to code here",
            "quick safety check",
            "press enter to continue",
            "login required",
            "please log in",
            "claude login",
            "permission",
            "telemetry",
        ]
        if let needle = promptNeedles.first(where: lower.contains) {
            return "Claude CLI requires interactive setup or permission prompt (\(needle)); live CLI fallback stopped."
        }
        return nil
    }

    private static func stripANSICodes(_ text: String) -> String {
        let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    private static func claudeProjectDirectoryName(for directory: URL) -> String {
        let path = directory.path.precomposedStringWithCanonicalMapping
        let mapped = path.utf16.map { codeUnit -> Character in
            switch codeUnit {
            case 48...57, 65...90, 97...122:
                Character(UnicodeScalar(codeUnit)!)
            default:
                "-"
            }
        }
        let sanitized = String(mapped)
        guard sanitized.count > 200 else { return sanitized }
        return String(sanitized.prefix(200))
    }

    private static func claudeConfigRoots(env: [String: String], fileManager: FileManager) -> [URL] {
        var roots: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { return }
            roots.append(standardized)
        }

        if let raw = env["CLAUDE_CONFIG_DIR"] {
            for part in raw.split(separator: ",") {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                append(URL(fileURLWithPath: trimmed, isDirectory: true))
            }
        }
        let home = env["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        append(URL(fileURLWithPath: home).appendingPathComponent(".claude", isDirectory: true))
        append(URL(fileURLWithPath: home).appendingPathComponent(".config/claude", isDirectory: true))
        if roots.isEmpty {
            append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true))
        }
        return roots
    }

    private struct FileState: Equatable {
        let exists: Bool
        let modifiedAt: TimeInterval?
        let size: Int64?
    }

    private static func captureProtectedState(
        env: [String: String],
        fileManager: FileManager = .default) -> [String: FileState]
    {
        Dictionary(
            uniqueKeysWithValues: Self.monitoredProtectedStateFiles(env: env).map { url in
                (url.path, Self.fileState(url: url, fileManager: fileManager))
            })
    }

    private static func changedStateFiles(before: [String: FileState], after: [String: FileState]) -> [String] {
        before.keys
            .sorted()
            .filter { before[$0] != after[$0] }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private static func monitoredProtectedStateFiles(env: [String: String]) -> [URL] {
        let home = env["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        let homeURL = URL(fileURLWithPath: home, isDirectory: true)
        return [
            homeURL.appendingPathComponent(".claude/.credentials.json"),
            homeURL.appendingPathComponent(".claude/settings.json"),
            homeURL.appendingPathComponent(".codex/auth.json"),
            homeURL.appendingPathComponent(".codex/config.toml"),
        ]
    }

    private static func fileState(url: URL, fileManager: FileManager) -> FileState {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        else {
            return FileState(exists: false, modifiedAt: nil, size: nil)
        }
        return FileState(
            exists: true,
            modifiedAt: values.contentModificationDate?.timeIntervalSince1970,
            size: values.fileSize.map(Int64.init))
    }
}
