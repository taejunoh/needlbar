public enum ClaudeQuotaFailureReason: String, Sendable, Equatable {
    case quotaAccessUnavailable
    case credentialAccessUnavailable
    case connectionUnavailable
    case temporarilyLimited
    case couldNotUpdateQuota

    public var displayText: String {
        switch self {
        case .quotaAccessUnavailable: "Quota access unavailable"
        case .credentialAccessUnavailable: "Credential access unavailable"
        case .connectionUnavailable: "Connection unavailable"
        case .temporarilyLimited: "Temporarily limited"
        case .couldNotUpdateQuota: "Could not update quota"
        }
    }
}
