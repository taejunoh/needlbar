import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore
import NeedlbarSettingsStudioReviewSupport

@Suite("SettingsCPUInformation")
@MainActor
struct SettingsCPUInformationTests {
    @Test func freshUsageDerivesIdleAndPerCoreActivity() {
        let capturedAt = Date(timeIntervalSince1970: 40_000)
        let presentation = SettingsCPUInformationPresentation(snapshot: Self.snapshot(
            usage: 25,
            perCore: [10, 40, 25],
            availability: .fresh(capturedAt: capturedAt)
        ))

        #expect(presentation.value.totalUsagePercent == 25)
        #expect(presentation.value.idlePercent == 75)
        #expect(presentation.value.perCorePercents == [10, 40, 25])
        #expect(presentation.value.status == .fresh(capturedAt: capturedAt))
    }

    @Test func warmingUpDoesNotTurnHardwarePresenceIntoZeroActivity() {
        let presentation = SettingsCPUInformationPresentation(snapshot: Self.snapshot(
            usage: nil,
            perCore: [],
            availability: .unavailable(code: "cpuWarmingUp")
        ))

        #expect(presentation.value.hardware?.name == "Apple M5 Pro")
        #expect(presentation.value.status == .warmingUp)
        #expect(presentation.value.reason == "Waiting for the first CPU sample")
        #expect(presentation.value.totalUsagePercent == nil)
        #expect(presentation.value.idlePercent == nil)
        #expect(presentation.value.perCorePercents == nil)
    }

    @Test func staleUsageUsesLastSuccessfulSampleTimeInsteadOfSnapshotCaptureTime() {
        let lastSuccess = Date(timeIntervalSince1970: 50_000)
        let failedAttempt = Date(timeIntervalSince1970: 60_000)
        let presentation = SettingsCPUInformationPresentation(snapshot: Self.snapshot(
            usage: 25,
            perCore: [10, 40],
            availability: .stale(lastSuccessfulAt: lastSuccess),
            capturedAt: failedAttempt
        ))

        #expect(presentation.value.status == .stale(lastSuccessfulAt: lastSuccess))
        #expect(presentation.value.lastSuccessfulAt == lastSuccess)
        #expect(presentation.value.lastSuccessfulAt != failedAttempt)
        #expect(presentation.value.totalUsagePercent == 25)
        #expect(presentation.value.idlePercent == 75)
        #expect(presentation.value.perCorePercents == [10, 40])
    }

    @Test func unavailableCPUDoesNotExposeOrphanedActivityNumbers() {
        let presentation = SettingsCPUInformationPresentation(snapshot: Self.snapshot(
            usage: 25,
            perCore: [10, 40],
            availability: .unavailable(code: "cpuUnavailable")
        ))

        #expect(presentation.value.status == .unavailable)
        #expect(presentation.value.reason == "CPU information is unavailable")
        #expect(presentation.value.totalUsagePercent == nil)
        #expect(presentation.value.idlePercent == nil)
        #expect(presentation.value.perCorePercents == nil)
        #expect(presentation.value.hardware?.physicalCoreCount == 15)
    }

    @Test func missingSystemAndOptionalCPUFieldsStayEmpty() {
        let missingSystem = CombinedUsageSnapshot(
            system: nil,
            providers: [],
            capturedAt: .distantPast,
            systemAvailability: [.cpu: .unavailable(code: "cpuUnavailable")]
        )
        let missingFields = SettingsCPUInformationPresentation(snapshot: Self.snapshot(
            usage: nil,
            perCore: [],
            availability: .fresh(capturedAt: Date(timeIntervalSince1970: 70_000)),
            hardware: CPUHardwareInfo(name: nil, physicalCoreCount: nil, logicalCoreCount: nil)
        ))

        #expect(SettingsCPUInformationPresentation(snapshot: missingSystem).value.status == .unavailable)
        #expect(missingFields.value.hardware?.name == nil)
        #expect(missingFields.value.hardware?.physicalCoreCount == nil)
        #expect(missingFields.value.hardware?.logicalCoreCount == nil)
        #expect(missingFields.value.totalUsagePercent == nil)
        #expect(missingFields.value.idlePercent == nil)
        #expect(missingFields.value.perCorePercents == nil)
    }

