import AppKit
import NeedlbarCore
import Network

@MainActor protocol QuotaPathMonitoring: AnyObject {
    func start(_ receive: @escaping @MainActor @Sendable (Bool) -> Void)
    func cancel()
}

@MainActor protocol QuotaRecoveryMonitoring: AnyObject {
    func start(using token: QuotaRecoveryRequestToken)
    func stop()
}

@MainActor final class QuotaRecoveryMonitor: QuotaRecoveryMonitoring {
    private let center: NotificationCenter
    private let makePath: @MainActor () -> any QuotaPathMonitoring
    private var observer: NSObjectProtocol?
    private var path: (any QuotaPathMonitoring)?
    private var lastSatisfied: Bool?
    private var generation: UInt64 = 0

    init(center: NotificationCenter = NSWorkspace.shared.notificationCenter,
         makePath: @escaping @MainActor () -> any QuotaPathMonitoring = { NetworkQuotaPathMonitor() }) {
        self.center = center
        self.makePath = makePath
    }

    func start(using token: QuotaRecoveryRequestToken) {
        guard path == nil else { return }
        let generation = generation
        observer = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) {
            [weak self, token] _ in
            Task { @MainActor [weak self, token] in
                guard let self, self.generation == generation, self.path != nil else { return }
                await token.submit(.wake)
            }
        }
        let path = makePath()
        self.path = path
        path.start { [weak self, token] satisfied in
            guard let self, self.generation == generation, self.path != nil else { return }
            let recovered = self.lastSatisfied == false && satisfied
            self.lastSatisfied = satisfied
            guard recovered else { return }
            Task { @MainActor [weak self, token] in
                guard let self, self.generation == generation, self.path != nil else { return }
                await token.submit(.connectivity)
            }
        }
    }

    func stop() {
        generation &+= 1
        if let observer { center.removeObserver(observer) }
        observer = nil
        path?.cancel()
        path = nil
        lastSatisfied = nil
    }
}

@MainActor private final class NetworkQuotaPathMonitor: QuotaPathMonitoring {
    private let monitor = NWPathMonitor()

    func start(_ receive: @escaping @MainActor @Sendable (Bool) -> Void) {
        monitor.pathUpdateHandler = { path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in receive(satisfied) }
        }
        monitor.start(queue: DispatchQueue(label: "com.taejunoh.needlbar.quota-path"))
    }

    func cancel() { monitor.cancel() }
}
