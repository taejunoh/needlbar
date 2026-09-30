import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarSettingsStudioReviewSupport

@Suite("SettingsRAMInformation")
@MainActor
struct SettingsRAMInformationTests {
    static let gib: UInt64 = 1_073_741_824
    static let time = Date(timeIntervalSince1970: 1_790_755_200)

    @Test func physicalCapacityAndOverlappingDetailsDoNotInflateUsedPercentage() {
        let value = SettingsRAMInformationPresentation(snapshot: Self.snapshot()).value
        #expect(value.totalBytes == 51_539_607_552)
        #expect(value.usedBytes == 38_654_705_664)
        #expect(value.availableBytes == 12_884_901_888)
        #expect(value.compressedBytes == 8_589_934_592)
        #expect(value.wiredBytes == 6_442_450_944)
        #expect(value.swapUsedBytes == 2_147_483_648)
        #expect(value.usedPercent == 75)
        #expect(value.pressure == "normal")
        #expect(value.successfulAt == Self.time)
    }

    @Test func zerosRemainRealAndUnknownCapacityIsNotInferred() {
        let zero = SettingsRAMInformationPresentation(snapshot: Self.snapshot(used: 0, available: 48 * Self.gib, compressed: 0, wired: 0, swap: 0)).value
        #expect(zero.usedPercent == 0)
        #expect(zero.compressedBytes == 0)
        #expect(zero.wiredBytes == 0)
        #expect(zero.swapUsedBytes == 0)
        let old = SettingsRAMInformationPresentation(snapshot: Self.snapshot(total: nil)).value
        #expect(old.totalBytes == nil)
        #expect(old.usedPercent == 75)
    }

    @Test func staleUsesSuccessfulDateAndDatesWithSameTimeRemainDistinct() {
        let first = SettingsRAMInformationPresentation(snapshot: Self.snapshot(availability: .stale(lastSuccessfulAt: Self.time)))
        let nextDay = Self.time.addingTimeInterval(86400)
        let second = SettingsRAMInformationPresentation(snapshot: Self.snapshot(availability: .stale(lastSuccessfulAt: nextDay)))
        #expect(first.value.successfulAt == Self.time)
        #expect(first.value.status == .stale(lastSuccessfulAt: Self.time))
        #expect(first.value.pressure == "normal")
        #expect(first.value.usedPercent == 75)
        #expect(first.value.usedBytes == 36 * Self.gib)
        #expect(first.value.availableBytes == 12 * Self.gib)
        #expect(first.value.compressedBytes == 8 * Self.gib)
        #expect(first.value.wiredBytes == 6 * Self.gib)
        #expect(first.value.swapUsedBytes == 2 * Self.gib)
        #expect(SettingsRAMInformationView(presentation: first).freshnessText.contains("Last known"))
        #expect(SettingsRAMInformationView(presentation: first).freshnessText.contains(Self.time.formatted(date: .abbreviated, time: .shortened)))
        #expect(!SettingsRAMInformationView(presentation: first).freshnessText.contains(Self.time.addingTimeInterval(60).formatted(date: .abbreviated, time: .shortened)))
        #expect(SettingsRAMInformationView(presentation: first).freshnessText != SettingsRAMInformationView(presentation: second).freshnessText)
    }

    @Test func unavailableOrMissingAvailabilityClearsOrphansAndPriorDynamics() {
        let presentation = SettingsRAMInformationPresentation(snapshot: Self.snapshot())
        for availability: MetricAvailability? in [.unavailable(code: "memoryUnavailable"), nil] {
            presentation.update(snapshot: Self.snapshot(availability: availability))
            let value = presentation.value
            #expect(value.totalBytes == 51_539_607_552)
            #expect(value.usedBytes == nil)
            #expect(value.availableBytes == nil)
            #expect(value.compressedBytes == nil)
            #expect(value.wiredBytes == nil)
            #expect(value.swapUsedBytes == nil)
            #expect(value.pressure == nil)
            #expect(value.usedPercent == nil)
            #expect(value.successfulAt == nil)
            #expect(value.status == .unavailable)
        }
        let empty = CombinedUsageSnapshot(system: nil, providers: [], capturedAt: Self.time, systemAvailability: [:])
        #expect(SettingsRAMInformationPresentation(snapshot: empty).value.totalBytes == nil)
        #expect(SettingsRAMInformationPresentation(snapshot: empty).value.status == .unavailable)
    }

    @Test func incompleteOrInvalidArithmeticSuppressesOnlyUnsupportedValues() {
        for snapshot in [Self.snapshot(available: nil), Self.snapshot(total: nil, used: 0, available: 0), Self.snapshot(total: nil, used: UInt64.max, available: 1), Self.snapshot(available: 11 * Self.gib)] {
            let value = SettingsRAMInformationPresentation(snapshot: snapshot).value
            #expect(value.usedPercent == nil)
            #expect(value.usedBytes != nil)
        }
        let invalidAvailable = SettingsRAMInformationPresentation(snapshot: Self.snapshot(available: 49 * Self.gib)).value
        #expect(invalidAvailable.availableBytes == nil)
        #expect(invalidAvailable.usedBytes == 36 * Self.gib)
        for used: UInt64? in [nil, 49 * Self.gib] {
            let value = SettingsRAMInformationPresentation(snapshot: Self.snapshot(used: used, availability: .stale(lastSuccessfulAt: Self.time))).value
            #expect(value.totalBytes == 48 * Self.gib)
            #expect(value.usedBytes == nil)
            #expect(value.successfulAt == nil)
            #expect(value.status == .unavailable)
        }
    }

