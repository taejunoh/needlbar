import AppKit
import NeedlbarCore

enum ProviderAPIBillingAction: Equatable, Sendable {
    case claude, codex

    init?(provider: ProviderID) {
        switch provider {
        case .claude:
            self = .claude
        case .codex:
            self = .codex
        case .cursor:
            return nil
        }
    }

    var provider: ProviderID {
        switch self {
        case .claude:
            .claude
        case .codex:
            .codex
        }
    }

    var providerLabel: String {
        switch self {
        case .claude:
            "Claude API"
        case .codex:
            "OpenAI API"
        }
    }

    var destination: URL {
        switch self {
        case .claude:
            URL(string: "https://platform.claude.com/settings/billing")!
        case .codex:
            URL(string: "https://platform.openai.com/settings/organization/billing/overview")!
        }
    }
}

@MainActor
enum ProviderAPIBillingActionRouter {
    @discardableResult
    static func open(
        _ action: ProviderAPIBillingAction,
        using opener: (URL) -> Bool = NSWorkspace.shared.open
    ) -> Bool {
        opener(action.destination)
    }
}
