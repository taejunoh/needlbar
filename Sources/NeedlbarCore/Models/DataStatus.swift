import Foundation

public enum DataStatus: Sendable, Equatable {
    case fresh
    case stale(lastSuccessfulAt: Date)
    case unavailable
    case requiresAuthentication
    case error(message: String, lastSuccessfulAt: Date?)
}
