import Foundation
import NeedlbarCore
import UserNotifications

public enum QuotaNotificationAuthorization: Sendable {
    case authorized
    case denied
    case notDetermined
    case provisional
    case unavailable
}

public enum QuotaNotificationSubmission: Sendable {
    case submitted
    case failed
}

public protocol QuotaNotificationClient: Sendable {
    func currentAuthorization() async -> QuotaNotificationAuthorization
    func requestAuthorization() async -> QuotaNotificationAuthorization
    func submit(body: String) async -> QuotaNotificationSubmission
}

public struct SystemQuotaNotificationClient: QuotaNotificationClient {
    public init() {}

    public func currentAuthorization() async -> QuotaNotificationAuthorization {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: Self.map(settings.authorizationStatus))
            }
        }
    }

    public func requestAuthorization() async -> QuotaNotificationAuthorization {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert])
        return await currentAuthorization()
    }

    public func submit(body: String) async -> QuotaNotificationSubmission {
        let content = UNMutableNotificationContent()
        content.title = "Needlbar"
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return .submitted
        } catch {
            return .failed
        }
    }

    private static func map(_ value: UNAuthorizationStatus) -> QuotaNotificationAuthorization {
        switch value {
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        case .provisional:
            .provisional
        @unknown default:
            .unavailable
        }
    }
}

@MainActor
public final class QuotaNotificationService {
    private let store: ProviderSnapshotStore
    private let preferences: QuotaNotificationPreferences
    private let client: any QuotaNotificationClient
    private let ledgerStore: any QuotaAlertLedgerStoring
    private let now: () -> Date
    private let policy = QuotaAlertPolicy()

    private var ledger: QuotaAlertLedger = .empty
    private var ledgerReady = false
    private var seenRevisions: [ProviderID: UInt64] = [:]
    private var baselinedKeys: Set<QuotaAlertKey> = []
    private var runGeneration: UInt64 = 0
    private var admissionGeneration: UInt64 = 0
    private var isRunning = false
    private var signalTask: Task<Void, Never>?
    private var workTask: Task<Void, Never>?
    private var nextWorkID: UInt64 = 0
    private var activeWorkID: UInt64 = 0
    private var needsEvaluation = false

    public init(
        store: ProviderSnapshotStore,
        preferences: QuotaNotificationPreferences,
        client: any QuotaNotificationClient = SystemQuotaNotificationClient(),
        ledgerStore: any QuotaAlertLedgerStoring = QuotaAlertLedgerStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.preferences = preferences
        self.client = client
        self.ledgerStore = ledgerStore
        self.now = now
    }

    public func start() async {
        guard !isRunning else { return }

        isRunning = true
        ledgerReady = false
        runGeneration &+= 1
        let listenerGeneration = runGeneration
        let signals = await store.quotaAlertChangeSignals()
        guard isRunning, runGeneration == listenerGeneration else { return }

        signalTask = Task { [weak self] in
            for await _ in signals {
                guard let self,
                      !Task.isCancelled,
                      self.isRunning,
                      self.runGeneration == listenerGeneration
                else {
                    return
                }
                self.scheduleEvaluation()
            }
        }

        if let oldWork = workTask {
            await oldWork.value
        }
        guard isRunning, runGeneration == listenerGeneration else { return }

        let loaded = (try? await ledgerStore.load()) ?? .empty
        guard isRunning, runGeneration == listenerGeneration else { return }
        ledger = loaded
        ledgerReady = true
        scheduleEvaluation()
    }

    public func stop() {
        isRunning = false
        ledgerReady = false
        runGeneration &+= 1
        admissionGeneration &+= 1
        needsEvaluation = false
        seenRevisions = [:]
        baselinedKeys = []
        signalTask?.cancel()
        signalTask = nil
        workTask?.cancel()
    }

    public func setEnabledFromSettings(_ enabled: Bool) async {
        admissionGeneration &+= 1
        needsEvaluation = false
        seenRevisions = [:]
        baselinedKeys = []
        workTask?.cancel()

        guard enabled else {
            preferences.setEnabled(false)
            return
        }

        let requestGeneration = admissionGeneration
        let authorization = await client.requestAuthorization()
        guard isRunning, admissionGeneration == requestGeneration else { return }
        guard authorization == .authorized else {
            preferences.setUnavailable()
            return
        }

        preferences.setEnabled(true)
        scheduleEvaluation()
    }

#if DEBUG
    func reconcileLatestForTesting() async {
        guard isRunning, ledgerReady else { return }
        scheduleEvaluation()
    }

    func waitUntilIdle() async {
        while let workTask {
            await workTask.value
        }
    }
#endif

    private func scheduleEvaluation() {
        guard isRunning, ledgerReady, preferences.isEnabled else { return }
        needsEvaluation = true
        guard workTask == nil else { return }

        let taskGeneration = admissionGeneration
        nextWorkID &+= 1
        let workID = nextWorkID
        activeWorkID = workID
        workTask = Task { [weak self] in
            defer {
                if let self, self.activeWorkID == workID {
                    self.workTask = nil
                    if self.needsEvaluation {
                        self.scheduleEvaluation()
                    }
                }
            }

            while let self,
                  self.needsEvaluation,
                  !Task.isCancelled,
                  self.isRunning,
                  self.ledgerReady,
                  self.admissionGeneration == taskGeneration
            {
                self.needsEvaluation = false
                await self.evaluateLatest(generation: taskGeneration)
            }
        }
    }

