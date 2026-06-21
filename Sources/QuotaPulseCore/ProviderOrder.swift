import Combine
import Foundation

public enum ProviderOrderDirection: Sendable {
    case up
    case down
}

public enum ProviderOrderDefaults {
    public static let key = "QuotaPulse.providerOrder.v1"
}

@MainActor
public final class ProviderOrderStore: ObservableObject {
    @Published public private(set) var providers: [ProviderKind]

    private let defaults: UserDefaults
    private let key: String

    public var keyForTesting: String { self.key }

    public init(
        defaults: UserDefaults = .standard,
        key: String = ProviderOrderDefaults.key)
    {
        self.defaults = defaults
        self.key = key
        self.providers = ProviderKind.normalizedOrder(
            defaults.stringArray(forKey: key)?.compactMap(ProviderKind.init(rawValue:)) ?? ProviderKind.defaultOrder)
    }

    public func move(_ provider: ProviderKind, direction: ProviderOrderDirection) {
        var next = self.providers
        guard let index = next.firstIndex(of: provider) else { return }
        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = index - 1
        case .down:
            targetIndex = index + 1
        }
        guard next.indices.contains(targetIndex) else { return }
        next.swapAt(index, targetIndex)
        self.set(next)
    }

    public func set(_ providers: [ProviderKind]) {
        let normalized = ProviderKind.normalizedOrder(providers)
        guard normalized != self.providers else { return }
        self.providers = normalized
        self.defaults.set(normalized.map(\.rawValue), forKey: self.key)
    }

    public func reset() {
        self.set(ProviderKind.defaultOrder)
    }
}
