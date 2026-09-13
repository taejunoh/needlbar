import Foundation

public enum ClaudeAPIBalanceFeasibilityMode: Equatable, Sendable {
    case run
    case clear
}

public enum ClaudeAPIBalanceFeasibilityLaunchError: Error, Equatable, Sendable {
    case invalidArguments
}

public enum ClaudeAPIBalanceFeasibilityLaunch {
    public static func parse(arguments: [String]) throws -> ClaudeAPIBalanceFeasibilityMode {
        guard arguments.count == 2 else {
            throw ClaudeAPIBalanceFeasibilityLaunchError.invalidArguments
        }

        switch arguments[1] {
        case "--claude-api-balance-feasibility":
            return .run
        case "--clear-claude-api-balance-feasibility-store":
            return .clear
        default:
            throw ClaudeAPIBalanceFeasibilityLaunchError.invalidArguments
        }
    }
}

public enum ClaudeAPIBalanceFeasibilityStore {
    public static let identifier = UUID(uuidString: "27B56380-7838-4B83-B1A8-A9B408524E9B")!
    public static let billingURL = URL(string: "https://platform.claude.com/settings/billing")!
}

public enum ClaudeAPIBalanceFeasibilityNavigationEvent: Equatable, Sendable {
    case allowedPlatformOrigin
    case blockedOrigin(String)
}

public enum ClaudeAPIBalanceFeasibilityNavigationPolicy {
    public static func event(for url: URL) -> ClaudeAPIBalanceFeasibilityNavigationEvent {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "platform.claude.com",
              (url.port ?? 443) == 443,
              url.user == nil,
              url.password == nil
        else {
            return .blockedOrigin(sanitizedOrigin(for: url))
        }

        return .allowedPlatformOrigin
    }

    public static func allows(_ url: URL) -> Bool {
        if case .allowedPlatformOrigin = event(for: url) {
            return true
        }

        return false
    }

    public static func isBillingRoute(_ url: URL) -> Bool {
        allows(url) && url.path == "/settings/billing" && url.query == nil && url.fragment == nil
    }

    private static func sanitizedOrigin(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? "invalid"
        let host = url.host?.lowercased() ?? "invalid"
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}
