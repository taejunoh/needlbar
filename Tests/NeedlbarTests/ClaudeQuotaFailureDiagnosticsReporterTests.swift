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
    #expect(sink.values.map(\.attemptAt) == Array(
        repeating: "2026-09-16T11:59:59Z",
        count: ClaudeQuotaFailureOrigin.allCasesForTest.count
    ))
    #expect(sink.values.map(\.message) == ClaudeQuotaFailureOrigin.allCasesForTest.map {
        "claudeQuotaFailure origin=\($0.rawValue) code=unknown attempt=2026-09-16T11:59:59Z"
    })
}

@Test func reporterLogLineAddsEachAllowlistedQuotaCodeBetweenOriginAndAttempt() async throws {
    let sink = DiagnosticEventSink()
    for code in allowlistedQuotaCodes {
        let fixture = try diagnosticsEnvelope(
            origin: "otherFailure",
            attempt: "2026-09-16T11:59:59.123Z",
            quotaErrorCode: code
        )
        let reporter = ClaudeQuotaFailureDiagnosticsReporter(readDiagnostics: { fixture }, sink: { sink.append($0) })

        reporter.reportLatestClaudeQuotaFailure()
    }

    #expect(sink.values.map(\.message) == allowlistedQuotaCodes.map {
        "claudeQuotaFailure origin=otherFailure code=\($0) attempt=2026-09-16T11:59:59Z"
    })
}

@Test func reporterLogsEachSplitOtherFailureOriginWithItsProducerCode() async throws {
    let sink = DiagnosticEventSink()
    let cases = [
        ("credentialStoreAmbiguous", "schemaChanged"),
        ("credentialFormatUnrecognized", "schemaChanged"),
        ("credentialFormatUnrecognized", "requiresAuthentication"),
        ("usageEndpointServerError", "providerUnavailable"),
        ("usageResponseUnrecognized", "schemaChanged"),
    ]
    for (origin, code) in cases {
        let reporter = ClaudeQuotaFailureDiagnosticsReporter(
            readDiagnostics: {
                try diagnosticsEnvelope(
                    origin: origin,
                    attempt: "2026-10-29T11:59:59.123Z",
                    quotaErrorCode: code,
                    extraFields: "\"rawSecretCanary\":\"CLAUDE-CANARY-SECRET\"",
                    errors: #"[{"provider":"claude","code":"\#(code)","message":"CLAUDE-CANARY-SECRET"}]"#
                )
            },
            sink: { sink.append($0) }
        )

        reporter.reportLatestClaudeQuotaFailure()
    }

    #expect(sink.values.map(\.message) == cases.map {
        "claudeQuotaFailure origin=\($0.0) code=\($0.1) attempt=2026-10-29T11:59:59Z"
    })
    for event in sink.values {
        #expect(!event.message.contains("CLAUDE-CANARY-SECRET"))
        #expect(!String(describing: event).contains("CLAUDE-CANARY-SECRET"))
    }
}

@Test func reporterLogsUnknownForAnAbsentOrNonQuotaRecordCode() async throws {
    let sink = DiagnosticEventSink()
    let codes: [String?] = [
        nil, "noUsageData", "usageRuntimeUnavailable", "usageReportUnavailable",
        "invalidUsageDate", "invalidUsageData", "internalError",
    ]
    for code in codes {
        let fixture = try diagnosticsEnvelope(
            origin: "otherFailure",
            attempt: "2026-09-16T11:59:59.123Z",
            quotaErrorCode: code
        )
        let reporter = ClaudeQuotaFailureDiagnosticsReporter(readDiagnostics: { fixture }, sink: { sink.append($0) })

        reporter.reportLatestClaudeQuotaFailure()
    }

    #expect(sink.values.map(\.message) == Array(
        repeating: "claudeQuotaFailure origin=otherFailure code=unknown attempt=2026-09-16T11:59:59Z",
        count: codes.count
    ))
}

@Test func reporterFailsClosedWhenTheRecordCodeIsOutsideTheDecodedSet() async {
    let sink = DiagnosticEventSink()
    // `serviceUnavailable` is a Rust quota code the bridge folds into
    // `providerUnavailable`; it, like any other undecodable value, must not
    // reach the line. The record decode rejects it, so nothing is emitted.
    for code in ["serviceUnavailable", "futureCode", "HTTP 503 CLAUDE-CANARY-SECRET"] {
        let reporter = ClaudeQuotaFailureDiagnosticsReporter(
            readDiagnostics: {
                try diagnosticsEnvelope(origin: "otherFailure", attempt: "2026-09-16T11:59:59.123Z", quotaErrorCode: code)
            },
            sink: { sink.append($0) }
        )

        reporter.reportLatestClaudeQuotaFailure()
    }

    #expect(sink.values.isEmpty)
}