    @Test func pressureIsIndependentAndDetailsAreValidatedIndividually() {
        for (raw, normalized) in [(nil, nil), ("normal", "normal"), ("warning", "warning"), ("critical", "critical"), ("invalid", nil)] as [(String?, String?)] {
            let value = SettingsRAMInformationPresentation(snapshot: Self.snapshot(pressure: raw)).value
            #expect(value.pressure == normalized)
            #expect(value.usedPercent == 75)
        }
        let high = SettingsRAMInformationPresentation(snapshot: Self.snapshot(used: 47 * Self.gib, available: Self.gib)).value
        #expect(high.pressure == "normal")
        let details = SettingsRAMInformationPresentation(snapshot: Self.snapshot(compressed: 49 * Self.gib, wired: nil, swap: 60 * Self.gib)).value
        #expect(details.compressedBytes == nil)
        #expect(details.wiredBytes == nil)
        #expect(details.swapUsedBytes == 60 * Self.gib)
        #expect(details.usedPercent == 75)
        let invalidWired = SettingsRAMInformationPresentation(snapshot: Self.snapshot(compressed: nil, wired: 49 * Self.gib, swap: nil)).value
        #expect(invalidWired.wiredBytes == nil)
        #expect(invalidWired.compressedBytes == nil)
        #expect(invalidWired.swapUsedBytes == nil)
        #expect(invalidWired.usedBytes == 36 * Self.gib)
        #expect(SettingsRAMInformationPresentation(snapshot: Self.snapshot(total: 0)).value.totalBytes == nil)
    }

    @Test func reviewFixtureIncludesFreshRAMAlongsideUnchangedCPU() {
        let snapshot = SettingsStudioReviewFixtures.cpuSnapshot()
        #expect(snapshot.system?.memory.totalBytes == 48 * Self.gib)
        #expect(snapshot.system?.memory.usedBytes == 36 * Self.gib)
        #expect(snapshot.systemAvailability[.memory] == .fresh(capturedAt: Self.time))
        #expect(snapshot.system?.cpu.totalUsage?.value == 25)
    }

    @Test func attachedNativeRAMCardRendersNormalMinimumStaleAndUnavailableFixtures() throws {
        let fixtures: [(String, Double, NSAppearance.Name, CombinedUsageSnapshot)] = [
            ("light-normal", 677, .aqua, Self.snapshot()),
            ("dark-minimum", 477, .darkAqua, Self.snapshot()),
            ("stale-critical", 477, .darkAqua, Self.snapshot(pressure: "critical", availability: .stale(lastSuccessfulAt: Self.time))),
            ("unavailable", 477, .darkAqua, Self.snapshot(availability: .unavailable(code: "memoryUnavailable")))
        ]
        for (name, width, appearance, snapshot) in fixtures {
            let bitmap = try Self.render(snapshot: snapshot, width: width, appearance: appearance)
            #expect(bitmap.pixelsWide == Int(width))
            #expect(bitmap.pixelsHigh > 0)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let directory = URL(fileURLWithPath: "/tmp/needlbar-ram-settings-review", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
        }
    }

    private static func render(snapshot: CombinedUsageSnapshot, width: CGFloat, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let content = SettingsRAMInformationView(presentation: SettingsRAMInformationPresentation(snapshot: snapshot))
            .frame(width: width, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: content)
        let frame = NSRect(x: 0, y: 0, width: width, height: hosting.fittingSize.height)
        hosting.frame = frame
        let nativeAppearance = try #require(NSAppearance(named: appearance))
        hosting.appearance = nativeAppearance
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = nativeAppearance
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        for _ in 0..<6 {
            window.display()
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width),
            pixelsHigh: max(1, Int(frame.height.rounded(.up))), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    static func snapshot(total: UInt64? = 48 * gib, used: UInt64? = 36 * gib, available: UInt64? = 12 * gib, compressed: UInt64? = 8 * gib, wired: UInt64? = 6 * gib, swap: UInt64? = 2 * gib, pressure: String? = "normal", availability: MetricAvailability? = .fresh(capturedAt: time)) -> CombinedUsageSnapshot {
        let entries: [MonitorModuleID: MetricAvailability] = availability.map { [.memory: $0] } ?? [:]
        let attempt = time.addingTimeInterval(60)
        let system = SystemMetricsSnapshot(capturedAt: attempt, cpu: .init(totalUsage: nil, perCoreUsage: []), memory: .init(usedBytes: used, freeBytes: available, swapUsedBytes: swap, pressure: pressure, totalBytes: total, compressedBytes: compressed, wiredBytes: wired), disks: [], network: .init(uploadBytesPerSecond: nil, downloadBytesPerSecond: nil, localIPAddresses: [], publicIPAddress: nil), battery: .init(level: nil, isCharging: nil, health: nil), availability: entries)
        return CombinedUsageSnapshot(system: system, providers: [], capturedAt: attempt, systemAvailability: entries)
    }
}
