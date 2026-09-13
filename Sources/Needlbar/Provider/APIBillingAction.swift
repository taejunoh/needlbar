import AppKit
import NeedlbarCore

public enum ProviderAPIBillingAction: Equatable, Sendable {
    case claude, codex

    public init?(provider: ProviderID) {
        switch provider {
        case .claude:
            self = .claude
        case .codex:
            self = .codex
        case .cursor:
            return nil
        }
    }

    public var provider: ProviderID {
        switch self {
        case .claude:
            .claude
        case .codex:
            .codex
        }
    }

    public var providerLabel: String {
        switch self {
        case .claude:
            "Claude API"
        case .codex:
            "OpenAI API"
        }
    }

    public var destination: URL {
        switch self {
        case .claude:
            URL(string: "https://platform.claude.com/settings/billing")!
        case .codex:
            URL(string: "https://platform.openai.com/settings/organization/billing/overview")!
        }
    }
}

@MainActor
public enum ProviderAPIBillingActionRouter {
    @discardableResult
    public static func open(
        _ action: ProviderAPIBillingAction,
        using opener: (URL) -> Bool = NSWorkspace.shared.open
    ) -> Bool {
        opener(action.destination)
    }
}
