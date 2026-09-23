import Foundation
import Testing
@testable import NeedlbarCore

@Test func diagnosticsDecoderAcceptsOnlyKnownProvidersEnumsAndTimestamps() throws {
    let payload = """
    {
      "schemaVersion": "needlbar.v1",
      "ok": true,
      "generatedAt": "2026-08-14T12:00:00Z",
      "data": {
        "providers": [
          {
            "provider": "claude",
            "usageStatus": "available",
            "quotaStatus": "requiresAuthentication",
            "usageSource": "local",
            "quotaSource": "oauth",
            "lastUsageAt": "2026-08-14T11:00:00Z",
            "lastQuotaAt": null,
            "quotaErrorCode": "requiresAuthentication",
            "futureField": "CLAUDE-CANARY-SECRET"
          }
        ],
        "futurePayloadField": "CODEX-CANARY-SECRET"
      },
      "errors": []
    }
    """

    let envelope = try BridgeDecoder().decodeDiagnosticsEnvelope(Data(payload.utf8))
    let provider = try #require(envelope.data?.providers.first)

    #expect(provider.provider == .claude)
    #expect(provider.usageStatus == .available)
    #expect(provider.quotaStatus == .requiresAuthentication)
    #expect(provider.usageSource == .local)
    #expect(provider.quotaSource == .oauth)
    #expect(provider.lastUsageAt == BridgeDecoder.date("2026-08-14T11:00:00Z"))
    #expect(provider.lastQuotaAt == nil)
    #expect(provider.quotaErrorCode == .requiresAuthentication)
}

@Test func diagnosticsDecoderAcceptsPermissionDeniedFromClaudeVerification() throws {
    let payload = """
    { "schemaVersion": "needlbar.v1", "ok": true, "generatedAt": "2026-08-25T12:00:00Z", "data": { "providers": [{ "provider": "claude", "usageStatus": "available", "quotaStatus": "error", "usageSource": "local", "quotaSource": "oauth", "lastUsageAt": null, "lastQuotaAt": null, "quotaErrorCode": "permissionDenied" }] }, "errors": [] }
    """

    let envelope = try BridgeDecoder().decodeDiagnosticsEnvelope(Data(payload.utf8))
    let provider = try #require(envelope.data?.providers.first)
    #expect(provider.quotaErrorCode == .permissionDenied)
}

@Test func diagnosticsDecoderAcceptsCurrentAndLegacyRustOAuthQuotaSourceSpellings() throws {
    for source in ["oauth", "oAuth"] {
        let payload = #"{"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-09-16T12:00:00Z","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"error","usageSource":"local","quotaSource":"\#(source)"}]},"errors":[]}"#

        let envelope = try BridgeDecoder().decodeDiagnosticsEnvelope(Data(payload.utf8))
        let provider = try #require(envelope.data?.providers.first)

        #expect(provider.quotaSource == .oauth)
    }
}

@Test func diagnosticsDecoderAcceptsOnlyClosedClaudeFailureOriginsAndOptionalAttemptTime() throws {
    let origins: [ClaudeQuotaFailureOrigin] = [
        .credentialMissing, .keychainCredentialExpired, .fileCredentialExpired,
        .credentialAccessDenied, .usageEndpointUnauthorized, .usageEndpointForbidden, .otherFailure,
    ]
    for origin in origins {
        let payload = """
        {"schemaVersion":"needlbar.v1","ok":true,"generatedAt":"2026-09-16T12:00:00Z","data":{"providers":[{"provider":"claude","usageStatus":"available","quotaStatus":"error","usageSource":"local","quotaSource":"oauth","lastAttemptAt":"2026-09-16T11:59:59Z","claudeQuotaFailureOrigin":"\(origin.rawValue)"}]},"errors":[]}
        """
        let provider = try #require(BridgeDecoder().decodeDiagnosticsEnvelope(Data(payload.utf8)).data?.providers.first)
        #expect(provider.claudeQuotaFailureOrigin == origin)
        #expect(provider.lastAttemptAt == BridgeDecoder.date("2026-09-16T11:59:59Z"))
    }
}

