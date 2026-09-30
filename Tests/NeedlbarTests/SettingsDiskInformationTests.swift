import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarSettingsStudioReviewSupport

@Suite("SettingsDiskInformation")
@MainActor
struct SettingsDiskInformationTests {
    static let time = Date(timeIntervalSince1970: 1_790_755_200)

    @Test func actualVolumeCapacityAndIndependentRatesUseSuccessfulTime() {
        let value = SettingsDiskInformationPresentation(snapshot: Self.snapshot()).value
        #expect(value.name == "Macintosh HD")
        #expect(value.totalBytes == 1_099_511_627_776)
        #expect(value.usedBytes == 824_633_720_832)
        #expect(value.availableBytes == 274_877_906_944)
        #expect(value.usedPercent == 75)
        #expect(value.readBytesPerSecond == 12_582_912)
        #expect(value.writeBytesPerSecond == 3_145_728)
        #expect(value.successfulAt == Self.time)
        #expect(value.status == .fresh(capturedAt: Self.time))
    }

    @Test func staleUsesSuccessfulDateAcrossDaysAndRetainsWholeRecord() {
        let first = SettingsDiskInformationPresentation(snapshot: Self.snapshot(availability: .stale(lastSuccessfulAt: Self.time)))
        let nextDay = SettingsDiskInformationPresentation(snapshot: Self.snapshot(availability: .stale(lastSuccessfulAt: Self.time.addingTimeInterval(86400))))
        #expect(first.value.status == .stale(lastSuccessfulAt: Self.time))
        #expect(first.value.successfulAt == Self.time)
        #expect(first.value.usedBytes == 824_633_720_832)
        #expect(first.value.availableBytes == 274_877_906_944)
        #expect(first.value.usedPercent == 75)
        #expect(first.value.readBytesPerSecond == 12_582_912)
        #expect(first.value.writeBytesPerSecond == 3_145_728)
        let text = SettingsDiskInformationView(presentation: first).freshnessText
        #expect(text.contains("Last known"))
        #expect(text.contains(Self.time.formatted(date: .abbreviated, time: .shortened)))
        #expect(!text.contains(Self.time.addingTimeInterval(60).formatted(date: .abbreviated, time: .shortened)))
        #expect(text != SettingsDiskInformationView(presentation: nextDay).freshnessText)
    }

    @Test func unknownTotalIsNotInferredAndZeroCapacitySuppressesDynamics() {
        let old = SettingsDiskInformationPresentation(snapshot: Self.snapshot(total: nil)).value
        #expect(old.totalBytes == nil)
        #expect(old.usedPercent == 75)
        let invalid = SettingsDiskInformationPresentation(snapshot: Self.snapshot(total: 0)).value
        #expect(invalid.totalBytes == nil)
        Self.expectUnavailableDynamics(invalid)
        let emptyUsed = SettingsDiskInformationPresentation(snapshot: Self.snapshot(total: 100, used: 0, available: 100)).value
        #expect(emptyUsed.usedBytes == 0)
        #expect(emptyUsed.usedPercent == 0)
        let full = SettingsDiskInformationPresentation(snapshot: Self.snapshot(total: 100, used: 100, available: 0)).value
        #expect(full.availableBytes == 0)
        #expect(full.usedPercent == 100)
    }

    @Test func unsupportedPercentageDoesNotEraseSupportedUsedOrRates() {
        for snapshot in [Self.snapshot(available: nil), Self.snapshot(total: nil, used: 0, available: 0), Self.snapshot(total: nil, used: UInt64.max, available: 1), Self.snapshot(total: 100, used: 80, available: 19)] {
            let value = SettingsDiskInformationPresentation(snapshot: snapshot).value
            #expect(value.usedPercent == nil)
            #expect(value.usedBytes != nil)
            #expect(value.readBytesPerSecond == 12_582_912)
            #expect(value.successfulAt == Self.time)
        }
        let excessive = SettingsDiskInformationPresentation(snapshot: Self.snapshot(total: 100, used: 80, available: 101)).value
        #expect(excessive.availableBytes == nil)
        #expect(excessive.usedPercent == nil)
        #expect(excessive.usedBytes == 80)
        for used: UInt64? in [nil, 101] {
            let value = SettingsDiskInformationPresentation(snapshot: Self.snapshot(total: 100, used: used, availability: .stale(lastSuccessfulAt: Self.time))).value
            #expect(value.totalBytes == 100)
            Self.expectUnavailableDynamics(value)
        }
    }

    @Test func unavailableMissingAvailabilityAndRecordTransitionsDoNotCache() {
        let presentation = SettingsDiskInformationPresentation(snapshot: Self.snapshot())
        for availability: MetricAvailability? in [.unavailable(code: "diskUnavailable"), nil] {
            presentation.update(snapshot: Self.snapshot(name: "Current name", total: 100, availability: availability))
            #expect(presentation.value.name == "Current name")
            #expect(presentation.value.totalBytes == 100)
            Self.expectUnavailableDynamics(presentation.value)
        }
        for missing in [Self.snapshot(hasDisk: false, availability: .stale(lastSuccessfulAt: Self.time)), CombinedUsageSnapshot(system: nil, providers: [], capturedAt: Self.time, systemAvailability: [.disk: .stale(lastSuccessfulAt: Self.time)])] {
            presentation.update(snapshot: missing)
            #expect(presentation.value.name == nil)
            #expect(presentation.value.totalBytes == nil)
            Self.expectUnavailableDynamics(presentation.value)
        }
        presentation.update(snapshot: Self.snapshot())
        #expect(presentation.value.usedPercent == 75)
        presentation.update(snapshot: Self.snapshot(total: nil, used: nil, availability: .stale(lastSuccessfulAt: Self.time)))
        Self.expectUnavailableDynamics(presentation.value)
    }

