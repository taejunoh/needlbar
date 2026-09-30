import Combine
import Darwin
import Foundation
import NeedlbarCore

enum SettingsNetworkInformationStatus: Equatable {
    case fresh(capturedAt: Date)
    case stale(lastSuccessfulAt: Date)
    case unavailable
}

struct SettingsNetworkInformationValue: Equatable {
    let downloadBytesPerSecond: UInt64?
    let uploadBytesPerSecond: UInt64?
    let successfulAt: Date?
    let status: SettingsNetworkInformationStatus
    let interfaceNames: [String]?
    let interfaceNamesOmitted: Bool
    let metadataIsStale: Bool
    let localIPAddresses: [String]
    let publicIPAddress: String?
}

@MainActor
public final class SettingsNetworkInformationPresentation: ObservableObject {
    @Published private(set) var value: SettingsNetworkInformationValue

    public init(snapshot: CombinedUsageSnapshot? = nil) {
        value = Self.presentation(for: snapshot)
    }

    public func update(snapshot: CombinedUsageSnapshot) {
        value = Self.presentation(for: snapshot)
    }

    private static func presentation(for snapshot: CombinedUsageSnapshot?) -> SettingsNetworkInformationValue {
        guard let snapshot, let system = snapshot.system else {
            return SettingsNetworkInformationValue(
                downloadBytesPerSecond: nil, uploadBytesPerSecond: nil, successfulAt: nil,
                status: .unavailable, interfaceNames: nil, interfaceNamesOmitted: false,
                metadataIsStale: false, localIPAddresses: [], publicIPAddress: nil
            )
        }

        let availability = snapshot.systemAvailability[.network]
        let ratesAvailable = system.network.downloadBytesPerSecond != nil || system.network.uploadBytesPerSecond != nil
        let trafficStatus: SettingsNetworkInformationStatus
        let successfulAt: Date?
        if ratesAvailable {
            switch availability {
            case let .fresh(capturedAt):
                trafficStatus = .fresh(capturedAt: capturedAt)
                successfulAt = capturedAt
            case let .stale(lastSuccessfulAt):
                trafficStatus = .stale(lastSuccessfulAt: lastSuccessfulAt)
                successfulAt = lastSuccessfulAt
            case .unavailable, nil:
                trafficStatus = .unavailable
                successfulAt = nil
            }
        } else {
            trafficStatus = .unavailable
            successfulAt = nil
        }

        let normalizedNames = normalizeNames(system.network.interfaceNames)
        let staleMetadata: Bool
        if case .stale? = availability { staleMetadata = true } else { staleMetadata = false }

        return SettingsNetworkInformationValue(
            downloadBytesPerSecond: trafficStatus == .unavailable ? nil : system.network.downloadBytesPerSecond,
            uploadBytesPerSecond: trafficStatus == .unavailable ? nil : system.network.uploadBytesPerSecond,
            successfulAt: successfulAt,
            status: trafficStatus,
            interfaceNames: normalizedNames.names,
            interfaceNamesOmitted: normalizedNames.omitted,
            metadataIsStale: staleMetadata,
            localIPAddresses: validateLocalAddresses(system.network.localIPAddresses),
            publicIPAddress: validateAddress(system.network.publicIPAddress)
        )
    }

    private static func normalizeNames(_ names: [String]?) -> (names: [String]?, omitted: Bool) {
        guard let names else { return (nil, false) }
        guard !names.isEmpty else { return ([], false) }
        var accepted = Set<String>()
        var omitted = false
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.utf8.count <= 64,
                  !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else {
                omitted = true
                continue
            }
            accepted.insert(trimmed)
        }
        guard !accepted.isEmpty else { return (nil, true) }
        let sorted = accepted.sorted()
        if sorted.count > 16 { omitted = true }
        return (Array(sorted.prefix(16)), omitted)
    }

    private static func validateLocalAddresses(_ addresses: [String]) -> [String] {
        var seen = Set<String>()
        return addresses.compactMap { candidate in
            guard let valid = validateAddress(candidate), seen.insert(valid).inserted else { return nil }
            return valid
        }
    }

    private static func validateAddress(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let address = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty,
              address.utf8.count <= 45,
              !address.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        var ipv4 = in_addr()
        if address.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 { return address }
        var ipv6 = in6_addr()
        if address.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 { return address }
        return nil
    }
}
