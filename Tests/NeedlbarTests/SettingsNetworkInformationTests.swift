import AppKit
import Foundation
import SwiftUI
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("SettingsNetworkInformation")
@MainActor
struct SettingsNetworkInformationTests {
    @Test func trafficPreservesIndependentRatesAndFreshnessDates() {
        let capturedAt = Date(timeIntervalSince1970: 1_790_755_200)
        let presentation = SettingsNetworkInformationPresentation(snapshot: Self.snapshot(
            download: 1_048_576, upload: 0, availability: .fresh(capturedAt: capturedAt)
        ))

        #expect(presentation.value.downloadBytesPerSecond == 1_048_576)
        #expect(presentation.value.uploadBytesPerSecond == 0)
        #expect(presentation.value.status == .fresh(capturedAt: capturedAt))

        presentation.update(snapshot: Self.snapshot(
            download: nil, upload: 131_072, availability: .fresh(capturedAt: capturedAt)
        ))
        #expect(presentation.value.downloadBytesPerSecond == nil)
        #expect(presentation.value.uploadBytesPerSecond == 131_072)
    }

    @Test func trafficUnavailableOrMissingAvailabilityClearsOrphanRatesAndDate() {
        let capturedAt = Date(timeIntervalSince1970: 1_790_755_200)
        let presentation = SettingsNetworkInformationPresentation(snapshot: Self.snapshot(
            download: 100, upload: 200, availability: .fresh(capturedAt: capturedAt)
        ))

        presentation.update(snapshot: Self.snapshot(download: 100, upload: 200,
            availability: .unavailable(code: "networkUnavailable")))
        #expect(presentation.value.downloadBytesPerSecond == nil)
        #expect(presentation.value.uploadBytesPerSecond == nil)
        #expect(presentation.value.successfulAt == nil)
        #expect(presentation.value.status == .unavailable)

        presentation.update(snapshot: Self.snapshot(download: 100, upload: 200, availability: nil))
        #expect(presentation.value.downloadBytesPerSecond == nil)
        #expect(presentation.value.successfulAt == nil)
    }

    @Test func staleTrafficUsesLastSuccessfulDateAndCanBeDataLess() {
        let lastSuccess = Date(timeIntervalSince1970: 1_790_668_800)
        let failedAttempt = lastSuccess.addingTimeInterval(86_400)
        let presentation = SettingsNetworkInformationPresentation(snapshot: Self.snapshot(
            download: 0, upload: 42, availability: .stale(lastSuccessfulAt: lastSuccess),
            capturedAt: failedAttempt
        ))
        #expect(presentation.value.status == .stale(lastSuccessfulAt: lastSuccess))
        #expect(presentation.value.successfulAt == lastSuccess)
        #expect(presentation.value.successfulAt != failedAttempt)

        presentation.update(snapshot: Self.snapshot(download: nil, upload: nil,
            availability: .stale(lastSuccessfulAt: lastSuccess), capturedAt: failedAttempt))
        #expect(presentation.value.status == .unavailable)
        #expect(presentation.value.downloadBytesPerSecond == nil)
        #expect(presentation.value.successfulAt == nil)
    }

    @Test func missingSystemClearsTrafficInterfacesAndAddressesThenRecovers() {
        let capturedAt = Date(timeIntervalSince1970: 1_790_755_200)
        let presentation = SettingsNetworkInformationPresentation(snapshot: Self.snapshot(
            download: 100, upload: 200, availability: .fresh(capturedAt: capturedAt),
            names: ["en0"], local: ["192.0.2.10"], publicIP: "198.51.100.10"
        ))

        presentation.update(snapshot: CombinedUsageSnapshot(system: nil, providers: [], capturedAt: capturedAt,
            systemAvailability: [.network: .stale(lastSuccessfulAt: capturedAt)]))
        #expect(presentation.value.downloadBytesPerSecond == nil)
        #expect(presentation.value.interfaceNames == nil)
        #expect(presentation.value.localIPAddresses.isEmpty)
        #expect(presentation.value.publicIPAddress == nil)

        presentation.update(snapshot: Self.snapshot(download: 0, upload: nil,
            availability: .fresh(capturedAt: capturedAt)))
        #expect(presentation.value.downloadBytesPerSecond == 0)
        #expect(presentation.value.status == .fresh(capturedAt: capturedAt))
    }

