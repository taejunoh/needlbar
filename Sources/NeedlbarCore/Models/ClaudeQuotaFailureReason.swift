import Foundation

public enum ClaudeQuotaFailureReason: String, Sendable, Equatable {
    case quotaAccessUnavailable
    case connectionUnavailable
    case temporarilyLimited
    case couldNotUpdateQuota
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

    func localizedDisplayText(bundle: Bundle) -> String {
        switch self {
        case .quotaAccessUnavailable: "Quota access unavailable"
        case .connectionUnavailable: "Connection unavailable"
        case .temporarilyLimited: "Temporarily limited"
        case .couldNotUpdateQuota: "Could not update quota"
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
        case .quotaAccessUnavailable, .connectionUnavailable,
             .temporarilyLimited, .couldNotUpdateQuota, .claudeCodeCheckFailed, .usageReportFormatChanged:
            nil
        }
    }


    /// Maps a completed attempt's Claude error code to a safe reason.
    init(errorCode: String) {
        switch errorCode {
        case "notInstalled": self = .claudeCodeNotInstalled
        case "requiresAuthentication": self = .claudeCodeSignInRequired
        case "authenticationExpired": self = .quotaAccessUnavailable
        case "networkUnavailable": self = .connectionUnavailable
        case "rateLimited": self = .temporarilyLimited
        case "providerUnavailable": self = .claudeCodeCheckFailed
        case "schemaChanged": self = .usageReportFormatChanged
        default: self = .couldNotUpdateQuota
        }
    }
}
