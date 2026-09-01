import AppKit
import Combine
import NeedlbarCore
import SwiftUI

@MainActor
public final class AnalyticsViewModel: ObservableObject {
    public enum PresentationState: Equatable, Sendable {
        case idle
        case loading
        case fresh
        case stale
        case unavailable
    }

    @Published public private(set) var state: AnalyticsRefreshState = .idle

    private let store: AnalyticsSnapshotStore
    private let repository: any AnalyticsRepository
    private var hasLoaded = false
    private var refreshTask: Task<Void, Never>?

    public init(store: AnalyticsSnapshotStore, repository: any AnalyticsRepository) {
        self.store = store
        self.repository = repository
    }

    public var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    public var presentationState: PresentationState {
        switch state {
        case .idle: .idle
        case .loading: .loading
        case .fresh: .fresh
        case .stale: .stale
        case .unavailable: .unavailable
        }
    }

    public var snapshot: AnalyticsSnapshot? {
        switch state {
        case let .fresh(snapshot), let .stale(snapshot): snapshot
        case .idle, .loading, .unavailable: nil
        }
    }

    public var statusCopy: String {
        switch state {
        case .idle:
            "Open Analytics to inspect local repository usage."
        case .loading:
            "Analyzing local repository data…"
        case let .fresh(snapshot):
            Self.isPartial(snapshot)
                ? "Some local usage or repository coverage is partial."
                : "Local analysis complete."
        case .stale:
            "Showing the last successful local analysis. Refresh to try again."
        case .unavailable:
            "Analytics unavailable. Refresh to try again."
        }
    }

    public func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        refresh()
    }

    public func refresh() {
        guard !isLoading else { return }
        state = .loading
        let store = self.store
        let repository = self.repository
        refreshTask = Task { @MainActor [weak self] in
            _ = await store.refresh(using: repository)
            guard let self else { return }
            self.state = await store.state
            self.refreshTask = nil
        }
    }

    private static func isPartial(_ snapshot: AnalyticsSnapshot) -> Bool {
        if !snapshot.errors.isEmpty || !snapshot.coverage.reasons.isEmpty || !snapshot.unattributed.reasons.isEmpty {
            return true
        }
        return snapshot.repositories.contains {
            $0.coverage.timingPartial || !$0.coverage.reasons.isEmpty || $0.state == "unavailable"
        }
    }

    deinit {
        refreshTask?.cancel()
    }
}

@MainActor
public final class AnalyticsWindowController: NSWindowController {
    public let viewModel: AnalyticsViewModel

    public init(store: AnalyticsSnapshotStore, repository: any AnalyticsRepository) {
        viewModel = AnalyticsViewModel(store: store, repository: repository)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Needlbar Analytics"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: AnalyticsView(viewModel: viewModel))
        window.setFrame(NSRect(x: 0, y: 0, width: 760, height: 520), display: false)
        super.init(window: window)
    }

    @available(*, unavailable)
    required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showAnalytics() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp?.activate(ignoringOtherApps: true)
        viewModel.loadIfNeeded()
    }

    public func refreshAnalytics() {
        viewModel.refresh()
    }
}