    @Test func interfacesRenderWithoutTrafficAndDistinguishUnknownFromNoNames() {
        let capturedAt = Date(timeIntervalSince1970: 1_790_755_200)
        let presentation = SettingsNetworkInformationPresentation(snapshot: Self.snapshot(
            download: nil, upload: nil, availability: .fresh(capturedAt: capturedAt), names: ["utun3", "en0"]
        ))
        #expect(presentation.value.interfaceNames == ["en0", "utun3"])
        #expect(presentation.value.status == .unavailable)

        presentation.update(snapshot: Self.snapshot(download: nil, upload: nil,
            availability: .fresh(capturedAt: capturedAt), names: []))
        #expect(presentation.value.interfaceNames == [])
        presentation.update(snapshot: Self.snapshot(download: nil, upload: nil,
            availability: .fresh(capturedAt: capturedAt), names: nil))
        #expect(presentation.value.interfaceNames == nil)

        presentation.update(snapshot: Self.snapshot(download: nil, upload: nil,
            availability: .fresh(capturedAt: capturedAt), names: ["en0", "EN0", "en0"]))
        #expect(presentation.value.interfaceNames == ["EN0", "en0"])
        #expect(!presentation.value.interfaceNamesOmitted)
    }

    @Test func interfaceNamesNormalizeSortDeduplicateAndExplainOmissions() {
        let capturedAt = Date(timeIntervalSince1970: 1_790_755_200)
        let controls = "bad\u{0007}name"
        let longName = String(repeating: "x", count: 65)
        let many = (0..<17).map { String(format: "en%02d", $0) }
        let presentation = SettingsNetworkInformationPresentation(snapshot: Self.snapshot(
            download: nil, upload: nil, availability: .fresh(capturedAt: capturedAt),
            names: [" utun3 ", "en0", "en0", controls, longName] + many
        ))

        #expect(presentation.value.interfaceNames == ["en0", "en00", "en01", "en02", "en03", "en04", "en05", "en06", "en07", "en08", "en09", "en10", "en11", "en12", "en13", "en14"])
        #expect(presentation.value.interfaceNamesOmitted)

        presentation.update(snapshot: Self.snapshot(download: nil, upload: nil,
            availability: .fresh(capturedAt: capturedAt), names: [controls, longName]))
        #expect(presentation.value.interfaceNames == nil)
        #expect(presentation.value.interfaceNamesOmitted)
    }

    @Test func staleMetadataRemainsLastKnownWhenTrafficHasNoUsableRates() {
        let lastSuccess = Date(timeIntervalSince1970: 1_790_668_800)
        let presentation = SettingsNetworkInformationPresentation(snapshot: Self.snapshot(
            download: nil, upload: nil, availability: .stale(lastSuccessfulAt: lastSuccess),
            names: ["en0"], local: ["192.0.2.10"], publicIP: "198.51.100.10"
        ))

        #expect(presentation.value.status == .unavailable)
        #expect(presentation.value.metadataIsStale)
        #expect(presentation.value.interfaceNames == ["en0"])
        #expect(presentation.value.localIPAddresses == ["192.0.2.10"])
        #expect(presentation.value.publicIPAddress == "198.51.100.10")
    }

    @Test func addressesRequireNumericLiteralsAndRetainLocalOrder() {
        let capturedAt = Date(timeIntervalSince1970: 1_790_755_200)
        let presentation = SettingsNetworkInformationPresentation(snapshot: Self.snapshot(
            download: 0, upload: nil, availability: .fresh(capturedAt: capturedAt),
            local: [" 192.0.2.10 ", "2001:db8::10", "192.0.2.10", "localhost", "999.1.1.1", "bad\u{0007}ip", String(repeating: "a", count: 46)],
            publicIP: " 198.51.100.10 "
        ))

        #expect(presentation.value.localIPAddresses == ["192.0.2.10", "2001:db8::10"])
        #expect(presentation.value.publicIPAddress == "198.51.100.10")
    }

