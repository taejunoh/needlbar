import Foundation

public enum MetricFormatter {
    public static func tokens(_ value: UInt64) -> String {
        switch value {
        case 1_000_000...:
            compact(Double(value) / 1_000_000, suffix: "M")
        case 1_000...:
            compact(Double(value) / 1_000, suffix: "K")
        default:
            String(value)
        }
    }

    public static func costUSD(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return "$\(formatter.string(from: value as NSDecimalNumber) ?? "0.00")"
    }

    public static func quotaRemaining(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    public static func reset(
        _ date: Date?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String? {
        guard let date else { return nil }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func compact(_ value: Double, suffix: String) -> String {
        let formatted = String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return formatted + suffix
    }
}
