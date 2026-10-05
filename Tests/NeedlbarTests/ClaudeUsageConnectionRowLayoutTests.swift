import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("ClaudeUsageConnectionRowLayout", .serialized)
@MainActor
struct ClaudeUsageConnectionRowLayoutTests {
    private static let now = Date(timeIntervalSince1970: 1_790_755_200)

    @Test func connectionCardHasApprovedClearanceAroundRealClaudeRow() throws {
        let (settings, defaultsName, defaults) = try Self.settings(snapshot: Self.lastKnownSnapshot())
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let contentCard = SettingsStudioSection(title: "Connection") {
            settings.claudeUsageRowContent
        }
        let renderedCard = SettingsStudioSection(title: "Connection") {
            settings.claudeUsageRow
        }
        let contentSize = Self.fittingSize(of: contentCard)
        let renderedSize = Self.fittingSize(of: renderedCard)

        #expect(abs((renderedSize.width - contentSize.width) - 16) < 1)
        #expect(abs((renderedSize.height - contentSize.height) - 40) < 1)
    }

    @Test func longLastKnownMetadataWrapsAtNarrowWidthAndRendersInBothAppearances() throws {
        let (settings, defaultsName, defaults) = try Self.settings(snapshot: Self.lastKnownSnapshot())
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        let wideHeight = Self.fittingSize(of: Self.card(settings).frame(width: 491, alignment: .topLeading)).height
        let narrowHeight = Self.fittingSize(of: Self.card(settings).frame(width: 390, alignment: .topLeading)).height
        #expect(narrowHeight > wideHeight)

        try Self.render(Self.card(settings), name: "last-known-light-minimum-window-column", width: 491, appearance: .aqua)
        try Self.render(Self.card(settings), name: "last-known-dark-narrow", width: 390, appearance: .darkAqua)
        try Self.render(Self.card(settings), name: "last-known-dark-extreme-320", width: 320, appearance: .darkAqua)

        let (freshSettings, freshDefaultsName, freshDefaults) = try Self.settings(snapshot: Self.freshSnapshot())
        defer { freshDefaults.removePersistentDomain(forName: freshDefaultsName) }
        try Self.render(Self.card(freshSettings), name: "fresh-light-minimum-window-column", width: 491, appearance: .aqua)
    }

    @Test func unavailableQuotaAndFableStillRenderWithoutAQuotaSnapshot() throws {
        let snapshot = ProviderSnapshot(
            provider: .claude,
            usage: nil,
            quota: nil,
            usageStatus: .unavailable,
            quotaStatus: .error(message: "fixture only", lastSuccessfulAt: nil),
            updatedAt: Self.now,
            claudeQuotaFailureReason: .couldNotUpdateQuota
        )
        let (settings, defaultsName, defaults) = try Self.settings(snapshot: snapshot)
        defer { defaults.removePersistentDomain(forName: defaultsName) }

        try Self.render(Self.card(settings), name: "unavailable-dark", width: 500, appearance: .darkAqua)
    }

    private static func settings(snapshot: ProviderSnapshot) throws -> (SettingsView, String, UserDefaults) {
        let defaultsName = "ClaudeConnectionCardLayout.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        let configuration = ModuleConfiguration(defaults: defaults)
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        let presentation = SettingsClaudeQuotaPresentation(snapshot: CombinedUsageSnapshot(
            system: nil,
            providers: [snapshot],
            capturedAt: now,
            systemAvailability: [:]
        ), now: now)
        let view = SettingsView(
            configuration: configuration,
            actions: SettingsActions(),
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(store: ProviderSnapshotStore(), preferences: preferences),
            openCursorSpending: {},
            claudeQuotaPresentation: presentation
        )
        return (view, defaultsName, defaults)
    }

    private static func lastKnownSnapshot() throws -> ProviderSnapshot {
        let lastSuccess = now.addingTimeInterval(-86_400)
        let windows = try [
            QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: now.addingTimeInterval(3_600)),
            QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 53, resetsAt: now.addingTimeInterval(604_800)),
            QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 42, resetsAt: now.addingTimeInterval(604_800)),
        ]
        return ProviderSnapshot(
            provider: .claude,
            usage: nil,
            quota: QuotaSnapshot(windows: windows),
            usageStatus: .unavailable,
            quotaStatus: .error(message: "fixture only", lastSuccessfulAt: lastSuccess),
            updatedAt: now,
            claudeQuotaFailureReason: .couldNotUpdateQuota,
            quotaLastSuccessfulAt: lastSuccess
        )
    }

    private static func freshSnapshot() throws -> ProviderSnapshot {
        let windows = try [
            QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68, resetsAt: now.addingTimeInterval(3_600)),
            QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 53, resetsAt: now.addingTimeInterval(604_800)),
            QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 42, resetsAt: now.addingTimeInterval(604_800)),
        ]
        return ProviderSnapshot(
            provider: .claude,
            usage: nil,
            quota: QuotaSnapshot(windows: windows),
            usageStatus: .unavailable,
            quotaStatus: .fresh,
            updatedAt: now,
            quotaLastSuccessfulAt: now
        )
    }

    private static func card(_ settings: SettingsView) -> some View {
        SettingsStudioSection(title: "Connection") {
            settings.claudeUsageRow
        }
    }

    private static func fittingSize<Content: View>(of content: Content) -> CGSize {
        let host = NSHostingView(rootView: content)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private static func render<Content: View>(
        _ content: Content,
        name: String,
        width: CGFloat,
        appearance: NSAppearance.Name
    ) throws {
        _ = NSApplication.shared
        let root = content
            .frame(width: width, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        let frame = NSRect(x: 0, y: 0, width: width, height: max(1, host.fittingSize.height))
        host.frame = frame
        let nativeAppearance = try #require(NSAppearance(named: appearance))
        host.appearance = nativeAppearance
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = nativeAppearance
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        for _ in 0..<6 {
            window.display()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width),
            pixelsHigh: max(1, Int(frame.height.rounded(.up))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: "/tmp/needlbar-claude-connection-card-review", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
}
