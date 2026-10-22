import Foundation

public enum ClaudeQuotaFailureReason: String, Sendable, Equatable {
    case quotaAccessUnavailable
    case credentialAccessUnavailable
    case connectionUnavailable
    case temporarilyLimited
    case couldNotUpdateQuota
    /// The access Claude Code saved on this Mac has passed its expiry time.
    /// Stored only for `authenticationExpired` with a local-expiry origin.
    case claudeCodeAccessExpired

    public var displayText: String { localizedDisplayText(bundle: .main) }

    /// A second explanatory line, shown only in the provider popover and Settings.
    public var detailText: String? { localizedDetailText(bundle: .main) }

    func localizedDisplayText(bundle: Bundle) -> String {
        switch self {
        case .quotaAccessUnavailable: "Quota access unavailable"
        case .credentialAccessUnavailable: "Credential access unavailable"
        case .connectionUnavailable: "Connection unavailable"
        case .temporarilyLimited: "Temporarily limited"
        case .couldNotUpdateQuota: "Could not update quota"
        case .claudeCodeAccessExpired:
            String(
                localized: "claudeQuota.reason.claudeCodeAccessExpired",
                defaultValue: "Claude Code access on this Mac expired",
                bundle: bundle,
                comment: "Claude quota reason, short form: the access the Claude Code command-line tool saved on this Mac has expired. A statement of fact; it offers the user no action."
            )
        }
    }

    func localizedDetailText(bundle: Bundle) -> String? {
        switch self {
        case .claudeCodeAccessExpired:
            String(
                localized: "claudeQuota.reason.claudeCodeAccessExpired.detail",
                defaultValue: "Needlbar reads the access the Claude Code command-line tool saves on this Mac. The Claude desktop app does not renew it, so it updates after Claude Code runs in Terminal.",
                bundle: bundle,
                comment: "Explains the Claude quota reason as fact: Needlbar reads the access the Claude Code command-line tool saves, and the Claude desktop app does not renew it. Mentions Terminal only as a fact. Informational only; it offers the user no action."
            )
        case .quotaAccessUnavailable, .credentialAccessUnavailable, .connectionUnavailable,
             .temporarilyLimited, .couldNotUpdateQuota:
            nil
        }
    }

    /// Maps a completed attempt's Claude error code, plus the failure origin
    /// associated with that same attempt, to a safe reason. Only a local
    /// credential expiry changes the code-based mapping; HTTP 401/403 and every
    /// other origin keep it.
    init(errorCode: String, associatedOrigin: ClaudeQuotaFailureOrigin?) {
        switch (errorCode, associatedOrigin) {
        case ("authenticationExpired", .keychainCredentialExpired?),
             ("authenticationExpired", .fileCredentialExpired?):
            self = .claudeCodeAccessExpired
        case ("requiresAuthentication", _), ("authenticationExpired", _): self = .quotaAccessUnavailable
        case ("permissionDenied", _): self = .credentialAccessUnavailable
        case ("networkUnavailable", _): self = .connectionUnavailable
        case ("rateLimited", _): self = .temporarilyLimited
        default: self = .couldNotUpdateQuota
        }
    }
}