    @Test func staleDatesFormatAsLastKnownAndRatesUseBinaryUnits() {
        let successfulAt = Date(timeIntervalSince1970: 1_790_668_800)
        let dateText = SettingsNetworkInformationView.trafficTimeText(
            status: .stale(lastSuccessfulAt: successfulAt)
        )
        #expect(dateText.hasPrefix("Last known traffic · "))
        #expect(dateText.contains(successfulAt.formatted(date: .complete, time: .shortened)))
        #expect(SettingsNetworkInformationView.trafficTimeText(status: .fresh(capturedAt: successfulAt))
            == "Traffic sampled · \(successfulAt.formatted(date: .complete, time: .shortened))")
        #expect(SettingsNetworkInformationView.rateAccessibilityText(title: "Download", value: 1_048_576,
            status: .stale(lastSuccessfulAt: successfulAt)) == "Last known Download 1048576 bytes per second, 1 MiB/s")
        #expect(SettingsNetworkInformationView.rateText(0) == "0 B/s")
        #expect(SettingsNetworkInformationView.rateText(1_048_576) == "1 MiB/s")
        #expect(SettingsNetworkInformationView.rateText(nil) == "—")
    }

    @Test func ipVisibilityRequiresDashboardAndIndependentOption() {
        for tab in SettingsStudioTab.allCases {
            for localEnabled in [false, true] {
                for publicEnabled in [false, true] {
                    let visibility = SettingsNetworkIPVisibility(tab: tab,
                        localEnabled: localEnabled, publicEnabled: publicEnabled)
                    #expect(visibility.showsLocalIP == (tab == .dashboard && localEnabled))
                    #expect(visibility.showsPublicIP == (tab == .dashboard && publicEnabled))
                }
            }
        }

        let visibility = SettingsNetworkIPVisibility(tab: .dashboard,
            localEnabled: false, publicEnabled: true)
        #expect(!visibility.showsLocalIP)
        #expect(visibility.showsPublicIP)

        let retained = SettingsNetworkInformationPresentation(snapshot: Self.snapshot(download: 0, upload: nil,
            availability: .fresh(capturedAt: Date(timeIntervalSince1970: 1_790_755_200)),
            local: ["192.0.2.10"], publicIP: "198.51.100.10"))
        let bothOn = SettingsNetworkIPVisibility(tab: .dashboard, localEnabled: true, publicEnabled: true)
        let bothOff = SettingsNetworkIPVisibility(tab: .dashboard, localEnabled: false, publicEnabled: false)
        #expect(bothOn.showsLocalIP && bothOn.showsPublicIP)
        #expect(!bothOff.showsLocalIP && !bothOff.showsPublicIP)
        #expect(retained.value.localIPAddresses == ["192.0.2.10"])
        #expect(retained.value.publicIPAddress == "198.51.100.10")
    }

    @Test func attachedNetworkCardRendersLightDarkLongNamesIPv6AndUnavailableStates() throws {
        let time = Date(timeIntervalSince1970: 1_790_755_200)
        let longNames = (0..<16).map { "interface-\($0)-" + String(repeating: "x", count: 24) }
        let fixtures: [(String, CGFloat, NSAppearance.Name, CombinedUsageSnapshot)] = [
            ("light-normal", 677, .aqua, Self.snapshot(download: 1_048_576, upload: 131_072,
                availability: .fresh(capturedAt: time), names: ["en0", "utun3"],
                local: ["2001:db8:1234:5678:9abc:def0:1234:5678"], publicIP: "198.51.100.10")),
            ("dark-minimum-long-names-ipv6", 477, .darkAqua, Self.snapshot(download: 1_048_576, upload: 0,
                availability: .stale(lastSuccessfulAt: time), names: longNames,
                local: ["2001:db8:1234:5678:9abc:def0:1234:5678"], publicIP: "2001:db8::1")),
            ("unavailable", 477, .darkAqua, Self.snapshot(download: nil, upload: nil,
                availability: .unavailable(code: "networkUnavailable"), names: nil)),
        ]

        for (name, width, appearance, snapshot) in fixtures {
            let bitmap = try Self.render(snapshot: snapshot, width: width, appearance: appearance)
            #expect(bitmap.pixelsWide == Int(width))
            #expect(bitmap.pixelsHigh > 0)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let directory = URL(fileURLWithPath: "/tmp/needlbar-network-settings-review", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
        }
    }

    @MainActor
    private static func render(
        snapshot: CombinedUsageSnapshot, width: CGFloat, appearance: NSAppearance.Name
    ) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let presentation = SettingsNetworkInformationPresentation(snapshot: snapshot)
        let content = SettingsNetworkInformationView(presentation: presentation,
            ipVisibility: SettingsNetworkIPVisibility(tab: .dashboard, localEnabled: true, publicEnabled: true))
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

    private static func snapshot(
        download: UInt64?, upload: UInt64?, availability: MetricAvailability?,
        names: [String]? = nil, local: [String] = [], publicIP: String? = nil,
        capturedAt: Date = Date(timeIntervalSince1970: 1_790_755_200)
    ) -> CombinedUsageSnapshot {
        var systemAvailability: [MonitorModuleID: MetricAvailability] = [:]
        if let availability { systemAvailability[.network] = availability }
        let system = SystemMetricsSnapshot(
            capturedAt: capturedAt,
            cpu: .init(totalUsage: nil, perCoreUsage: []),
            memory: .init(usedBytes: nil, freeBytes: nil, swapUsedBytes: nil, pressure: nil),
            disks: [],
            network: .init(uploadBytesPerSecond: upload, downloadBytesPerSecond: download,
                           localIPAddresses: local, publicIPAddress: publicIP, interfaceNames: names),
            battery: .init(level: nil, isCharging: nil, health: nil),
            availability: systemAvailability
        )
        return CombinedUsageSnapshot(system: system, providers: [], capturedAt: capturedAt,
                                     systemAvailability: systemAvailability)
    }
}
