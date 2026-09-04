import Foundation
import Testing

@Suite("ProviderBrandSurfaceContractTests", .serialized)
struct ProviderBrandSurfaceContractTests {
    @Test("all approved provider surfaces use the shared decorative brand icon")
    func approvedProviderSurfacesUseSharedBrandIcon() throws {
        for relativePath in Self.surfacePaths {
            let source = try String(contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath), encoding: .utf8)

            #expect(source.contains("ProviderBrandIcon(provider:"), "Missing ProviderBrandIcon wiring in \(relativePath)")
            #expect(source.contains("accessibility: .decorative"), "Provider brand icon must be decorative in \(relativePath)")
            #expect(!source.contains("provider.systemImage"), "Legacy provider systemImage usage remains in \(relativePath)")
            #expect(!source.contains("presentation.provider.systemImage"), "Legacy provider systemImage usage remains in \(relativePath)")
            #expect(!source.contains("row.provider.systemImage"), "Legacy provider systemImage usage remains in \(relativePath)")
        }
    }

    private static let surfacePaths = [
        "Sources/Needlbar/Modules/Overview/SystemDashboardPopoverView.swift",
        "Sources/Needlbar/Modules/Overview/OverviewPopoverView.swift",
        "Sources/Needlbar/Modules/Provider/ProviderPopoverView.swift",
        "Sources/Needlbar/Settings/SystemMonitorSettingsView.swift",
        "Sources/Needlbar/Settings/SettingsView.swift",
    ]

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
