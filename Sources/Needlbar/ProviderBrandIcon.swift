import AppKit
import OSLog
import SwiftUI
import NeedlbarCore

/// The single provider-to-brand mapping used by provider-facing SwiftUI views.
@MainActor
struct ProviderBrandIcon: View {
    enum Rendering: Equatable {
        case officialOrange
        case systemMonochrome
    }

    enum ContentMode: Equatable {
        case fit
    }

    enum Accessibility: Equatable {
        case decorative
        case labelled
    }

    enum AssetFailure: String, CaseIterable, Equatable, Error {
        case missing
        case malformed
        case incompatible
    }

    struct CatalogueEntry: Equatable {
        let resourceID: String
        let visibleProviderName: String
        let rendering: Rendering
        let fallbackSymbol: String

        init(
            resourceID: String,
            visibleProviderName: String,
            rendering: Rendering,
            fallbackSymbol: String
        ) {
            self.resourceID = resourceID
            self.visibleProviderName = visibleProviderName
            self.rendering = rendering
            self.fallbackSymbol = fallbackSymbol
        }
    }

    struct Plan {
        let image: NSImage?
        let frame: CGSize
        let contentMode: ContentMode
        let sourceAspectRatio: CGFloat?
        let rendering: Rendering
        let fallbackSymbol: String?
        let accessibilityLabel: String
        let accessibility: Accessibility
        let failure: AssetFailure?

        init(
            image: NSImage?,
            sourceAspectRatio: CGFloat?,
            rendering: Rendering,
            fallbackSymbol: String?,
            accessibilityLabel: String,
            accessibility: Accessibility,
            failure: AssetFailure?
        ) {
            self.image = image
            self.frame = CGSize(width: 18, height: 18)
            self.contentMode = .fit
            self.sourceAspectRatio = sourceAspectRatio
            self.rendering = rendering
            self.fallbackSymbol = fallbackSymbol
            self.accessibilityLabel = accessibilityLabel
            self.accessibility = accessibility
            self.failure = failure
        }
    }

    struct AssetLoader {
        let load: (String) -> Result<NSImage, AssetFailure>

        init(load: @escaping (String) -> Result<NSImage, AssetFailure>) {
            self.load = load
        }

        @MainActor
        static let bundle = AssetLoader { resourceID in
            guard let url = Bundle.module.url(
                forResource: resourceID,
                withExtension: "png",
                subdirectory: "ProviderBrands"
            ) else {
                return .failure(.missing)
            }

            guard let image = NSImage(contentsOf: url) else {
                return .failure(.malformed)
            }

            guard ProviderBrandIcon.isCompatible(image) else {
                return .failure(.incompatible)
            }

            return .success(image)
        }
    }

    static let catalogue: [ProviderID: CatalogueEntry] = [
        .claude: CatalogueEntry(
            resourceID: "provider-brand-claude",
            visibleProviderName: "Claude",
            rendering: .officialOrange,
            fallbackSymbol: "sparkles"
        ),
        .codex: CatalogueEntry(
            resourceID: "provider-brand-openai-blossom",
            visibleProviderName: "Codex",
            rendering: .systemMonochrome,
            fallbackSymbol: "chevron.left.forwardslash.chevron.right"
        ),
        .cursor: CatalogueEntry(
            resourceID: "provider-brand-cursor-2d",
            visibleProviderName: "Cursor",
            rendering: .systemMonochrome,
            fallbackSymbol: "cursorarrow"
        ),
    ]

    static let iconFrame = CGSize(width: 18, height: 18)

    private static let logger = Logger(subsystem: "com.taejunoh.needlbar", category: "ProviderBrandIcon")
    private static let diagnosticsLock = NSLock()
    private static var recordedFailures = Set<String>()

    private let planValue: Plan

    init(
        provider: ProviderID,
        loader: AssetLoader = .bundle,
        accessibility: Accessibility = .decorative
    ) {
        planValue = Self.plan(for: provider, loader: loader, accessibility: accessibility)
    }

    var plan: Plan { planValue }

    static func catalogueEntry(for provider: ProviderID) -> CatalogueEntry {
        // The switch makes an omitted provider fail at compile time when ProviderID grows.
        switch provider {
        case .claude: return catalogue[.claude]!
        case .codex: return catalogue[.codex]!
        case .cursor: return catalogue[.cursor]!
        }
    }

    static func plan(
        for provider: ProviderID,
        loader: AssetLoader = .bundle,
        accessibility: Accessibility = .decorative
    ) -> Plan {
        let entry = catalogueEntry(for: provider)
        let loaded: Result<NSImage, AssetFailure> = loader.load(entry.resourceID)

        switch loaded {
        case let .success(image) where isCompatible(image):
            let size = image.size
            return Plan(
                image: image,
                sourceAspectRatio: size.width / size.height,
                rendering: entry.rendering,
                fallbackSymbol: nil,
                accessibilityLabel: entry.visibleProviderName,
                accessibility: accessibility,
                failure: nil
            )
        case .success:
            recordFailure(.incompatible, provider: provider, entry: entry)
            return fallbackPlan(entry: entry, accessibility: accessibility, failure: .incompatible)
        case let .failure(failure):
            recordFailure(failure, provider: provider, entry: entry)
            return fallbackPlan(entry: entry, accessibility: accessibility, failure: failure)
        }
    }

    @ViewBuilder
    var body: some View {
        iconView
            .frame(width: planValue.frame.width, height: planValue.frame.height)
            .applyAccessibility(planValue.accessibility, label: planValue.accessibilityLabel)
    }

    @ViewBuilder
    private var iconView: some View {
        if let image = planValue.image {
            if planValue.rendering == .systemMonochrome {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(Color.primary)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
            }
        } else {
            Image(systemName: planValue.fallbackSymbol ?? "questionmark")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(planValue.rendering == .officialOrange ? Color.orange : Color.primary)
        }
    }

    private static func fallbackPlan(
        entry: CatalogueEntry,
        accessibility: Accessibility,
        failure: AssetFailure
    ) -> Plan {
        Plan(
            image: nil,
            sourceAspectRatio: nil,
            rendering: entry.rendering,
            fallbackSymbol: entry.fallbackSymbol,
            accessibilityLabel: entry.visibleProviderName,
            accessibility: accessibility,
            failure: failure
        )
    }

    private static func isCompatible(_ image: NSImage) -> Bool {
        let size = image.size
        return size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }

    private static func recordFailure(
        _ failure: AssetFailure,
        provider: ProviderID,
        entry: CatalogueEntry
    ) {
        let key = "\(provider.rawValue)|\(entry.resourceID)|\(failure.rawValue)"
        diagnosticsLock.lock()
        defer { diagnosticsLock.unlock() }
        guard recordedFailures.insert(key).inserted else { return }
        logger.warning("Provider brand asset fallback: provider=\(provider.rawValue, privacy: .public) resource=\(entry.resourceID, privacy: .public) failure=\(failure.rawValue, privacy: .public)")
    }
}

private extension View {
    @ViewBuilder
    func applyAccessibility(
        _ accessibility: ProviderBrandIcon.Accessibility,
        label: String
    ) -> some View {
        switch accessibility {
        case .decorative:
            accessibilityHidden(true)
        case .labelled:
            accessibilityLabel(label)
        }
    }
}
