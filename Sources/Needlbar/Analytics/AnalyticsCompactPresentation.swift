import Foundation

enum AnalyticsCompactPresentation {
    static let estimateQualifier = "Estimated cost · not a bill"
    static let countsQualification = "Counts use different units and may overlap. They are not a total."
    static func wideRows(_ width: CGFloat) -> Bool { width >= 680 }
    static func repositoryID(_ id: String) -> String { "repository-\(id)" }
    static func diagnosticID(_ code: String) -> String { "diagnostic-\(code)" }
    static func statusTitle(_ status: AnalyticsDashboardStatus) -> String {
        if case .partial = status { return "Partial coverage" }
        return status.text
    }
    static func quality(cost: String, timing: String) -> String? {
        let parts = [cost == "Complete" ? nil : "Cost \(cost)",
                     timing == "Complete" ? nil : "Timing \(timing)"].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    static func diagnosticContext(_ code: String) -> String {
        switch code {
        case "missingDuration": "Response duration missing"
        case "missingTimestamp": "Period coverage incomplete"
        case "recordLimitReached": "Mixed processing limits"
        case "gitOutputLimitReached": "Inspection output bounded"
        case "gitTimedOut", "gitUnavailable": "Inspection unavailable or incomplete"
        default: "Limited evidence"
        }
    }
}