    private func evaluateLatest(generation expectedGeneration: UInt64) async {
        guard isRunning,
              ledgerReady,
              preferences.isEnabled,
              admissionGeneration == expectedGeneration
        else {
            return
        }

        let samples = await store.quotaAlertCapture()
        guard isRunning,
              ledgerReady,
              preferences.isEnabled,
              admissionGeneration == expectedGeneration
        else {
            return
        }

        for sample in samples {
            guard isRunning,
                  ledgerReady,
                  preferences.isEnabled,
                  admissionGeneration == expectedGeneration
            else {
                return
            }
            guard sample.provider == .claude || sample.provider == .codex,
                  sample.revision != seenRevisions[sample.provider]
            else {
                continue
            }

            seenRevisions[sample.provider] = sample.revision
            for observation in makeObservations(sample, now: now()) {
                await evaluate(observation, from: sample, generation: expectedGeneration)
                guard isRunning,
                      ledgerReady,
                      preferences.isEnabled,
                      admissionGeneration == expectedGeneration
                else {
                    return
                }
            }
        }
    }

    private func evaluate(
        _ observation: QuotaAlertObservation,
        from sample: QuotaAlertSample,
        generation expectedGeneration: UInt64
    ) async {
        guard isRunning,
              ledgerReady,
              preferences.isEnabled,
              admissionGeneration == expectedGeneration
        else {
            return
        }

        let authorization = await client.currentAuthorization()
        guard authorization == .authorized else {
            if isRunning, ledgerReady, admissionGeneration == expectedGeneration {
                preferences.setUnavailable()
            }
            return
        }

        let currentBeforeReservation = await isCurrent(sample, observation: observation, at: now())
        guard isRunning,
              ledgerReady,
              preferences.isEnabled,
              admissionGeneration == expectedGeneration,
              currentBeforeReservation
        else {
            return
        }

        let decision = policy.observe(
            observation,
            ledger: ledger,
            now: now(),
            processHasEstablishedBaseline: baselinedKeys.contains(observation.key)
        )
        do {
            try await ledgerStore.save(decision.ledger)
        } catch {
            ledger = (try? await ledgerStore.load()) ?? ledger
            return
        }

        guard isRunning,
              ledgerReady,
              preferences.isEnabled,
              admissionGeneration == expectedGeneration,
              !Task.isCancelled
        else {
            ledger = (try? await ledgerStore.load()) ?? ledger
            return
        }

        ledger = decision.ledger
        baselinedKeys.insert(observation.key)

        let postSaveAuthorization = await client.currentAuthorization()
        guard isRunning,
              ledgerReady,
              preferences.isEnabled,
              admissionGeneration == expectedGeneration
        else {
            return
        }
        guard postSaveAuthorization == .authorized else {
            preferences.setUnavailable()
            return
        }

        let currentBeforeSubmit = await isCurrent(sample, observation: observation, at: now())
        guard isRunning,
              ledgerReady,
              preferences.isEnabled,
              admissionGeneration == expectedGeneration,
              currentBeforeSubmit,
              let stage = decision.stage
        else {
            return
        }

        _ = await client.submit(body: copy(provider: sample.provider, stage: stage))
    }

    private func makeObservations(_ sample: QuotaAlertSample, now: Date) -> [QuotaAlertObservation] {
        guard sample.status == .fresh,
              let successfulAt = sample.lastSuccessfulAt,
              successfulAt <= now,
              now.timeIntervalSince(successfulAt) < 15 * 60,
              let quota = sample.quota
        else {
            return []
        }

        return quota.windows
            .filter { isAllowed(provider: sample.provider, id: $0.id) }
            .sorted { $0.id < $1.id }
            .compactMap { window in
                guard let key = try? QuotaAlertKey(provider: sample.provider, windowID: window.id) else {
                    return nil
                }
                return QuotaAlertObservation(
                    key: key,
                    remainingPercent: window.remainingPercent,
                    resetsAt: window.resetsAt,
                    successfulAt: successfulAt,
                    revision: sample.revision
                )
            }
    }

    private func isCurrent(
        _ original: QuotaAlertSample,
        observation: QuotaAlertObservation,
        at now: Date
    ) async -> Bool {
        let current = await store.currentQuotaAlertSample(for: original.provider)
        return current.revision == original.revision
            && current.lastSuccessfulAt == original.lastSuccessfulAt
            && current.status == .fresh
            && current.quota == original.quota
            && makeObservations(current, now: now).contains {
                $0.key == observation.key
                    && $0.remainingPercent == observation.remainingPercent
                    && $0.resetsAt == observation.resetsAt
            }
    }

    private func isAllowed(provider: ProviderID, id: String) -> Bool {
        switch (provider, id) {
        case (.claude, "claude.session"),
             (.claude, "claude.weekly"),
             (.codex, "codex.primary"),
             (.codex, "codex.secondary"):
            true
        default:
            false
        }
    }

    private func copy(provider: ProviderID, stage: QuotaAlertStage) -> String {
        let name = provider == .claude ? "Claude" : "Codex"
        return "\(name) quota: \(stage.rawValue)% or less remaining."
    }
}
