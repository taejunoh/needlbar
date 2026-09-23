import Foundation
import Testing
@testable import NeedlbarApp
import NeedlbarCore

@Test func reporterEmitsOneAllowlistedEventForEachClosedOriginWithFixedRFC3339Attempt() async throws {
    let sink = DiagnosticEventSink()
    for origin in ClaudeQuotaFailureOrigin.allCasesForTest {
        let reporter = ClaudeQuotaFailureDiagnosticsReporter(
            readDiagnostics: { try diagnosticsEnvelope(origin: origin.rawValue, attempt: "2026-09-16T11:59:59.123Z") },
            sink: { sink.append($0) }
        )

        reporter.reportLatestClaudeQuotaFailure()
    }

    #expect(sink.values.map(\.origin) == ClaudeQuotaFailureOrigin.allCasesForTest)
    #expect(sink.values.map(\.attemptAt) == Array(repeating: "2026-09-16T11:59:59Z", count: 7))
}

@Test func reporterOmitsEventsForOldSuccessAndMissingDiagnosticFields() async throws {
    let sink = DiagnosticEventSink()
    let fixtures = [
        oldDiagnosticsEnvelope(),
        try diagnosticsEnvelope(origin: nil, attempt: "2026-09-16T11:59:59.123Z", quotaStatus: "available"),
        try diagnosticsEnvelope(origin: "otherFailure", attempt: "2026-09-16T11:59:59.123Z", quotaStatus: "available"),
        try diagnosticsEnvelope(origin: "otherFailure", attempt: nil),
    ]

    for fixture in fixtures {
        let reporter = ClaudeQuotaFailureDiagnosticsReporter(
            readDiagnostics: { fixture },
            sink: { sink.append($0) }
        )

        reporter.reportLatestClaudeQuotaFailure()
    }

    #expect(sink.values.isEmpty)
}

@Test func reporterOmitsEventsForInvalidAndMalformedDiagnostics() async {
    let sink = DiagnosticEventSink()
    let invalidOrigin = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-09-16T12:00:00Z","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"error","usageSource":"local","quotaSource":"oauth","lastAttemptAt":"2026-09-16T11:59:59.123Z","claudeQuotaFailureOrigin":"futureOrigin"}]},"errors":[]}
    """
    let malformed = "{".data(using: .utf8)!
    let fixtures: [@Sendable () throws -> BridgeEnvelope<DiagnosticsSnapshot>] = [
        { try BridgeDecoder().decodeDiagnosticsEnvelope(Data(invalidOrigin.utf8)) },
        { try BridgeDecoder().decodeDiagnosticsEnvelope(malformed) },
    ]

    for fixture in fixtures {
        let reporter = ClaudeQuotaFailureDiagnosticsReporter(
            readDiagnostics: fixture,
            sink: { sink.append($0) }
        )

        reporter.reportLatestClaudeQuotaFailure()
    }

    #expect(sink.values.isEmpty)
}

@Test func reporterEventNeverIncludesUnrelatedRawSecretCanaryFields() async throws {
    let sink = DiagnosticEventSink()
    let fixture = try diagnosticsEnvelope(
        origin: "usageEndpointForbidden",
        attempt: "2026-09-16T11:59:59.123Z",
        extraFields: "\"rawSecretCanary\":\"CLAUDE-CANARY-SECRET\",\"accountPath\":\"/private/canary\""
    )
    let reporter = ClaudeQuotaFailureDiagnosticsReporter(
        readDiagnostics: { fixture },
        sink: { sink.append($0) }
    )

    reporter.reportLatestClaudeQuotaFailure()

    let event = try #require(sink.values.first)
    #expect(event.origin == .usageEndpointForbidden)
    #expect(event.attemptAt == "2026-09-16T11:59:59Z")
    #expect(!event.attemptAt.contains("CLAUDE-CANARY-SECRET"))
    #expect(!String(describing: event).contains("CLAUDE-CANARY-SECRET"))
}

@Test func reporterReadsDiagnosticsExactlyOnceWithoutCallingQuotaBridgeClosures() async throws {
    let diagnosticsCalls = LockedCounter()
    let quotaCalls = LockedCounter()
    let frees = FreeRecorder()
    let returnedPointer = try CStringPointer(diagnosticsCString())
    let bridge = RustBridge(
        quotaCall: {
            quotaCalls.increment()
            return nil
        },
        claudePreflightQuotaCall: {
            quotaCalls.increment()
            return nil
        },
        claudeUserInitiatedQuotaCall: {
            quotaCalls.increment()
            return nil
        },
        codexQuotaCall: {
            quotaCalls.increment()
            return nil
        },
        diagnosticsCall: {
            diagnosticsCalls.increment()
            return returnedPointer.pointer
        },
        free: { frees.release($0) }
    )
    let sink = DiagnosticEventSink()
    let reporter = ClaudeQuotaFailureDiagnosticsReporter(
        readDiagnostics: bridge.diagnosticsEnvelope,
        sink: { sink.append($0) }
    )

    reporter.reportLatestClaudeQuotaFailure()

    #expect(diagnosticsCalls.value == 1)
    #expect(quotaCalls.value == 0)
    #expect(frees.count == 1)
    #expect(sink.values.count == 1)
}

private func diagnosticsEnvelope(
    origin: String?,
    attempt: String?,
    quotaStatus: String = "error",
    extraFields: String = ""
) throws -> BridgeEnvelope<DiagnosticsSnapshot> {
    let originField = origin.map { "\"claudeQuotaFailureOrigin\":\"\($0)\"," } ?? ""
    let attemptField = attempt.map { "\"lastAttemptAt\":\"\($0)\"," } ?? ""
    let json = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-09-16T12:00:00Z","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"\(quotaStatus)","usageSource":"local","quotaSource":"oauth",\(attemptField)\(originField)\(extraFields)}]},"errors":[]}
    """
    return try BridgeDecoder().decodeDiagnosticsEnvelope(Data(json.utf8))
}

