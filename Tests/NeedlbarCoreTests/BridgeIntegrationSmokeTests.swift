import Foundation
import Testing
@testable import NeedlbarCore

@Test func fixtureBridgeABISnapshotsMergeAllProvidersAndPreservePartialFailure() async throws {
    let fixtureHome = try makeFixtureHome()
    defer { try? FileManager.default.removeItem(at: fixtureHome) }

    let installed = fixtureHome.path.withCString { needlbar_test_install_fixture_runtime($0) }
    #expect(installed)
    defer { needlbar_test_clear_runtime() }

    let bridge = RustBridge()
    let usage = try RustUsageRepository(bridge: bridge).refresh()
    let quota = try RustQuotaRepository(bridge: bridge).refresh()
    let now = try #require(BridgeDecoder.date("2026-08-14T12:00:00Z"))
    let store = ProviderSnapshotStore(now: { now })

    for (provider, snapshot) in usage.snapshots {
        await store.applyUsage(snapshot, for: provider, at: now)
    }
    for (provider, snapshot) in quota.snapshots {
        await store.applyQuota(snapshot, for: provider, at: now)
    }
    for (provider, error) in usage.errors {
        await store.markUsageFailure(
            for: provider,
            status: .error(message: error.message, lastSuccessfulAt: nil),
            at: now
        )
    }

    let snapshots = await store.snapshots()
    #expect(snapshots.allSatisfy { $0.usage != nil && $0.quota != nil })
    #expect(HeadlineQuotaSelector.mostConstrained(snapshots)?.id == "cursor.plan")

    let codex = try #require(snapshots.first(where: { $0.provider == .codex }))
    #expect(codex.usage?.totalTokens == 1_300)
    #expect(codex.usageStatus == .error(message: "Usage data is unavailable.", lastSuccessfulAt: now))
    #expect(codex.quota?.windows.first?.remainingPercent == 50)

    let claude = try #require(snapshots.first(where: { $0.provider == .claude }))
    let cursor = try #require(snapshots.first(where: { $0.provider == .cursor }))
    #expect(claude.usage?.totalTokens == 1_750)
    #expect(cursor.usage?.totalTokens ?? 0 > 0)
    #expect(cursor.quotaStatus == .fresh)
}

@_silgen_name("needlbar_test_install_fixture_runtime")
private func needlbar_test_install_fixture_runtime(_ fixtureHome: UnsafePointer<CChar>) -> Bool

@_silgen_name("needlbar_test_clear_runtime")
private func needlbar_test_clear_runtime()

private func makeFixtureHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("needlbar-task14-fixtures-\(UUID().uuidString)", isDirectory: true)
    let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Fixtures/usage", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    try copyTree(from: fixtures.appendingPathComponent("claude"), to: home)
    try copyTree(from: fixtures.appendingPathComponent("codex"), to: home)
    let cache = home.appendingPathComponent(".config/tokscale/cursor-cache/usage.csv")
    try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: fixtures.appendingPathComponent("cursor/usage.csv"), to: cache)
    return home
}

private func copyTree(from source: URL, to destination: URL) throws {
    let contents = try FileManager.default.contentsOfDirectory(
        at: source,
        includingPropertiesForKeys: [.isDirectoryKey]
    )
    for item in contents {
        let target = destination.appendingPathComponent(item.lastPathComponent)
        if try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try copyTree(from: item, to: target)
        } else {
            try FileManager.default.copyItem(at: item, to: target)
        }
    }
}