    @Test func rateZerosAndMissingDirectionsRemainIndependent() {
        for (read, write) in [(UInt64(0), UInt64(0)), (nil, UInt64(0)), (UInt64(0), nil), (nil, nil)] as [(UInt64?, UInt64?)] {
            let presentation = SettingsDiskInformationPresentation(snapshot: Self.snapshot(read: read, write: write))
            #expect(presentation.value.readBytesPerSecond == read)
            #expect(presentation.value.writeBytesPerSecond == write)
            #expect(presentation.value.usedPercent == 75)
        }
        #expect(SettingsDiskInformationView.rateText(0) == "0 B/s")
        #expect(SettingsDiskInformationView.rateText(nil) == "—")
        #expect(SettingsDiskInformationView.rateText(12_582_912) == "12.0 MiB/s")
    }

    @Test func volumeLabelsAreTrimmedOrSafelyReplacedWithoutErasingValues() {
        let long = String(repeating: "Long system volume name ", count: 10).trimmingCharacters(in: .whitespacesAndNewlines)
        for (raw, expected) in [("  Macintosh HD  ", "Macintosh HD"), (" \n ", "System volume"), ("Bad\u{0007}name", "System volume"), ("Bad\nname", "System volume"), (long, long)] {
            let value = SettingsDiskInformationPresentation(snapshot: Self.snapshot(name: raw)).value
            #expect(value.name == expected)
            #expect(value.usedPercent == 75)
        }
    }

    @Test func reviewFixtureAddsDiskWithoutChangingCPUOrRAM() {
        let snapshot = SettingsStudioReviewFixtures.cpuSnapshot()
        let value = SettingsDiskInformationPresentation(snapshot: snapshot).value
        #expect(value.name == "Macintosh HD")
        #expect(value.totalBytes == 1_099_511_627_776)
        #expect(value.usedPercent == 75)
        #expect(value.readBytesPerSecond == 12_582_912)
        #expect(value.writeBytesPerSecond == 3_145_728)
        #expect(snapshot.systemAvailability[.disk] == .fresh(capturedAt: Self.time))
        #expect(snapshot.system?.cpu.totalUsage?.value == 25)
        #expect(snapshot.system?.memory.totalBytes == 51_539_607_552)
    }

    @Test func attachedNativeDiskCardRendersLightMinimumLongNameStaleAndUnavailable() throws {
        let fixtures: [(String, CGFloat, NSAppearance.Name, CombinedUsageSnapshot)] = [
            ("light-normal", 677, .aqua, Self.snapshot()),
            ("dark-minimum", 477, .darkAqua, Self.snapshot()),
            ("long-name", 477, .darkAqua, Self.snapshot(name: String(repeating: "Long Macintosh HD volume name ", count: 5))),
            ("stale", 477, .darkAqua, Self.snapshot(availability: .stale(lastSuccessfulAt: Self.time))),
            ("unavailable", 477, .darkAqua, Self.snapshot(availability: .unavailable(code: "diskUnavailable")))
        ]
        for (name, width, appearance, snapshot) in fixtures {
            let bitmap = try Self.render(snapshot: snapshot, width: width, appearance: appearance)
            #expect(bitmap.pixelsWide == Int(width))
            #expect(bitmap.pixelsHigh > 0)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let directory = URL(fileURLWithPath: "/tmp/needlbar-disk-settings-review", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
        }
    }

    private static func expectUnavailableDynamics(_ value: SettingsDiskInformationValue) {
        #expect(value.usedBytes == nil)
        #expect(value.availableBytes == nil)
        #expect(value.usedPercent == nil)
        #expect(value.readBytesPerSecond == nil)
        #expect(value.writeBytesPerSecond == nil)
        #expect(value.successfulAt == nil)
        #expect(value.status == .unavailable)
    }

    private static func render(snapshot: CombinedUsageSnapshot, width: CGFloat, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let content = SettingsDiskInformationView(presentation: SettingsDiskInformationPresentation(snapshot: snapshot))
            .frame(width: width, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor))
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
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: max(1, Int(frame.height.rounded(.up))), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    static func snapshot(name: String = "Macintosh HD", total: UInt64? = 1_099_511_627_776, used: UInt64? = 824_633_720_832, available: UInt64? = 274_877_906_944, read: UInt64? = 12_582_912, write: UInt64? = 3_145_728, hasDisk: Bool = true, availability: MetricAvailability? = .fresh(capturedAt: time)) -> CombinedUsageSnapshot {
        let entries: [MonitorModuleID: MetricAvailability] = availability.map { [.disk: $0] } ?? [:]
        let attempt = time.addingTimeInterval(60)
        let disk = SystemMetricsSnapshot.DiskVolume(name: name, usedBytes: used, freeBytes: available, readBytesPerSecond: read, writeBytesPerSecond: write, totalBytes: total)
        let system = SystemMetricsSnapshot(capturedAt: attempt, cpu: .init(totalUsage: nil, perCoreUsage: []), memory: .init(usedBytes: nil, freeBytes: nil, swapUsedBytes: nil, pressure: nil), disks: hasDisk ? [disk] : [], network: .init(uploadBytesPerSecond: nil, downloadBytesPerSecond: nil, localIPAddresses: [], publicIPAddress: nil), battery: .init(level: nil, isCharging: nil, health: nil), availability: entries)
        return CombinedUsageSnapshot(system: system, providers: [], capturedAt: attempt, systemAvailability: entries)
    }
}
