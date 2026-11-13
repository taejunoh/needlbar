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

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func column(_ provider: WidgetProvider) -> WidgetQuotaColumn {
        WidgetPresentation.quotaColumn(
            for: provider,
            in: entry.projection,
            now: entry.date,
            calendar: calendar,
            locale: .current
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 14) {
                QuotaColumnView(column: column(.claude), accent: .orange)
                QuotaColumnView(column: column(.codex), accent: .blue)
            }
            Spacer(minLength: 0)
            if let footer = WidgetPresentation.todayFooter(entry.projection, now: entry.date) {
                HStack {
                    Text(footer.tokens)
                    Spacer()
                    Text(footer.cost)
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
        .widgetURL(URL(string: "needlbar://overview"))
    }
}

private struct QuotaColumnView: View {
    let column: WidgetQuotaColumn
    let accent: Color

    private var warning: Color? {
        switch column.level {
        case .critical: .red
        case .low: .orange
        case .normal, nil: nil
        }
    }

    private func fableColor(_ level: WidgetRemainingLevel?) -> Color {
        switch level {
        case .critical: return .red
        case .low: return .orange
        case .normal, nil: return .secondary
        }
    }

    private var figure: some View {
        Text(column.figure)
            .font(.system(size: 36, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(warning ?? Color.primary)
            .opacity(column.isDimmed ? 0.45 : 1)
    }

    private func fableText(_ text: String, level: WidgetRemainingLevel?) -> some View {
        Text(text)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(fableColor(level))
            .fixedSize()
    }

    // The Fable text sits beside the figure and never shrinks it: one line when it fits, two
    // lines (the value on the figure's baseline) when it does not, otherwise the figure alone.
    @ViewBuilder
    private var figureRow: some View {
        if let fable = column.fable {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    figure.fixedSize()
                    fableText(fable.text, level: fable.level)
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    figure.fixedSize()
                    fableText(fable.text.replacingOccurrences(of: " ", with: "\n"), level: fable.level)
                }
                figure
            }
        } else {
            figure
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(column.title)
                .font(.headline)
            figureRow
            QuotaBar(fraction: column.fraction, fill: warning ?? accent)
                .opacity(column.isDimmed ? 0.45 : 1)
            Text(column.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(column.accessibilityLabel)
    }
}

private struct QuotaBar: View {
    let fraction: Double?
    let fill: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 2).frame(maxHeight: .infinity)
                if let fraction {
                    Capsule()
                        .fill(fill)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
        }
        .frame(height: 6)
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