@Test func reporterLogLineCarriesNoCanaryFromErrorMessagesOrOtherRecordFields() async throws {
    let canaries = [
        "CLAUDE-CANARY-SECRET", "/private/canary", "https://canary.invalid",
        "Bearer CANARY-TOKEN", "HTTP/1.1 503 CANARY", "CANARY-BODY", "503", "5xx",
    ]
    let fixture = try diagnosticsEnvelope(
        origin: "otherFailure",
        attempt: "2026-09-16T11:59:59.123Z",
        quotaErrorCode: "schemaChanged",
        usageErrorCode: "internalError",
        extraFields: [
            "\"quotaErrorMessage\":\"CLAUDE-CANARY-SECRET\"",
            "\"httpStatus\":\"HTTP/1.1 503 CANARY\"",
            "\"statusClass\":\"5xx\"",
            "\"url\":\"https://canary.invalid/api/oauth/usage\"",
            "\"authorization\":\"Bearer CANARY-TOKEN\"",
            "\"accountPath\":\"/private/canary\"",
            "\"responseBody\":\"{\\\"five_hour\\\":\\\"CANARY-BODY\\\"}\"",
        ].joined(separator: ","),
        errors: """
        [{"provider":"claude","code":"schemaChanged","message":"CLAUDE-CANARY-SECRET HTTP/1.1 503 CANARY https://canary.invalid /private/canary Bearer CANARY-TOKEN CANARY-BODY"}]
        """
    )
    // The canaries are in the read the reporter receives.
    #expect(fixture.errors.first?.message.contains("CLAUDE-CANARY-SECRET") == true)
    #expect(fixture.data?.providers.first?.usageErrorCode == .internalError)
    let sink = DiagnosticEventSink()
    let reporter = ClaudeQuotaFailureDiagnosticsReporter(readDiagnostics: { fixture }, sink: { sink.append($0) })

    reporter.reportLatestClaudeQuotaFailure()

    let event = try #require(sink.values.first)
    #expect(sink.values.count == 1)
    #expect(event.message == "claudeQuotaFailure origin=otherFailure code=schemaChanged attempt=2026-09-16T11:59:59Z")
    for marker in canaries {
        #expect(!event.message.contains(marker), "\(marker) leaked into the log line")
        #expect(!String(describing: event).contains(marker), "\(marker) leaked into the event")
    }
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

/// The Claude quota error codes the bridge can record; the log line's allowlist.
private let allowlistedQuotaCodes = [
    "notInstalled", "requiresAuthentication", "authenticationExpired", "permissionDenied",
    "rateLimited", "networkUnavailable", "providerUnavailable", "schemaChanged",
]

private func diagnosticsEnvelope(
    origin: String?,
    attempt: String?,
    quotaStatus: String = "error",
    quotaErrorCode: String? = nil,
    usageErrorCode: String? = nil,
    extraFields: String = "",
    errors: String = "[]"
) throws -> BridgeEnvelope<DiagnosticsSnapshot> {
    let originField = origin.map { "\"claudeQuotaFailureOrigin\":\"\($0)\"," } ?? ""
    let attemptField = attempt.map { "\"lastAttemptAt\":\"\($0)\"," } ?? ""
    let quotaCodeField = quotaErrorCode.map { "\"quotaErrorCode\":\"\($0)\"," } ?? ""
    let usageCodeField = usageErrorCode.map { "\"usageErrorCode\":\"\($0)\"," } ?? ""
    let json = """
    {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-09-16T12:00:00Z","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"\(quotaStatus)","usageSource":"local","quotaSource":"oauth",\(attemptField)\(quotaCodeField)\(usageCodeField)\(originField)\(extraFields)}]},"errors":\(errors)}
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
        .credentialStoreAmbiguous,
        .credentialFormatUnrecognized,
        .usageEndpointUnauthorized,
        .usageEndpointForbidden,
        .usageEndpointServerError,
        .usageResponseUnrecognized,
        .otherFailure,
    ]
}