@Test func diagnosticsDecoderPreservesLocalCursorUsageWhenQuotaIsUnavailable() throws {
    let payload = """
    { "schemaVersion": "needlbar.v1", "ok": true, "generatedAt": "2026-08-26T12:00:00Z", "data": { "providers": [{ "provider": "cursor", "usageStatus": "available", "quotaStatus": "unavailable", "usageSource": "local", "quotaSource": "unavailable", "lastUsageAt": null, "lastQuotaAt": null, "quotaErrorCode": "providerUnavailable" }] }, "errors": [] }
    """

    let envelope = try BridgeDecoder().decodeDiagnosticsEnvelope(Data(payload.utf8))
    let provider = try #require(envelope.data?.providers.first)

    #expect(provider.provider == .cursor)
    #expect(provider.usageStatus == .available)
    #expect(provider.quotaStatus == .unavailable)
    #expect(provider.usageSource == .local)
    #expect(provider.quotaSource == .unavailable)
    #expect(provider.lastUsageAt == nil)
    #expect(provider.lastQuotaAt == nil)
    #expect(provider.quotaErrorCode == .providerUnavailable)
}

@Test func diagnosticsDecoderRejectsUnknownProviderEnumsAndMalformedTimestamps() {
    let invalidProvider = """
    { "schemaVersion": "needlbar.v1", "ok": true, "generatedAt": "2026-08-14T12:00:00Z", "data": { "providers": [{ "provider": "unknown", "usageStatus": "available", "quotaStatus": "available", "usageSource": "local", "quotaSource": "oauth", "lastUsageAt": null, "lastQuotaAt": null }] }, "errors": [] }
    """
    let invalidSource = """
    { "schemaVersion": "needlbar.v1", "ok": true, "generatedAt": "2026-08-14T12:00:00Z", "data": { "providers": [{ "provider": "cursor", "usageStatus": "available", "quotaStatus": "available", "usageSource": "/Users/name/CLAUDE-CANARY-SECRET", "quotaSource": "oauth", "lastUsageAt": null, "lastQuotaAt": null }] }, "errors": [] }
    """
    let invalidTimestamp = """
    { "schemaVersion": "needlbar.v1", "ok": true, "generatedAt": "2026-08-14T12:00:00Z", "data": { "providers": [{ "provider": "codex", "usageStatus": "available", "quotaStatus": "available", "usageSource": "local", "quotaSource": "oauth", "lastUsageAt": "CODEX-CANARY-SECRET", "lastQuotaAt": null }] }, "errors": [] }
    """
    let invalidOrigin = """
    { "schemaVersion": "needlbar.v1", "ok": true, "generatedAt": "2026-08-14T12:00:00Z", "data": { "providers": [{ "provider": "claude", "usageStatus": "available", "quotaStatus": "error", "usageSource": "local", "quotaSource": "oauth", "lastAttemptAt": "2026-08-14T12:00:00Z", "claudeQuotaFailureOrigin": "CLAUDE-CANARY-SECRET" }] }, "errors": [] }
    """

    #expect(throws: DecodingError.self) {
        _ = try BridgeDecoder().decodeDiagnosticsEnvelope(Data(invalidProvider.utf8))
    }
    #expect(throws: DecodingError.self) {
        _ = try BridgeDecoder().decodeDiagnosticsEnvelope(Data(invalidSource.utf8))
    }
    #expect(throws: DecodingError.self) {
        _ = try BridgeDecoder().decodeDiagnosticsEnvelope(Data(invalidTimestamp.utf8))
    }
    #expect(throws: DecodingError.self) {
        _ = try BridgeDecoder().decodeDiagnosticsEnvelope(Data(invalidOrigin.utf8))
    }
}
