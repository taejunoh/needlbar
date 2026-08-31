import Foundation

public enum QuotaAlertLedgerStoreError: Error, Sendable, Equatable {
    case corrupt
    case writeFailed
}

public protocol QuotaAlertLedgerStoring: Sendable {
    func load() async throws -> QuotaAlertLedger
    func save(_ ledger: QuotaAlertLedger) async throws
}

public struct QuotaAlertLedgerStore: QuotaAlertLedgerStoring {
    private static let maximumBytes = 16 * 1024

    private let url: URL
    private let writer: any SnapshotFileWriter

    public init(
        fileManager: FileManager = .default,
        writer: any SnapshotFileWriter = POSIXSnapshotFileWriter()
    ) {
        let directory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Needlbar", isDirectory: true)
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        url = directory.appendingPathComponent("quota-alert-ledger-v1.json")
        self.writer = writer
    }

    init(url: URL, writer: any SnapshotFileWriter) {
        self.url = url
        self.writer = writer
    }

    public func load() async throws -> QuotaAlertLedger {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .empty
        }
        defer { try? handle.close() }

        guard let bytes = try? handle.read(upToCount: Self.maximumBytes + 1), bytes.count <= Self.maximumBytes,
              let ledger = try? JSONDecoder().decode(QuotaAlertLedger.self, from: bytes),
              QuotaAlertLedgerValidation.isValid(ledger, now: Date())
        else {
            return .empty
        }
        return ledger
    }

    public func save(_ ledger: QuotaAlertLedger) async throws {
        guard QuotaAlertLedgerValidation.isValid(ledger, now: Date()) else {
            throw QuotaAlertLedgerStoreError.corrupt
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(ledger),
              (try? writer.writeAtomically(bytes, to: url)) == .committed
        else {
            throw QuotaAlertLedgerStoreError.writeFailed
        }
    }
}

enum QuotaAlertLedgerValidation {
    static func isValid(_ ledger: QuotaAlertLedger, now: Date) -> Bool {
        guard ledger.schemaVersion == QuotaAlertLedger.currentSchemaVersion,
              ledger.records.count <= 4
        else {
            return false
        }

        var keys = Set<QuotaAlertKey>()
        return ledger.records.allSatisfy { record in
            guard keys.insert(record.key).inserted,
                  QuotaAlertKey.isAllowed(provider: record.key.provider, windowID: record.key.windowID),
                  record.lastRemainingPercent.isFinite,
                  (0 ... 100).contains(record.lastRemainingPercent),
                  record.lastSuccessfulAt.timeIntervalSinceReferenceDate.isFinite,
                  record.lastSuccessfulAt <= now,
                  record.pinnedResetAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
                  record.reservedStages.isSubset(of: record.consumedStages)
            else {
                return false
            }
            return true
        }
    }
}