private func oldDiagnosticsEnvelope() -> BridgeEnvelope<DiagnosticsSnapshot> {
    let json = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-09-16T12:00:00Z","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"available","usageSource":"local","quotaSource":"oauth"}]},"errors":[]}
    """
    return try! BridgeDecoder().decodeDiagnosticsEnvelope(Data(json.utf8))
}

private func diagnosticsCString() -> UnsafePointer<CChar>? {
    let json = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-09-16T12:00:00Z","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"error","usageSource":"local","quotaSource":"oauth","lastAttemptAt":"2026-09-16T11:59:59.123Z","claudeQuotaFailureOrigin":"otherFailure"}]},"errors":[]}
    """
    return makeCString(Array(json.utf8).map(CChar.init) + [0])
}

private func makeCString(_ bytes: [CChar]) -> UnsafePointer<CChar>? {
    let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
    pointer.initialize(from: bytes, count: bytes.count)
    return UnsafePointer(pointer)
}

private final class DiagnosticEventSink: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ClaudeQuotaFailureDiagnosticEvent] = []

    var values: [ClaudeQuotaFailureDiagnosticEvent] {
        lock.withLock { events }
    }

    func append(_ event: ClaudeQuotaFailureDiagnosticEvent) {
        lock.withLock { events.append(event) }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

private final class FreeRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var pointers: [UInt] = []

    var count: Int {
        lock.withLock { pointers.count }
    }

    func release(_ pointer: UnsafePointer<CChar>?) {
        guard let pointer else { return }
        lock.withLock { pointers.append(UInt(bitPattern: pointer)) }
        UnsafeMutablePointer(mutating: pointer).deallocate()
    }
}

private final class CStringPointer: @unchecked Sendable {
    let pointer: UnsafePointer<CChar>

    init(_ pointer: UnsafePointer<CChar>?) throws {
        self.pointer = try #require(pointer)
    }
}

private extension ClaudeQuotaFailureOrigin {
    static let allCasesForTest: [Self] = [
        .credentialMissing,
        .keychainCredentialExpired,
        .fileCredentialExpired,
        .credentialAccessDenied,
        .usageEndpointUnauthorized,
        .usageEndpointForbidden,
        .otherFailure,
    ]
}
