import Combine
import Foundation
import NeedlbarCore

/// Tells the refresh coordinator whether automatic Claude runs are allowed: the
/// user's setting and Claude being shown. Each value is computed on the main
/// actor from the current state and sent through one serial channel, so values
/// reach the coordinator in the order they were computed and the last one it
/// applies is the current one.
@MainActor
final class ClaudeAutomaticRunsRelay {
    private let preferences: ClaudeAutomaticChecksPreferences
    private let configuration: ModuleConfiguration
    private let continuation: AsyncStream<Bool>.Continuation
    private var preferenceObservation: AnyCancellable?
    private var configurationObserver: NSObjectProtocol?

    init(
        preferences: ClaudeAutomaticChecksPreferences,
        configuration: ModuleConfiguration,
        apply: @escaping @Sendable (Bool) async -> Void
    ) {
        self.preferences = preferences
        self.configuration = configuration
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        self.continuation = continuation
        // The single consumer: one value is applied before the next is read.
        Task {
            for await allowed in stream {
                await apply(allowed)
            }
        }
        // `@Published` reports a change before it is stored, so the value is
        // read again on the next main-actor turn rather than taken from here.
        preferenceObservation = preferences.$isEnabled.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.push() }
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: ModuleConfiguration.didChangeNotification,
            object: configuration,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.push() }
        }
    }

    /// The value the coordinator should hold now.
    var allowed: Bool {
        preferences.isEnabled && claudeIsShown(configuration.systemMonitor)
    }

    func push() {
        continuation.yield(allowed)
    }

    func stop() {
        preferenceObservation = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        continuation.finish()
    }
}
