import Foundation

public enum ClaudeQuotaFailureReason: String, Sendable, Equatable {
    case quotaAccessUnavailable
    case connectionUnavailable
    case temporarilyLimited
    case couldNotUpdateQuota
    /// No executable `claude` at the fixed locations.
    case claudeCodeNotInstalled
    /// The run timed out, produced too much output, did not finish, or reported
    /// no usage. A null report also appears while the CLI's own fetch is failing,
    /// so it is not treated as proof that the user is signed out.
    case claudeCodeCheckFailed
    /// A run finished without a usable usage report.
    case usageReportFormatChanged
    /// `/usage` finished without plan usage, which Claude Code does when it does
    /// not consider itself signed in with a Claude plan.
    case planUsageUnavailable

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
        case .claudeCodeCheckFailed:
            String(
                localized: "claudeQuota.reason.claudeCodeCheckFailed",
                defaultValue: "Could not check Claude Code",
                bundle: bundle,
                comment: "Claude quota reason: running Claude Code to read usage timed out, produced too much output, did not finish, or reported no usage."
            )
        case .usageReportFormatChanged:
            String(
                localized: "claudeQuota.reason.usageReportFormatChanged",
                defaultValue: "Could not read Claude Code's usage report",
                bundle: bundle,
                comment: "Claude quota reason: Claude Code finished but gave no usage report Needlbar can read."
            )
        case .planUsageUnavailable:
            String(
                localized: "claudeQuota.reason.planUsageUnavailable",
                defaultValue: "Claude Code didn't report plan usage",
                bundle: bundle,
                comment: "Claude quota reason: Claude Code ran its usage command and finished without plan usage, which it does when it is not signed in with a Claude plan. Describes what Claude Code did, not a cause."
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
        case .claudeCodeCheckFailed:
            String(
                localized: "claudeQuota.reason.claudeCodeCheckFailed.detail",
                defaultValue: "If this continues, run claude in Terminal to check its sign-in.",
                bundle: bundle,
                comment: "Second line for the check-failed reason, shown in the provider popover and Settings. Keep 'claude' as the command name. Needlbar offers no button for this."
            )
        case .planUsageUnavailable:
            String(
                localized: "claudeQuota.reason.planUsageUnavailable.detail",
                defaultValue: "Claude Code usually shows plan usage only when it's signed in with a Claude plan. Run claude auth login in Terminal, then choose Check now in Needlbar. API keys and usage-billed accounts have no plan limits to show.",
                bundle: bundle,
                comment: "Second line for the plan-usage-unavailable reason, shown in the provider popover and Settings. Keep 'claude auth login' as the command and 'Check now' as the button name. Needlbar never runs the command and offers no sign-in button."
            )
        case .quotaAccessUnavailable, .connectionUnavailable,
             .temporarilyLimited, .couldNotUpdateQuota, .usageReportFormatChanged:
            nil
        }
    }

    /// Maps a completed attempt's Claude error code to a safe reason.
    init(errorCode: String) {
        switch errorCode {
        case "notInstalled": self = .claudeCodeNotInstalled
        case "requiresAuthentication": self = .planUsageUnavailable
        case "authenticationExpired": self = .quotaAccessUnavailable
        case "networkUnavailable": self = .connectionUnavailable
        case "rateLimited": self = .temporarilyLimited
        case "providerUnavailable": self = .claudeCodeCheckFailed
        case "schemaChanged": self = .usageReportFormatChanged
        default: self = .couldNotUpdateQuota
        }
    }
}
