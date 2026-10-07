import Foundation
import NeedlbarCore

@MainActor enum QuotaPresentationTicker {
    static func run(
        clock: any ClockLike = SystemClock(),
        update: @MainActor (Date) -> Void
    ) async {
        while !Task.isCancelled {
            update(clock.now)
            do { try await clock.sleep(for: .seconds(1)) }
            catch { return }
        }
    }
}
