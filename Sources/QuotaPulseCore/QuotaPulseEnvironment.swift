import Foundation

public enum QuotaPulseEnvironment {
    public static func value(
        _ name: String,
        in env: [String: String] = ProcessInfo.processInfo.environment)
        -> String?
    {
        if let value = env[name], !value.isEmpty {
            return value
        }
        guard let legacyName = self.legacyName(for: name),
              let legacyValue = env[legacyName],
              !legacyValue.isEmpty
        else {
            return nil
        }
        return legacyValue
    }

    public static func isEnabled(
        _ name: String,
        in env: [String: String] = ProcessInfo.processInfo.environment)
        -> Bool
    {
        self.value(name, in: env) == "1"
    }

    public static func isExplicitlySet(
        _ name: String,
        in env: [String: String] = ProcessInfo.processInfo.environment)
        -> Bool
    {
        if env[name]?.isEmpty == false {
            return true
        }
        guard let legacyName = self.legacyName(for: name) else {
            return false
        }
        return env[legacyName]?.isEmpty == false
    }

    public static func legacyName(for name: String) -> String? {
        let prefix = "QUOTA_PULSE_"
        guard name.hasPrefix(prefix) else {
            return nil
        }
        return "CODEX_NOTCH_METER_" + String(name.dropFirst(prefix.count))
    }
}