    @Test func hostedCPUInformationRendersAtNarrowAndNormalDetailWidths() throws {
        let presentation = SettingsCPUInformationPresentation(snapshot: Self.snapshot(
            usage: 25,
            perCore: Array(repeating: 25, count: 15),
            availability: .fresh(capturedAt: Date(timeIntervalSince1970: 80_000))
        ))

        for (name, width, appearance) in [
            ("light-normal", 677.0, NSAppearance.Name.aqua),
            ("dark-minimum", 477.0, NSAppearance.Name.darkAqua),
        ] {
            let host = SettingsCPUInformationTestHost(presentation: presentation)
            let image = try host.render(width: width, appearance: appearance)
            #expect(image.pixelsWide == Int(width))
            #expect(image.pixelsHigh > 0)
            try host.writePNG(image, name: name)
        }
    }

    @Test func reviewFixtureKeepsDeterministicAppleSiliconCPUData() {
        let snapshot = SettingsStudioReviewFixtures.cpuSnapshot()
        let cpu = snapshot.system?.cpu

        #expect(cpu?.hardware?.name == "Apple M5 Pro")
        #expect(cpu?.hardware?.physicalCoreCount == 15)
        #expect(cpu?.hardware?.logicalCoreCount == 15)
        #expect(cpu?.hardware?.coreGroups.map(\.name) == ["Super", "Performance"])
        #expect(cpu?.totalUsage?.value == 25)
        #expect(cpu?.perCoreUsage.count == 15)
        #expect(cpu?.perCoreUsage.allSatisfy { $0.value == 25 } == true)
        #expect(snapshot.systemAvailability[.cpu] == .fresh(capturedAt: Date(timeIntervalSince1970: 1_790_755_200)))
    }

    private static func snapshot(
        usage: Double?,
        perCore: [Double],
        availability: MetricAvailability,
        capturedAt: Date = Date(timeIntervalSince1970: 30_000),
        hardware: CPUHardwareInfo = CPUHardwareInfo(
            name: "Apple M5 Pro",
            physicalCoreCount: 15,
            logicalCoreCount: 15,
            coreGroups: [
                CPUHardwareInfo.CoreGroup(name: "Super", physicalCoreCount: 5)!,
                CPUHardwareInfo.CoreGroup(name: "Performance", physicalCoreCount: 10)!,
            ]
        )
    ) -> CombinedUsageSnapshot {
        let system = SystemMetricsSnapshot(
            capturedAt: capturedAt,
            cpu: .init(totalUsage: usage.flatMap(MetricPercentage.init),
                       perCoreUsage: perCore.compactMap(MetricPercentage.init), hardware: hardware),
            memory: .init(usedBytes: nil, freeBytes: nil, swapUsedBytes: nil, pressure: nil),
            disks: [],
            network: .init(uploadBytesPerSecond: nil, downloadBytesPerSecond: nil,
                           localIPAddresses: [], publicIPAddress: nil),
            battery: .init(level: nil, isCharging: nil, health: nil),
            availability: [.cpu: availability]
        )
        return CombinedUsageSnapshot(
            system: system,
            providers: [],
            capturedAt: capturedAt,
            systemAvailability: [.cpu: availability]
        )
    }
}

@MainActor
private struct SettingsCPUInformationTestHost {
    let presentation: SettingsCPUInformationPresentation

    func render(width: CGFloat, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let content = SettingsCPUInformationView(presentation: presentation)
            .frame(width: width, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        let hostingView = NSHostingView(rootView: content)
        let frame = NSRect(x: 0, y: 0, width: width, height: hostingView.fittingSize.height)
        hostingView.frame = frame
        let nativeAppearance = try #require(NSAppearance(named: appearance))
        hostingView.appearance = nativeAppearance
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = nativeAppearance
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.display()
        defer { window.close() }
        for _ in 0..<6 {
            window.display()
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        let bitmap = NSBitmapImageRep(
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
        )!
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    func writePNG(_ image: NSBitmapImageRep, name: String) throws {
        let directory = URL(fileURLWithPath: "/tmp/needlbar-cpu-settings-review", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try #require(image.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
    }
}
