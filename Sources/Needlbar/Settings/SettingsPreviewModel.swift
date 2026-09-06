import Combine
import Foundation
import NeedlbarCore

@MainActor
public final class SettingsPreviewModel: ObservableObject {
    @Published public private(set) var result: MenuBarDashboardRenderResult
    public init() {
        result = MenuBarDashboardRenderer.render(snapshot: CombinedUsageSnapshot(
            system: nil, providers: [], capturedAt: .distantPast, systemAvailability: [:]),
            configuration: SystemMonitorConfiguration(), availableWidth: 240)
    }
    public func update(snapshot: CombinedUsageSnapshot, configuration: SystemMonitorConfiguration) {
        result = MenuBarDashboardRenderer.render(snapshot: snapshot, configuration: configuration, availableWidth: 240)
    }
}
