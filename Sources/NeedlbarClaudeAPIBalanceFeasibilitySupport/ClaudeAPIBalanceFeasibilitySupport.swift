import Foundation
import Darwin

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

public struct ClaudeAPIBalanceFeasibilityCallback: Equatable, Sendable {
    public let generation: UInt64
    public let navigationID: UInt64
}

public struct ClaudeAPIBalanceFeasibilityFailure: Equatable, Sendable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-".unicodeScalars)
        self.domain = !domain.isEmpty && domain.unicodeScalars.count <= 128 &&
            domain.unicodeScalars.allSatisfy(allowed.contains) ? domain : "invalid"
        self.code = code
    }
}

public enum ClaudeAPIBalanceFeasibilityFeedbackStatus: Equatable, Sendable {
    case loading, billingRouteLoaded, inspectionUnavailable, inspectionRequiresBillingRoute
    case inspectionCounts(sections: Int, labels: Int), unavailable(ClaudeAPIBalanceFeasibilityFailure)

    public var displayText: String {
        switch self {
        case .loading: "Loading approved billing page"
        case .billingRouteLoaded: "Page loaded — authentication unproven"
        case let .inspectionCounts(sections, labels): "Inspection counts: sections \(sections), labels \(labels) — success unproven"
        case .inspectionUnavailable: "Inspection unavailable"
        case .inspectionRequiresBillingRoute: "Inspect the approved billing page first"
        case let .unavailable(failure): "Unavailable: \(failure.domain) (\(failure.code))"
        }
    }
}

public struct ClaudeAPIBalanceFeasibilityFeedbackEmission: Equatable, Sendable {
    public let status: ClaudeAPIBalanceFeasibilityFeedbackStatus
    public let eventLine: String
}

public struct ClaudeAPIBalanceFeasibilityFeedback: Sendable {
    private var generation: UInt64 = 0
    private var current: ClaudeAPIBalanceFeasibilityCallback?

    public init() {}

    public mutating func beginNavigation(navigationID: UInt64, approvedOrigin: Bool, approvedBillingRoute: Bool) -> (callback: ClaudeAPIBalanceFeasibilityCallback, emission: ClaudeAPIBalanceFeasibilityFeedbackEmission) {
        generation &+= 1
        let callback = ClaudeAPIBalanceFeasibilityCallback(generation: generation, navigationID: navigationID)
        current = callback
        return (callback, emit(.loading, "navigationStarted approvedOrigin=\(approvedOrigin) approvedBillingRoute=\(approvedBillingRoute)"))
    }

    public func isCurrent(_ callback: ClaudeAPIBalanceFeasibilityCallback) -> Bool { current == callback }
    public mutating func invalidate() { generation &+= 1; current = nil }

    public func routeLoaded(for callback: ClaudeAPIBalanceFeasibilityCallback, isExactBillingRoute: Bool) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? {
        guard isCurrent(callback), isExactBillingRoute else { return nil }
        return emit(.billingRouteLoaded, "billingRouteLoaded=true authenticationProven=false")
    }

    public func inspectionCounts(for callback: ClaudeAPIBalanceFeasibilityCallback, isExactBillingRoute: Bool, sections: Int, labels: Int) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? {
        guard isCurrent(callback), isExactBillingRoute else { return nil }
        return emit(.inspectionCounts(sections: sections, labels: labels), "creditBalanceSectionCount=\(sections) remainingBalanceLabelCount=\(labels) successProven=false")
    }

    public func inspectionUnavailable(for callback: ClaudeAPIBalanceFeasibilityCallback, isExactBillingRoute: Bool) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? {
        guard isCurrent(callback), isExactBillingRoute else { return nil }
        return emit(.inspectionUnavailable, "domProbe=unavailable")
    }

    public func inspectionRequiresBillingRoute() -> ClaudeAPIBalanceFeasibilityFeedbackEmission {
        emit(.inspectionRequiresBillingRoute, "domProbe=notOnApprovedBillingRoute")
    }

    public func provisionalFailure(for callback: ClaudeAPIBalanceFeasibilityCallback, isAllowedOrigin: Bool, failure: ClaudeAPIBalanceFeasibilityFailure) -> ClaudeAPIBalanceFeasibilityFeedbackEmission? {
        guard isCurrent(callback), isAllowedOrigin else { return nil }
        return emit(.unavailable(failure), "provisionalLoad=failed domain=\(failure.domain) code=\(failure.code)")
    }

    private func emit(_ status: ClaudeAPIBalanceFeasibilityFeedbackStatus, _ payload: String) -> ClaudeAPIBalanceFeasibilityFeedbackEmission {
        .init(status: status, eventLine: "CLAUDE_API_BALANCE_FEASIBILITY \(payload)")
    }
}

public struct ClaudeAPIBalanceFeasibilityEventWriter: Sendable {
    public let fileDescriptor: Int32

    public init(fileDescriptor: Int32) { self.fileDescriptor = fileDescriptor }

    public func write(_ line: String) {
        let bytes = Array((line + "\n").utf8)
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fileDescriptor, base.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { return }
                offset += Int(count)
            }
        }
    }
}
