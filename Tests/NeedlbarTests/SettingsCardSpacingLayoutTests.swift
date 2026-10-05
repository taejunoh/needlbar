import AppKit
import Foundation
import NeedlbarCore
import NeedlbarClaudeStatusLineSupport
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarSettingsStudioReviewSupport

@Suite("SettingsCardSpacingLayout", .serialized)
@MainActor
struct SettingsCardSpacingLayoutTests {
    @Test func sharedSettingsCardAddsApprovedEdgeClearance() {
        let content = Color.clear.frame(width: 240, height: 60)
        let card = SettingsStudioCard { content }

        let contentSize = Self.fittingSize(of: content)
        let cardSize = Self.fittingSize(of: card)

        #expect(abs((cardSize.width - contentSize.width) - 48) < 1)
        #expect(abs((cardSize.height - contentSize.height) - 40) < 1)
    }

    @Test func settingsStateMatrixRendersInBothAppearancesAndWindowSizes() throws {
        _ = NSApplication.shared
        let states = Self.states
        let fixture = try Self.fixture()
        defer { fixture.cleanup() }
        let directory = URL(fileURLWithPath: "/tmp/needlbar-settings-spacing-review/final", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        for (sizeName, size) in [("default-960x720", NSSize(width: 960, height: 720)),
                                  ("minimum-760x560", NSSize(width: 760, height: 560))] {
            for (appearanceName, appearance) in [("aqua", NSAppearance.Name.aqua),
                                                   ("dark-aqua", NSAppearance.Name.darkAqua)] {
                var tiles: [(String, NSImage)] = []
                for (page, tab, label) in states {
                    let image = try Self.capture(
                        fixture.settings.settingsWindowContent(page: .constant(page), tab: .constant(tab)),
                        size: size,
                        appearance: appearance
                    )
                    let name = "\(Self.slug(label))_\(sizeName)_\(appearanceName)"
                    try Self.write(image, to: directory.appendingPathComponent("\(name).png"))
                    tiles.append((label, image))
                }
                let contactSheet = Self.contactSheet(tiles: tiles)
                try Self.write(
                    contactSheet,
                    to: directory.appendingPathComponent("contact_\(sizeName)_\(appearanceName).png")
                )
            }
        }
        #expect(states.count == 28)
    }

    @Test func narrowDetailBodiesWrapLongAndMissingContentAtSupportedWidth() throws {
        _ = NSApplication.shared
        let fixture = try Self.fixture()
        defer { fixture.cleanup() }
        let directory = URL(fileURLWithPath: "/tmp/needlbar-settings-spacing-review/final/detail-bodies", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [(SettingsStudioPage, SettingsStudioTab, String)] = [
            (.layout, .dashboard, "layout-full-order-lists"),
            (.module(.cpu), .menuBar, "cpu-system-card"),
            (.module(.memory), .dashboard, "ram-system-card"),
            (.module(.disk), .dashboard, "disk-system-card"),
            (.module(.network), .dashboard, "network-with-ip"),
            (.provider(.claude), .dashboard, "claude-connection-statusline-billing"),
            (.provider(.codex), .dashboard, "codex-connection-billing"),
            (.provider(.cursor), .dashboard, "cursor-connection"),
            (.notifications, .menuBar, "notifications"),
            (.data, .menuBar, "export-idle"),
        ]
        for (page, tab, name) in cases {
            let content = fixture.settings.settingsDetailContent(page: page, tab: .constant(tab))
            for (appearanceName, appearance) in [("aqua", NSAppearance.Name.aqua),
                                                   ("dark-aqua", NSAppearance.Name.darkAqua)] {
                let image = try Self.captureIntrinsic(content, width: 491, appearance: appearance)
                #expect(image.size.width == 491)
                #expect(image.size.height > 100)
                try Self.write(image, to: directory.appendingPathComponent("\(name)_491_\(appearanceName).png"))
            }
        }

        let missing = try Self.fixture(snapshot: nil)
        defer { missing.cleanup() }
        for (page, name) in [
            (SettingsStudioPage.module(.cpu), "cpu-missing"),
            (.module(.memory), "ram-missing"),
            (.module(.disk), "disk-missing"),
            (.module(.network), "network-missing"),
        ] {
            let content = missing.settings.settingsDetailContent(page: page, tab: .constant(.dashboard))
            let image = try Self.captureIntrinsic(content, width: 491, appearance: .aqua)
            #expect(image.size.height > 100)
            try Self.write(image, to: directory.appendingPathComponent("\(name)_491_aqua.png"))
        }

        let long = try Self.fixture(snapshot: Self.longSnapshot())
        defer { long.cleanup() }
        for (page, name) in [
            (SettingsStudioPage.module(.cpu), "cpu-long-labels"),
            (.module(.disk), "disk-long-volume-name"),
            (.module(.network), "network-long-interface-list"),
        ] {
            let image = try Self.captureIntrinsic(
                long.settings.settingsDetailContent(page: page, tab: .constant(.dashboard)),
                width: 491,
                appearance: .aqua
            )
            #expect(image.size.height > 350)
            try Self.write(image, to: directory.appendingPathComponent("\(name)_491_aqua.png"))
        }

        let layoutBody = try Self.captureIntrinsic(
            fixture.settings.settingsDetailContent(page: .layout, tab: .constant(.dashboard)),
            width: 491,
            appearance: .aqua
        )
        #expect(layoutBody.size.height > 560)
    }

    @Test func exportFeedbackRendersForSyntheticSuccessAndFailure() async throws {
        _ = NSApplication.shared
        let actions = settingsStudioReviewActions(delay: .zero)
        let fixture = try Self.fixture(actions: actions)
        defer { fixture.cleanup() }
        let directory = URL(fileURLWithPath: "/tmp/needlbar-settings-spacing-review/final/export-feedback", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        actions.exportSnapshot()
        try await Self.waitForExportState(.exported, actions: actions)
        #expect(actions.exportState == .exported)
        let success = try Self.captureIntrinsic(
            fixture.settings.settingsDetailContent(page: .data, tab: .constant(.menuBar)),
            width: 491, appearance: .aqua
        )
        try Self.write(success, to: directory.appendingPathComponent("export-success_491_aqua.png"))

        actions.exportSnapshot()
        try await Self.waitForExportState(.failed, actions: actions)
        #expect(actions.exportState == .failed)
        let failure = try Self.captureIntrinsic(
            fixture.settings.settingsDetailContent(page: .data, tab: .constant(.menuBar)),
            width: 491, appearance: .darkAqua
        )
        try Self.write(failure, to: directory.appendingPathComponent("export-failure_491_dark-aqua.png"))
    }

    private static func fittingSize<Content: View>(of content: Content) -> CGSize {
        let host = NSHostingView(rootView: content)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private static var states: [(SettingsStudioPage, SettingsStudioTab, String)] {
        var result: [(SettingsStudioPage, SettingsStudioTab, String)] = []
        for tab in [SettingsStudioTab.menuBar, .dashboard] {
            result.append((.layout, tab, "Layout · \(tab.rawValue)"))
        }
        for module in [MonitorModuleID.cpu, .memory, .disk, .network, .battery] {
            for tab in SettingsStudioTab.allCases {
                result.append((.module(module), tab, "\(module.title) · \(tab.rawValue)"))
            }
        }
        for provider in ProviderID.allCases {
            for tab in SettingsStudioTab.allCases {
                result.append((.provider(provider), tab, "\(provider.displayName) · \(tab.rawValue)"))
            }
        }
        result.append((.notifications, .menuBar, "Notifications"))
        result.append((.data, .menuBar, "Data & Privacy"))
        return result
    }

    private struct Fixture {
        let settings: SettingsView
        let defaultsName: String
        let defaults: UserDefaults
        let root: URL

        func cleanup() {
            defaults.removePersistentDomain(forName: defaultsName)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private static func fixture(
        snapshot: CombinedUsageSnapshot? = SettingsStudioReviewFixtures.freshNetworkSnapshot(),
        actions: SettingsActions = SettingsActions()
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeedlbarSettingsSpacingFixture-\(UUID().uuidString)", isDirectory: true)
        let defaultsName = "SettingsCardSpacingLayout.\(UUID().uuidString)"
        var defaultsForCleanup: UserDefaults?
        var ownershipTransferred = false
        defer {
            if !ownershipTransferred {
                if let defaultsForCleanup {
                    defaultsForCleanup.removePersistentDomain(forName: defaultsName)
                }
                try? FileManager.default.removeItem(at: root)
            }
        }
        let configRootURL = root.appendingPathComponent("claude", isDirectory: true)
        try FileManager.default.createDirectory(at: configRootURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: configRootURL.path)

        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defaultsForCleanup = defaults
        defaults.set(true, forKey: "needlbar.systemMonitor.localIP")
        defaults.set(true, forKey: "needlbar.systemMonitor.publicIP")
        let configuration = ModuleConfiguration(defaults: defaults)
        let preferences = QuotaNotificationPreferences(defaults: defaults)
        let statusLineStore = try StatusLinePrivateStore(rootURL: root.appendingPathComponent("private", isDirectory: true))
        let settings = SettingsView(
            configuration: configuration,
            actions: actions,
            notificationPreferences: preferences,
            notificationService: QuotaNotificationService(
                store: ProviderSnapshotStore(), preferences: preferences,
                client: SettingsStudioInertNotificationClient()
            ),
            openCursorSpending: {},
            openClaudeUsage: { false },
            claudeStatusLineManager: ClaudeStatusLineConnectionManager(
                configRootURL: configRootURL,
                store: statusLineStore,
                helperURL: root.appendingPathComponent("NeedlbarClaudeStatusLine"),
                environment: [:]
            ),
            claudeQuotaPresentation: SettingsClaudeQuotaPresentation(snapshot: try Self.claudeSnapshot()),
            cpuInformationPresentation: SettingsCPUInformationPresentation(snapshot: snapshot),
            ramInformationPresentation: SettingsRAMInformationPresentation(snapshot: snapshot),
            diskInformationPresentation: SettingsDiskInformationPresentation(snapshot: snapshot),
            networkInformationPresentation: SettingsNetworkInformationPresentation(snapshot: snapshot)
        )
        ownershipTransferred = true
        return Fixture(settings: settings, defaultsName: defaultsName, defaults: defaults, root: root)
    }

    private static func claudeSnapshot() throws -> CombinedUsageSnapshot {
        let now = Date(timeIntervalSince1970: 1_790_755_200)
        let lastSuccess = now.addingTimeInterval(-86_400)
        let windows = try [
            QuotaWindow(id: "claude.session", title: "Session", usedPercent: 68,
                        resetsAt: now.addingTimeInterval(3_600)),
            QuotaWindow(id: "claude.weekly", title: "Weekly", usedPercent: 53,
                        resetsAt: now.addingTimeInterval(604_800)),
            QuotaWindow(id: QuotaWindow.claudeFableWeeklyID, title: "Fable weekly", usedPercent: 42,
                        resetsAt: now.addingTimeInterval(604_800)),
        ]
        let provider = ProviderSnapshot(
            provider: .claude, usage: nil, quota: QuotaSnapshot(windows: windows),
            usageStatus: .unavailable,
            quotaStatus: .error(message: "Fixture only", lastSuccessfulAt: lastSuccess),
            updatedAt: now, claudeQuotaFailureReason: .couldNotUpdateQuota,
            quotaLastSuccessfulAt: lastSuccess
        )
        return CombinedUsageSnapshot(system: nil, providers: [provider], capturedAt: now, systemAvailability: [:])
    }

    private static func longSnapshot() -> CombinedUsageSnapshot {
        let base = SettingsStudioReviewFixtures.freshNetworkSnapshot()
        let system = base.system!
        let capturedAt = system.capturedAt
        let cpu = SystemMetricsSnapshot.CPU(
            totalUsage: system.cpu.totalUsage,
            perCoreUsage: system.cpu.perCoreUsage,
            hardware: CPUHardwareInfo(
                name: String(repeating: "Apple M5 Pro Max · ", count: 4),
                physicalCoreCount: 15,
                logicalCoreCount: 15,
                coreGroups: [CPUHardwareInfo.CoreGroup(
                    name: String(repeating: "Performance cluster ", count: 5), physicalCoreCount: 15
                )!]
            )
        )
        let disk = SystemMetricsSnapshot.DiskVolume(
            name: String(repeating: "Macintosh HD System Volume ", count: 8),
            usedBytes: 824_633_720_832,
            freeBytes: 274_877_906_944,
            readBytesPerSecond: 12_582_912,
            writeBytesPerSecond: 3_145_728,
            totalBytes: 1_099_511_627_776
        )
        let network = SystemMetricsSnapshot.Network(
            uploadBytesPerSecond: 131_072,
            downloadBytesPerSecond: 1_048_576,
            localIPAddresses: ["192.0.2.10", "2001:db8::10"],
            publicIPAddress: "198.51.100.10",
            interfaceNames: (1...16).map { "virtual-interface-name-\($0)-long" }
        )
        let longSystem = SystemMetricsSnapshot(
            capturedAt: capturedAt, cpu: cpu, memory: system.memory, disks: [disk], network: network,
            battery: system.battery, availability: system.availability
        )
        return CombinedUsageSnapshot(
            system: longSystem, providers: base.providers, capturedAt: base.capturedAt,
            systemAvailability: base.systemAvailability
        )
    }

    private static func capture<Content: View>(
        _ content: Content,
        size: NSSize,
        appearance: NSAppearance.Name
    ) throws -> NSImage {
        let nativeAppearance = try #require(NSAppearance(named: appearance))
        let frame = NSRect(origin: .zero, size: size)
        let root = content
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.frame = frame
        host.appearance = nativeAppearance
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = nativeAppearance
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        for _ in 0..<4 {
            window.display()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return NSImage(cgImage: try #require(bitmap.cgImage), size: size)
    }

    private static func captureIntrinsic<Content: View>(
        _ content: Content,
        width: CGFloat,
        appearance: NSAppearance.Name
    ) throws -> NSImage {
        let nativeAppearance = try #require(NSAppearance(named: appearance))
        let root = content
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingView(rootView: root)
        host.appearance = nativeAppearance
        host.layoutSubtreeIfNeeded()
        let height = max(1, host.fittingSize.height)
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = nativeAppearance
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        for _ in 0..<4 {
            window.display()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(width),
            pixelsHigh: max(1, Int(height.rounded(.up))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return NSImage(cgImage: try #require(bitmap.cgImage), size: NSSize(width: width, height: height))
    }

    @MainActor
    private static func waitForExportState(
        _ expected: SnapshotExportState,
        actions: SettingsActions
    ) async throws {
        for _ in 0..<200 {
            if actions.exportState == expected { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(actions.exportState == expected)
    }

    private static func write(_ image: NSImage, to url: URL) throws {
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: url, options: .atomic)
    }

    private static func contactSheet(tiles: [(String, NSImage)]) -> NSImage {
        let columns = 4
        let tileSize = NSSize(width: 260, height: 195)
        let labelHeight: CGFloat = 26
        let gutter: CGFloat = 12
        let rows = Int(ceil(Double(tiles.count) / Double(columns)))
        let size = NSSize(
            width: CGFloat(columns) * (tileSize.width + gutter) + gutter,
            height: CGFloat(rows) * (tileSize.height + labelHeight + gutter) + gutter
        )
        let sheet = NSImage(size: size)
        sheet.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        for (index, item) in tiles.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = gutter + CGFloat(column) * (tileSize.width + gutter)
            let y = size.height - gutter - CGFloat(row + 1) * (tileSize.height + labelHeight + gutter)
            item.1.draw(in: NSRect(x: x, y: y + labelHeight, width: tileSize.width, height: tileSize.height))
            (item.0 as NSString).draw(
                in: NSRect(x: x, y: y, width: tileSize.width, height: labelHeight),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.labelColor]
            )
        }
        sheet.unlockFocus()
        return sheet
    }

    private static func slug(_ string: String) -> String {
        string.lowercased().replacingOccurrences(of: " & ", with: "-")
            .replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "·", with: "-")
    }
}
