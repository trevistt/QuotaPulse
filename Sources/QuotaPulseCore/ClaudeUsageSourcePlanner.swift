import Foundation

public enum ClaudeUsageSourceKind: String, Equatable, Sendable {
    case oauth
    case cli
    case disabled
    case failure
}

public struct ClaudeUsageSourcePlan: Equatable, Sendable {
    public let orderedSources: [ClaudeUsageSourceKind]
    public let failureMessage: String?

    public init(orderedSources: [ClaudeUsageSourceKind], failureMessage: String? = nil) {
        self.orderedSources = orderedSources
        self.failureMessage = failureMessage.map(UsageSnapshot.sanitized)
    }

    public var usesOAuth: Bool {
        self.orderedSources.contains(.oauth)
    }

    public var usesCLI: Bool {
        self.orderedSources.contains(.cli)
    }
}

public enum ClaudeUsageSourcePlanner {
    public static func plan(
        hasOAuthCredentials: Bool,
        oauthCredentialErrorMessage: String?,
        cliFallbackEnabled: Bool)
        -> ClaudeUsageSourcePlan
    {
        if hasOAuthCredentials {
            return ClaudeUsageSourcePlan(
                orderedSources: cliFallbackEnabled ? [.oauth, .cli] : [.oauth])
        }
        if let oauthCredentialErrorMessage,
           !oauthCredentialErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return ClaudeUsageSourcePlan(
                orderedSources: [.failure],
                failureMessage: oauthCredentialErrorMessage)
        }
        if cliFallbackEnabled {
            return ClaudeUsageSourcePlan(orderedSources: [.cli])
        }
        return ClaudeUsageSourcePlan(orderedSources: [.disabled])
    }
}
