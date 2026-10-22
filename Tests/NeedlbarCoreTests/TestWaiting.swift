import Foundation

// Waiting helpers for tests that drive concurrent code through test doubles.
// A readiness wait must never give up silently: proceeding without its
// condition lets a test act in the wrong order (for example advance a manual
// clock before a loop sleeps on it) and fail or stall later. Every wait here
// ends only when its condition holds or when the waiting task is cancelled,
// for example by a test time limit, so a missed wakeup fails that test
// instead of stalling the whole run.

/// Lets test code suspend until a condition over a test double's state holds.
/// A double calls `signal()` after every change that a condition may read, and
/// never while holding its own lock, because conditions run under this lock.
final class ConditionWaiters: @unchecked Sendable {
    private struct Waiter {
        let condition: @Sendable () -> Bool
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var waiters: [UUID: Waiter] = [:]

    func wait(until condition: @escaping @Sendable () -> Bool) async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Checking and registering under one lock means a signal
                // either finds this waiter or changed the state before the check.
                let ready = lock.withLock { () -> Bool in
                    if Task.isCancelled || condition() { return true }
                    waiters[id] = Waiter(condition: condition, continuation: continuation)
                    return false
                }
                if ready { continuation.resume() }
            }
        } onCancel: {
            lock.withLock { waiters.removeValue(forKey: id) }?.continuation.resume()
        }
    }

    func signal() {
        let ready = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            let due = waiters.filter { $0.value.condition() }
            for id in due.keys { waiters.removeValue(forKey: id) }
            return due.values.map(\.continuation)
        }
        for continuation in ready { continuation.resume() }
    }
}

/// Waits for a condition over state that lives behind an actor and so cannot
/// signal a `ConditionWaiters`. It polls, and ends early only on cancellation.
func pollUntil(_ condition: () async -> Bool) async {
    while !Task.isCancelled, !(await condition()) {
        try? await Task.sleep(for: .milliseconds(1))
    }
}

/// For negative checks only: yields up to `yields` times so that work a test
/// forbids has a chance to show up, stopping early once `unwanted` holds. It
/// proceeds silently either way, so it is never a readiness wait: under load
/// it can only miss a regression, never fail or stall a correct run.
func settle(watchingFor unwanted: () -> Bool, yields: Int = 100) async {
    for _ in 0 ..< yields where !unwanted() {
        await Task.yield()
    }
}

extension Task where Failure == Never {
    /// The task's value, or `nil` when the awaiting task is cancelled first
    /// (for example by a test time limit). Awaiting `value` directly ignores
    /// that cancellation, so a result that never arrives would stall the run.
    var valueUnlessCancelled: Success? {
        get async {
            let slot = TaskValueSlot<Success>()
            Task<Void, Never> { slot.fill(await self.value) }
            await slot.waitUntilFilled()
            return slot.value
        }
    }
}

private final class TaskValueSlot<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let changes = ConditionWaiters()
    private var filled = false
    private var stored: Value?

    var value: Value? { lock.withLock { stored } }

    func fill(_ value: Value) {
        lock.withLock {
            stored = value
            filled = true
        }
        changes.signal()
    }

    func waitUntilFilled() async {
        await changes.wait { self.lock.withLock { self.filled } }
    }
}
