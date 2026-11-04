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
    /// No executable `claude` at the fixed locations.
    case claudeCodeNotInstalled
    /// `rate_limits` was null, or `limits` was null or empty.
    case claudeCodeSignInRequired
    /// The run timed out, produced too much output, or did not finish.
    case claudeCodeCheckFailed
    /// A run finished without a usable usage report.
    case usageReportFormatChanged

    public var displayText: String { localizedDisplayText(bundle: .main) }

    /// A second explanatory line, shown only in the provider popover and Settings.
    public var detailText: String? { localizedDetailText(bundle: .main) }

    /// The title of the explicit Keychain access action, for the one reason
    /// that offers it. Every other reason offers the user no such action.
    public var keychainAccessActionTitle: String? { localizedKeychainAccessActionTitle(bundle: .main) }

    /// One line shown beside the Keychain access button, for the one reason
    /// that offers it, and never otherwise.
    public var keychainAccessActionDetail: String? { localizedKeychainAccessActionDetail(bundle: .main) }

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
        case .claudeCodeNotInstalled:
            String(
                localized: "claudeQuota.reason.claudeCodeNotInstalled",
                defaultValue: "Install Claude Code to see quota",
                bundle: bundle,
                comment: "Claude quota reason: the Claude Code command-line tool was not found on this Mac. Shown beside the View Claude usage link."
            )
        case .claudeCodeSignInRequired:
            String(
                localized: "claudeQuota.reason.claudeCodeSignInRequired",
                defaultValue: "Sign in with claude in Terminal",
                bundle: bundle,
                comment: "Claude quota reason: Claude Code reported no usage, usually because it is signed out. Keep 'claude' as the command name. Needlbar offers no button for this."
            )
        case .claudeCodeCheckFailed:
            String(
                localized: "claudeQuota.reason.claudeCodeCheckFailed",
                defaultValue: "Could not check Claude Code",
                bundle: bundle,
                comment: "Claude quota reason: running Claude Code to read usage timed out, produced too much output, or did not finish."
            )
        case .usageReportFormatChanged:
            String(
                localized: "claudeQuota.reason.usageReportFormatChanged",
                defaultValue: "Could not read Claude Code's usage report",
                bundle: bundle,
                comment: "Claude quota reason: Claude Code finished but gave no usage report Needlbar can read."
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
        case .claudeCodeNotInstalled:
            String(
                localized: "claudeQuota.reason.claudeCodeNotInstalled.detail",
                defaultValue: "Needlbar reads quota from the Claude Code command-line tool and did not find it on this Mac. View Claude usage still opens the usage page.",
                bundle: bundle,
                comment: "Second line for the not-installed reason, shown in the provider popover and Settings."
            )
        case .claudeCodeSignInRequired:
            String(
                localized: "claudeQuota.reason.claudeCodeSignInRequired.detail",
                defaultValue: "Claude Code reported no usage for this Mac. Needlbar updates at its next check and never opens a sign-in itself.",
                bundle: bundle,
                comment: "Second line for the sign-in reason, shown in the provider popover and Settings."
            )
        case .quotaAccessUnavailable, .credentialAccessUnavailable, .connectionUnavailable,
             .temporarilyLimited, .couldNotUpdateQuota, .claudeCodeCheckFailed, .usageReportFormatChanged:
            nil
        }
    }

    func localizedKeychainAccessActionTitle(bundle: Bundle) -> String? {
        switch self {
        case .credentialAccessUnavailable:
            String(
                localized: "claudeQuota.action.allowKeychainAccess",
                defaultValue: "Allow Keychain access",
                bundle: bundle,
                comment: "Button shown with the Claude quota reason 'Credential access unavailable'. Clicking it asks macOS once for access to the Keychain item the Claude Code command-line tool saved, which may show a macOS dialog. It only ever runs after this click. Keep 'Keychain', the macOS name."
            )
        case .quotaAccessUnavailable, .connectionUnavailable, .temporarilyLimited,
             .couldNotUpdateQuota, .claudeCodeAccessExpired, .claudeCodeNotInstalled,
             .claudeCodeSignInRequired, .claudeCodeCheckFailed, .usageReportFormatChanged:
            nil
        }
    }

    func localizedKeychainAccessActionDetail(bundle: Bundle) -> String? {
        switch self {
        case .credentialAccessUnavailable:
            String(
                localized: "claudeQuota.action.allowKeychainAccess.detail",
                defaultValue: "Choose Always Allow to let background updates read this Keychain item.",
                bundle: bundle,
                comment: "One line of guidance shown beside the 'Allow Keychain access' button, only while that button is shown. It explains the macOS dialog's 'Always Allow' choice as a suggestion, not a promise about what macOS keeps afterwards. Keep 'Always Allow', the macOS button name."
            )
        case .quotaAccessUnavailable, .connectionUnavailable, .temporarilyLimited,
             .couldNotUpdateQuota, .claudeCodeAccessExpired, .claudeCodeNotInstalled,
             .claudeCodeSignInRequired, .claudeCodeCheckFailed, .usageReportFormatChanged:
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
        case ("notInstalled", _): self = .claudeCodeNotInstalled
        case ("requiresAuthentication", _): self = .claudeCodeSignInRequired
        case ("authenticationExpired", _): self = .quotaAccessUnavailable
        case ("permissionDenied", _): self = .credentialAccessUnavailable
        case ("networkUnavailable", _): self = .connectionUnavailable
        case ("rateLimited", _): self = .temporarilyLimited
        case ("providerUnavailable", _): self = .claudeCodeCheckFailed
        case ("schemaChanged", _): self = .usageReportFormatChanged
        default: self = .couldNotUpdateQuota
        }
    }
}
