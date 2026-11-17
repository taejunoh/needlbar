import Foundation

/// Whether Claude is shown anywhere the user can see it in the app: in the AI
/// module on the menu bar, or in the AI section of the dashboard. Automatic
/// `/usage` runs pause while this is false. The widget and notifications do not
/// count. The legacy `needlbar.menuBar.claude.enabled` flag matters only as
/// `ModuleConfiguration`'s last fallback when no newer visibility key exists.
public func claudeIsShown(_ configuration: SystemMonitorConfiguration) -> Bool {
    let claude = configuration.ai[.claude] ?? AIProviderDisplayPreference()
    let onMenuBar = configuration.menuBarVisibleModules.contains(.ai) && claude.menuBarVisible
    let onDashboard = configuration.dashboardVisibleModules.contains(.ai) && claude.dashboardVisible
    return onMenuBar || onDashboard
}
