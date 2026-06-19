import AppKit
import QuotaPulseCore
import SwiftUI

@MainActor
enum ProviderBrandIcon {
    private static let subdirectory = "BrandIcons"
    private static var cache: [ProviderKind: NSImage] = [:]

    static func image(
        for provider: ProviderKind,
        size: NSSize = NSSize(width: 16, height: 16),
        isTemplate: Bool = true)
        -> NSImage?
    {
        guard let baseImage = self.baseImage(for: provider),
              let image = baseImage.copy() as? NSImage
        else {
            return nil
        }
        image.size = size
        image.isTemplate = isTemplate
        return image
    }

    static func isAvailable(for provider: ProviderKind) -> Bool {
        self.resourceURL(for: provider) != nil
    }

    static func resetCacheForTesting() {
        self.cache.removeAll()
    }

    static func fallbackSystemImage(for provider: ProviderKind) -> String {
        switch provider {
        case .codex:
            "gauge.with.dots.needle.50percent"
        case .claude:
            "sparkles"
        }
    }

    private static func baseImage(for provider: ProviderKind) -> NSImage? {
        if let cached = self.cache[provider] {
            return cached
        }
        guard let url = self.resourceURL(for: provider),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        self.cache[provider] = image
        return image
    }

    private static func resourceURL(for provider: ProviderKind) -> URL? {
        let resourceName = self.resourceName(for: provider)
        for bundle in self.resourceBundles() {
            if let url = bundle.url(
                forResource: resourceName,
                withExtension: "svg",
                subdirectory: self.subdirectory)
            {
                return url
            }
            if let url = bundle.url(
                forResource: resourceName,
                withExtension: "svg",
                subdirectory: "Resources/\(self.subdirectory)")
            {
                return url
            }
        }
        return self.sourceTreeResourceURL(resourceName: resourceName)
    }

    private static func resourceBundles() -> [Bundle] {
        var bundles: [Bundle] = [Bundle.main]
        if let appResourceBundleURL = Bundle.main.url(
            forResource: "QuotaPulse_QuotaPulse",
            withExtension: "bundle"),
            let appResourceBundle = Bundle(url: appResourceBundleURL)
        {
            bundles.append(appResourceBundle)
        }
        bundles.append(Bundle.module)
        return bundles.reduce(into: [Bundle]()) { unique, bundle in
            if !unique.contains(where: { $0.bundleURL == bundle.bundleURL }) {
                unique.append(bundle)
            }
        }
    }

    private static func sourceTreeResourceURL(resourceName: String) -> URL? {
        let current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates = [
            current.appendingPathComponent("Sources/QuotaPulse/Resources/\(self.subdirectory)/\(resourceName).svg"),
            current.deletingLastPathComponent()
                .appendingPathComponent("Sources/QuotaPulse/Resources/\(self.subdirectory)/\(resourceName).svg"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func resourceName(for provider: ProviderKind) -> String {
        switch provider {
        case .codex:
            "openai"
        case .claude:
            "claude"
        }
    }
}

struct ProviderBrandIconView: View {
    let provider: ProviderKind
    let size: CGFloat
    let fallbackSystemImage: String

    var body: some View {
        if let image = ProviderBrandIcon.image(
            for: self.provider,
            size: NSSize(width: self.size, height: self.size))
        {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: self.size, height: self.size)
        } else {
            Image(systemName: self.fallbackSystemImage)
                .font(.system(size: self.size * 0.9, weight: .bold))
                .frame(width: self.size, height: self.size)
        }
    }
}
