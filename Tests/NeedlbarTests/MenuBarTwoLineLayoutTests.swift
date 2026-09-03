import AppKit
import Testing
@testable import NeedlbarApp
@testable import NeedlbarCore

@Suite("MenuBarTwoLineLayoutTests", .serialized)
@MainActor
struct MenuBarTwoLineLayoutTests {
    @Test func percentageTransitionsKeepColumnGeometryStable() throws {
        let values = ["0%", "9%", "10%", "99%", "100%", "—"]
        let baseline = try #require(layout([segment(.cpu, "CPU", "0%", samples: ["100%", "—"]), segment(.memory, "RAM", "72%", samples: ["100%", "—"])], width: 240, height: 24))

        for value in values {
            let candidate = try #require(layout([segment(.cpu, "CPU", value, samples: ["100%", "—"]), segment(.memory, "RAM", "72%", samples: ["100%", "—"])], width: 240, height: 24))
            #expect(candidate.size == baseline.size)
            #expect(candidate.columnOrigins == baseline.columnOrigins)
        }
    }

    @Test func sharedVerticalBandsKeepBaselinesStableAcrossDigitSuffixAndDescenderChanges() throws {
        let digit = try #require(layout([
            segment(.cpu, "CPU", "9%", samples: ["100%"])
        ], width: 240, height: 24))
        let suffix = try #require(layout([
            segment(.cpu, "CPU", "9K", samples: ["100%"])
        ], width: 240, height: 24))
        let descender = try #require(layout([
            segment(.cpu, "gy", "g", samples: ["100%"])
        ], width: 240, height: 24))

        #expect(baseline(for: .value, in: digit) == baseline(for: .value, in: suffix))
        #expect(baseline(for: .value, in: suffix) == baseline(for: .value, in: descender))
        #expect(baseline(for: .label, in: digit) == baseline(for: .label, in: descender))
    }

    @Test func familyEnvelopesKeepStableLayout() throws {
        try assertFamily(["999", "999.99K", "999.99M", "999.99B", "—"], samples: ["999", "999.99K", "999.99M", "999.99B", "—"])
        try assertFamily(["$999,999.99", "$0.00", "$1,234.56", "—"], samples: ["$999,999.99", "—"])
        try assertFamily(["Connected", "Unavailable", "Sign in", "Stale", "Error", "—"], samples: ["Connected", "Unavailable", "Sign in", "Stale", "Error", "—"])
    }

    @Test func networkUploadChangesNeverMoveDownloadBaseline() throws {
        let uploads = ["↑999B", "↑999.9K", "↑999.9M", "↑999.9G", "↑—"]
        let downloadSamples = ["↓999B", "↓999.9K", "↓999.9M", "↓999.9G", "↓—"]
        var baseline: MenuBarDashboardTwoLineLayout?
        for upload in uploads {
            let candidate = try #require(layout([
                segment(.network, "NET", upload, samples: uploads, secondary: .init("↓2K", samples: downloadSamples))
            ], width: 240, height: 24))
            if let baseline {
                #expect(candidate.runs.first(where: { $0.text == "↓2K" })?.baseline.x == baseline.runs.first(where: { $0.text == "↓2K" })?.baseline.x)
            }
            baseline = candidate
        }
    }

    @Test func fittingUsesPrefixAndRendersOverflowIndicators() throws {
        let candidate = try #require(layout([
            segment(.cpu, "CPU", "24%", samples: ["100%", "—"]),
            segment(.memory, "RAM", "72%", samples: ["100%", "—"]),
            segment(.ai, "Claude", "8%", samples: ["100%", "—"], overflow: 2, compact: "CL"),
            segment(.disk, "Disk", "96%", samples: ["100%", "—"], compact: "DSK")
        ], width: 240, height: 24))

        #expect(candidate.moduleIDs == [.cpu, .memory, .ai])
        #expect(candidate.runs.contains { $0.text == "+1" })
        #expect(candidate.runs.contains { $0.text == "Claude +2" })
    }

    @Test func heightAndWidthGuardsRespectIconException() {
        #expect(layout([segment(.cpu, "CPU", "24%", samples: ["100%", "—"])], width: 21, height: 24) == nil)
        #expect(layout([segment(.cpu, "CPU", "24%", samples: ["100%", "—"])], width: 240, height: 12) == nil)
        #expect(layout([segment(.cpu, "CPU", "24%", samples: ["100%", "—"])], width: 240, height: 22) != nil)
        #expect(layout([segment(.ai, "AI", String(repeating: "9", count: 100), samples: ["999.99B", "—"])], width: 240, height: 24) == nil)
    }

    @Test func acceptedWidthsNeverExceedBudget() {
        let segments = [
            segment(.cpu, "CPU", "24%", samples: ["100%", "—"]),
            segment(.memory, "RAM", "72%", samples: ["100%", "—"]),
            segment(.ai, "Claude", "8%", samples: ["100%", "—"], overflow: 2, compact: "CL"),
            segment(.disk, "Disk", "96%", samples: ["100%", "—"], compact: "DSK")
        ]
        for width in stride(from: CGFloat(22), through: 500, by: 7) {
            if let candidate = layout(segments, width: width, height: 24) {
                #expect(candidate.size.width + MenuBarDashboardTwoLineLayout.chrome <= min(width, 240))
            }
        }
    }

    @Test func compactProviderLabelIsTriedBeforeDroppingThePrefix() throws {
        let segment = segment(.ai, "Claude", "8%", samples: ["100%", "—"], overflow: 2, compact: "CL")
        let compact = try #require((22...240).lazy.compactMap { width in
            layout([segment], width: CGFloat(width), height: 24)
        }.first(where: { $0.runs.contains { $0.text == "CL +2" } }))
        let exactWidth = compact.size.width + MenuBarDashboardTwoLineLayout.chrome
        let candidate = try #require(layout([segment], width: exactWidth, height: 24))

        #expect(candidate.moduleIDs == [.ai])
        #expect(candidate.runs.contains { $0.text == "CL +2" })
    }

    private func assertFamily(_ values: [String], samples: [String]) throws {
        let reference = try #require(layout([segment(.ai, "Claude", values[0], samples: samples)], width: 240, height: 24))
        for value in values.dropFirst() {
            let candidate = try #require(layout([segment(.ai, "Claude", value, samples: samples)], width: 240, height: 24))
            #expect(candidate.size == reference.size)
            #expect(candidate.columnOrigins == reference.columnOrigins)
        }
    }

    private func layout(_ segments: [MenuBarDashboardSegment], width: CGFloat, height: CGFloat, scale: CGFloat = 2) -> MenuBarDashboardTwoLineLayout? {
        MenuBarDashboardTwoLineLayout.fit(segments: segments, width: width, height: height, scale: scale)
    }

    private func segment(_ id: MonitorModuleID, _ label: String, _ value: String, samples: [String], secondary: MenuBarDashboardValuePart? = nil, overflow: Int = 0, compact: String? = nil) -> MenuBarDashboardSegment {
        .init(id, label: label, primary: .init(value, samples: samples), secondary: secondary, providerOverflowCount: overflow, compactLabel: compact)
    }

    private func baseline(for role: MenuBarTextRole, in layout: MenuBarDashboardTwoLineLayout) -> CGFloat? {
        layout.runs.first(where: { $0.role == role })?.baseline.y
    }
}
