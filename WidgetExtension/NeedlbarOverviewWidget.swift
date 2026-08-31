import Foundation
import SwiftUI
import WidgetKit

private enum WidgetSharedFile {
    static func url(bundle: Bundle = .main, fileManager: FileManager = .default) -> URL {
        let fallback = URL(fileURLWithPath: "/dev/null")
        guard let identifier = bundle.object(forInfoDictionaryKey: "NeedlbarAppGroupIdentifier") as? String,
              let directory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            return fallback
        }
        return directory.appendingPathComponent("NeedlbarWidgetProjection.json", isDirectory: false)
    }
}

private func readProjectionBytes(at url: URL) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let limit = WidgetProjection.maximumEncodedBytes + 1
    guard let bytes = try handle.read(upToCount: limit), bytes.count <= WidgetProjection.maximumEncodedBytes else {
        throw WidgetProjectionError.tooLarge
    }
    return bytes
}

struct OverviewEntry: TimelineEntry {
    let date: Date
    let projection: WidgetProjection?
}

struct OverviewProvider: TimelineProvider {
    func placeholder(in context: Context) -> OverviewEntry {
        .init(date: .now, projection: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (OverviewEntry) -> Void) {
        completion(load(now: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<OverviewEntry>) -> Void) {
        let entry = load(now: .now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let policy = entry.projection.map {
            TimelineReloadPolicy.after(WidgetPresentation.nextDeadline(after: entry.date, projection: $0, calendar: calendar))
        } ?? .after(entry.date.addingTimeInterval(15 * 60))
        completion(Timeline(entries: [entry], policy: policy))
    }

    private func load(now: Date) -> OverviewEntry {
        guard let bytes = try? readProjectionBytes(at: WidgetSharedFile.url()),
              let projection = try? WidgetProjection.decode(bytes, referenceDate: now) else {
            return .init(date: now, projection: nil)
        }
        return .init(date: now, projection: projection)
    }
}

struct OverviewWidgetView: View {
    let entry: OverviewEntry

    private var overallFreshnessLabel: String {
        guard let projection = entry.projection else { return "Quota unavailable" }
        let rows = projection.quotaRows.map { ($0.stream, $0.lastSuccessfulAt) }
            + projection.usageRows.map { ($0.stream, $0.lastSuccessfulAt) }
        return rows.allSatisfy {
            WidgetPresentation.freshness($0.0, lastSuccessfulAt: $0.1, now: entry.date) == .fresh
        } ? "Fresh" : "Stale"
    }

    private var todayLabel: String {
        guard let projection = entry.projection else {
            return "Today unavailable"
        }
        let contributors = projection.usageRows.filter {
            WidgetPresentation.todayIsCurrent($0, now: entry.date)
                && $0.todayTokens != nil
                && $0.todayCostUSD != nil
        }
        let values = contributors.compactMap { row -> (UInt64, Decimal)? in
            guard let tokens = row.todayTokens, let cost = row.todayCostUSD else { return nil }
            return (tokens, cost)
        }
        guard !values.isEmpty else { return "Today unavailable" }
        var tokens: UInt64 = 0
        var cost = Decimal.zero
        for value in values {
            let (next, overflow) = tokens.addingReportingOverflow(value.0)
            guard !overflow else { return "Today unavailable" }
            tokens = next
            var left = cost
            var right = value.1
            var result = Decimal()
            guard NSDecimalAdd(&result, &left, &right, .plain) == .noError else {
                return "Today unavailable"
            }
            cost = result
        }
        let completeness = values.count < 3 ? "Partial" : "Complete"
        let freshness = contributors.allSatisfy {
            WidgetPresentation.freshness($0.stream, lastSuccessfulAt: $0.lastSuccessfulAt, now: entry.date) == .fresh
        } ? "Fresh" : "Stale"
        return "\(completeness) · \(freshness) · Tokens: \(tokens)  Cost: \(NSDecimalNumber(decimal: cost).stringValue)"
    }

    private var todayUpdatedLabel: String {
        guard let projection = entry.projection else { return "Today updated: —" }
        let formatter = timestampFormatter
        let contributors = projection.usageRows.filter {
            WidgetPresentation.todayIsCurrent($0, now: entry.date)
                && $0.todayTokens != nil
                && $0.todayCostUSD != nil
        }
        guard !contributors.isEmpty else { return "Today updated: —" }
        return "Today updated: " + contributors.map {
            "\(providerLabel($0.provider)): \($0.lastSuccessfulAt.map { formatter.string(from: $0) } ?? "—")"
        }.joined(separator: " · ")
    }

    @ViewBuilder private func quotaLine(_ provider: WidgetProvider, title: String) -> some View {
        let row = entry.projection?.quotaRows.first(where: { $0.provider == provider })
        if let headline = row?.headline {
            let formatter = timestampFormatter
            let reset = WidgetPresentation.resetLabel(headline.resetsAt, now: entry.date, formatter: formatter) ?? "—"
            HStack {
                Text("\(title) \(headline.id.categoryLabel): \(Int(headline.remainingPercent.rounded()))%")
                Spacer()
                Text(reset)
            }
            Text(WidgetPresentation.freshness(row!.stream, lastSuccessfulAt: row!.lastSuccessfulAt, now: entry.date) == .fresh
                ? "Fresh · \(row!.lastSuccessfulAt.map { formatter.string(from: $0) } ?? "—")"
                : "Stale · \(row!.lastSuccessfulAt.map { formatter.string(from: $0) } ?? "—")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("\(title) — Quota unavailable")
        }
    }

    private func providerLabel(_ provider: WidgetProvider) -> String {
        switch provider {
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }

    private var timestampFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Needlbar").font(.headline)
                Spacer()
                Text(overallFreshnessLabel).font(.caption).foregroundStyle(.secondary)
            }
            quotaLine(.claude, title: "Claude")
            quotaLine(.codex, title: "Codex")
            Text("Cursor — Quota unavailable · local cached usage only")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("Today").font(.caption)
                Spacer()
                Text(todayLabel).font(.caption).monospacedDigit()
            }
            Text(todayUpdatedLabel).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .widgetURL(URL(string: "needlbar://overview"))
    }
}

struct NeedlbarOverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NeedlbarOverview", provider: OverviewProvider()) {
            OverviewWidgetView(entry: $0).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Overview")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct NeedlbarWidgetBundle: WidgetBundle {
    var body: some Widget {
        NeedlbarOverviewWidget()
    }
}
