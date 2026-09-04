import AppKit
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("ProviderBrandIconTests", .serialized)
@MainActor
struct ProviderBrandIconTests {
    @Test("catalogue maps every provider to its approved brand entry")
    func providerBrandCatalogueMapsEveryProviderToItsApprovedBrandEntry() {
        let claude = ProviderBrandIcon.catalogueEntry(for: .claude)
        #expect(claude.resourceID == "provider-brand-claude")
        #expect(claude.visibleProviderName == "Claude")
        #expect(claude.rendering == .officialOrange)
        #expect(claude.fallbackSymbol == "sparkles")

        let codex = ProviderBrandIcon.catalogueEntry(for: .codex)
        #expect(codex.resourceID == "provider-brand-openai-blossom")
        #expect(codex.visibleProviderName == "Codex")
        #expect(codex.rendering == .systemMonochrome)
        #expect(codex.fallbackSymbol == "chevron.left.forwardslash.chevron.right")

        let cursor = ProviderBrandIcon.catalogueEntry(for: .cursor)
        #expect(cursor.resourceID == "provider-brand-cursor-2d")
        #expect(cursor.visibleProviderName == "Cursor")
        #expect(cursor.rendering == .systemMonochrome)
        #expect(cursor.fallbackSymbol == "cursorarrow")
    }

    @Test("Codex plan uses the provider-specific visible label")
    func providerBrandCodexPlanUsesTheProviderSpecificVisibleLabel() {
        let plan = ProviderBrandIcon.plan(for: .codex, loader: .init { _ in
            .failure(.missing)
        }, accessibility: .labelled)

        #expect(plan.accessibilityLabel == "Codex")
        #expect(plan.accessibility == .labelled)
    }

    @Test("all providers use the fixed fitting frame and preserve source aspect ratio")
    func providerBrandPlansUseTheFixedFittingFrameAndPreserveSourceAspectRatio() throws {
        let sizes: [ProviderID: CGSize] = [
            .claude: CGSize(width: 937, height: 937),
            .codex: CGSize(width: 716, height: 716),
            .cursor: CGSize(width: 1401, height: 1597),
        ]

        for provider in ProviderID.allCases {
            let plan = ProviderBrandIcon.plan(for: provider, loader: .init { entry in
                let expected = ProviderBrandIcon.catalogueEntry(for: provider)
                #expect(entry == expected)
                return .success(NSImage(size: sizes[provider]!))
            })

            #expect(plan.frame == CGSize(width: 18, height: 18))
            #expect(plan.contentMode == .fit)
            let expectedRatio = sizes[provider]!.width / sizes[provider]!.height
            #expect(plan.sourceAspectRatio == expectedRatio)
            #expect(plan.image != nil)
            #expect(plan.fallbackSymbol == nil)
            #expect(plan.failure == nil)
        }
    }

    @Test("missing malformed and incompatible assets retain fallback identity and frame")
    func providerBrandFailuresRetainFallbackIdentityAndFrame() {
        let failures: [ProviderBrandIcon.AssetFailure] = [.missing, .malformed, .incompatible]

        for failure in failures {
            let plan = ProviderBrandIcon.plan(for: .cursor, loader: .init { _ in
                .failure(failure)
            })

            #expect(plan.image == nil)
            #expect(plan.fallbackSymbol == "cursorarrow")
            #expect(plan.frame == CGSize(width: 18, height: 18))
            #expect(plan.contentMode == .fit)
            #expect(plan.failure == failure)
            #expect(plan.sourceAspectRatio == nil)
        }
    }

    @Test("zero and nonfinite image sizes become incompatible")
    func providerBrandInvalidImageSizesBecomeIncompatible() {
        let invalidSizes = [
            CGSize(width: 0, height: 10),
            CGSize(width: 10, height: 0),
            CGSize(width: CGFloat.infinity, height: 10),
            CGSize(width: 10, height: CGFloat.nan),
        ]

        for size in invalidSizes {
            let plan = ProviderBrandIcon.plan(for: .claude, loader: .init { _ in
                .success(NSImage(size: size))
            })
            #expect(plan.image == nil)
            #expect(plan.failure == .incompatible)
            #expect(plan.fallbackSymbol == "sparkles")
        }
    }

    @Test("the bundled provider brand resources resolve")
    func bundledProviderBrandResourcesResolve() {
        for provider in ProviderID.allCases {
            let plan = ProviderBrandIcon.plan(for: provider)
            #expect(plan.image != nil)
            #expect(plan.failure == nil)
            #expect((plan.sourceAspectRatio ?? 0) > 0)
        }
    }

    @Test("decorative icons are hidden and labelled icons expose the provider label")
    func providerBrandAccessibilityPolicyDistinguishesDecorativeAndLabelled() {
        let decorative = ProviderBrandIcon.plan(for: .claude, loader: .init { _ in .failure(.missing) })
        #expect(decorative.accessibility == .decorative)
        #expect(decorative.accessibilityLabel == "Claude")

        let labelled = ProviderBrandIcon.plan(for: .claude, loader: .init { _ in .failure(.missing) }, accessibility: .labelled)
        #expect(labelled.accessibility == .labelled)
        #expect(labelled.accessibilityLabel == "Claude")
    }

    @Test("brand treatment is invariant across aqua and dark aqua")
    func providerBrandTreatmentIsInvariantAcrossAquaAndDarkAqua() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = NSAppearance(named: name)!
            appearance.performAsCurrentDrawingAppearance {
                let claude = ProviderBrandIcon.plan(for: .claude)
                let codex = ProviderBrandIcon.plan(for: .codex)
                let cursor = ProviderBrandIcon.plan(for: .cursor)

                #expect(claude.rendering == .officialOrange)
                #expect(codex.rendering == .systemMonochrome)
                #expect(cursor.rendering == .systemMonochrome)
            }
        }
    }
}
