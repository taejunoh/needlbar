import Darwin
import Foundation
import IOKit
import IOKit.ps

public actor MacSystemMetricsCollector: SystemMetricsCollecting {
  private struct NetworkCounters {
    let incoming: UInt64
    let outgoing: UInt64
    let capturedAt: Date
  }

  private var previousCPUTicks: CPUTicks?
  private var previousNetworkCounters: NetworkCounters?

  public init() {}

  public func collect(at date: Date) async throws -> SystemMetricsSnapshot {
    let cpu = collectCPU()
    let memory = collectMemory()
    let disks = collectDisks()
    let network = collectNetwork(at: date)
    let battery = collectBattery()
    let availability: [MonitorModuleID: MetricAvailability] = [
      .cpu: cpu.totalUsage == nil ? .unavailable(code: "cpuUnavailable") : .fresh(capturedAt: date),
      .memory: memory.usedBytes == nil
        ? .unavailable(code: "memoryUnavailable") : .fresh(capturedAt: date),
      .disk: disks.isEmpty ? .unavailable(code: "diskUnavailable") : .fresh(capturedAt: date),
      .network: network.uploadBytesPerSecond == nil && network.downloadBytesPerSecond == nil
        ? .unavailable(code: "networkUnavailable") : .fresh(capturedAt: date),
      .battery: battery.level == nil
        ? .unavailable(code: "batteryUnavailable") : .fresh(capturedAt: date),
      .ai: .unavailable(code: "providerSnapshotUnavailable"),
    ]
    return SystemMetricsSnapshot(
      capturedAt: date,
      cpu: cpu,
      memory: memory,
      disks: disks,
      network: network,
      battery: battery,
      availability: availability
    )
  }

  private func collectCPU() -> SystemMetricsSnapshot.CPU {
    var numberOfCPUs: natural_t = 0
    var cpuInfo: processor_info_array_t?
    var numberOfCPUInfo: mach_msg_type_number_t = 0
    let result = host_processor_info(
      mach_host_self(),
      PROCESSOR_CPU_LOAD_INFO,
      &numberOfCPUs,
      &cpuInfo,
      &numberOfCPUInfo
    )
    guard result == KERN_SUCCESS, let cpuInfo else {
      return .init(totalUsage: nil, perCoreUsage: [])
    }
    defer {
      let address = vm_address_t(bitPattern: cpuInfo)
      let size = vm_size_t(numberOfCPUInfo) * vm_size_t(MemoryLayout<integer_t>.stride)
      _ = vm_deallocate(mach_task_self_, address, size)
    }

    let stride = Int(CPU_STATE_MAX)
    var totalActive: UInt64 = 0
    var totalTicks: UInt64 = 0
    var currentPerCore: [(active: UInt64, total: UInt64)] = []
    for cpu in 0..<Int(numberOfCPUs) {
      let offset = cpu * stride
      let user = UInt64(max(0, cpuInfo[offset + Int(CPU_STATE_USER)]))
      let system = UInt64(max(0, cpuInfo[offset + Int(CPU_STATE_SYSTEM)]))
      let nice = UInt64(max(0, cpuInfo[offset + Int(CPU_STATE_NICE)]))
      let idle = UInt64(max(0, cpuInfo[offset + Int(CPU_STATE_IDLE)]))
      let active = user + system + nice
      let total = active + idle
      currentPerCore.append((active, total))
      totalActive += active
      totalTicks += total
    }

    let perCore = currentPerCore.enumerated().compactMap { index, value -> MetricPercentage? in
      guard let previous = previousCPUTicks else { return nil }
      let previousPerCore = previous.perCore[index]
      let activeDelta =
        value.active >= previousPerCore.active ? value.active - previousPerCore.active : 0
      let totalDelta =
        value.total >= previousPerCore.total ? value.total - previousPerCore.total : 0
      guard totalDelta > 0 else { return nil }
      return MetricPercentage(Double(activeDelta) / Double(totalDelta) * 100)
    }
    let totalUsage: MetricPercentage?
    if let previous = previousCPUTicks {
      let activeDelta = totalActive >= previous.active ? totalActive - previous.active : 0
      let totalDelta = totalTicks >= previous.total ? totalTicks - previous.total : 0
      totalUsage =
        totalDelta > 0 ? MetricPercentage(Double(activeDelta) / Double(totalDelta) * 100) : nil
    } else {
      totalUsage = nil
    }
    previousCPUTicks = CPUTicks(active: totalActive, total: totalTicks, perCore: currentPerCore)
    return .init(totalUsage: totalUsage, perCoreUsage: perCore)
  }

  private func collectMemory() -> SystemMetricsSnapshot.Memory {
    var statistics = vm_statistics64()
    var count = mach_msg_type_number_t(
      MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<natural_t>.stride)
    let result = withUnsafeMutablePointer(to: &statistics) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
        host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
      }
    }
    guard result == KERN_SUCCESS else {
      return .init(usedBytes: nil, freeBytes: nil, swapUsedBytes: nil, pressure: nil)
    }
    var pageSizeValue: vm_size_t = 0
    guard host_page_size(mach_host_self(), &pageSizeValue) == KERN_SUCCESS else {
      return .init(usedBytes: nil, freeBytes: nil, swapUsedBytes: nil, pressure: nil)
    }
    let pageSize = UInt64(pageSizeValue)
    let free = UInt64(statistics.free_count) * pageSize
    let usedPages =
      UInt64(statistics.active_count)
      + UInt64(statistics.inactive_count)
      + UInt64(statistics.wire_count)
      + UInt64(statistics.compressor_page_count)
    return .init(
      usedBytes: usedPages * pageSize, freeBytes: free, swapUsedBytes: nil, pressure: "normal")
  }

  private func collectDisks() -> [SystemMetricsSnapshot.DiskVolume] {
    let keys: Set<URLResourceKey> = [
      .volumeNameKey,
      .volumeTotalCapacityKey,
      .volumeAvailableCapacityKey,
    ]
    guard
      let urls = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: Array(keys),
        options: [.skipHiddenVolumes]
      )
    else { return [] }
    return urls.compactMap { url in
      guard let values = try? url.resourceValues(forKeys: keys),
        let total = values.volumeTotalCapacity,
        let available = values.volumeAvailableCapacity
      else { return nil }
      let totalBytes = UInt64(max(total, 0))
      let freeBytes = UInt64(max(available, 0))
      return .init(
        name: values.volumeName ?? url.lastPathComponent,
        usedBytes: totalBytes >= freeBytes ? totalBytes - freeBytes : 0,
        freeBytes: freeBytes,
        readBytesPerSecond: nil,
        writeBytesPerSecond: nil
      )
    }
  }

  private func collectNetwork(at date: Date) -> SystemMetricsSnapshot.Network {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let head else {
      return .init(
        uploadBytesPerSecond: nil, downloadBytesPerSecond: nil, localIPAddresses: [],
        publicIPAddress: nil)
    }
    defer { freeifaddrs(head) }

    var cursor: UnsafeMutablePointer<ifaddrs>? = head
    var incoming: UInt64 = 0
    var outgoing: UInt64 = 0
    var addresses = Set<String>()
    while let interface = cursor {
      let value = interface.pointee
      if let data = value.ifa_data?.assumingMemoryBound(to: if_data.self).pointee,
        value.ifa_addr?.pointee.sa_family == UInt8(AF_LINK)
      {
        incoming &+= UInt64(max(data.ifi_ibytes, 0))
        outgoing &+= UInt64(max(data.ifi_obytes, 0))
      }
      if let address = value.ifa_addr,
        address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6),
        let host = numericAddress(address),
        !isLoopbackOrLinkLocal(host),
        (value.ifa_flags & UInt32(IFF_UP)) != 0
      {
        addresses.insert(host)
      }
      cursor = value.ifa_next
    }

    let rates: (upload: UInt64?, download: UInt64?)
    if let previous = previousNetworkCounters {
      let elapsed = max(date.timeIntervalSince(previous.capturedAt), 0.001)
      let incomingDelta = incoming >= previous.incoming ? incoming - previous.incoming : 0
      let outgoingDelta = outgoing >= previous.outgoing ? outgoing - previous.outgoing : 0
      rates = (
        upload: UInt64(Double(outgoingDelta) / elapsed),
        download: UInt64(Double(incomingDelta) / elapsed)
      )
    } else {
      rates = (nil, nil)
    }
    previousNetworkCounters = NetworkCounters(
      incoming: incoming, outgoing: outgoing, capturedAt: date)
    return .init(
      uploadBytesPerSecond: rates.upload,
      downloadBytesPerSecond: rates.download,
      localIPAddresses: addresses.sorted(),
      publicIPAddress: nil
    )
  }

  private func collectBattery() -> SystemMetricsSnapshot.Battery {
    let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
      return .init(level: nil, isCharging: nil, health: nil)
    }
    for source in sources {
      guard
        let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
          as? [String: Any],
        let current = (description[kIOPSCurrentCapacityKey as String] as? NSNumber)?.doubleValue,
        let maximum = (description[kIOPSMaxCapacityKey as String] as? NSNumber)?.doubleValue,
        maximum > 0
      else { continue }
      let charging = (description[kIOPSIsChargingKey as String] as? NSNumber)?.boolValue
      let health = (description[kIOPSBatteryHealthKey as String] as? String).flatMap { value in
        switch value.lowercased() {
        case "good": return MetricPercentage(100)
        case "fair": return MetricPercentage(75)
        case "poor": return MetricPercentage(25)
        default: return nil
        }
      }
      return .init(
        level: MetricPercentage(current / maximum * 100), isCharging: charging, health: health)
    }
    return .init(level: nil, isCharging: nil, health: nil)
  }

  private func numericAddress(_ pointer: UnsafeMutablePointer<sockaddr>) -> String? {
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let length = socklen_t(pointer.pointee.sa_len)
    let result = host.withUnsafeMutableBufferPointer { buffer in
      getnameinfo(
        pointer, length, buffer.baseAddress, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
    }
    guard result == 0 else { return nil }
    return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
      .split(separator: "%", maxSplits: 1, omittingEmptySubsequences: true)
      .first
      .map(String.init)
  }

  private func isLoopbackOrLinkLocal(_ value: String) -> Bool {
    value == "127.0.0.1" || value == "::1" || value.hasPrefix("169.254.")
      || value.lowercased().hasPrefix("fe80:")
  }
}

extension MacSystemMetricsCollector {
  fileprivate struct CPUTicks {
    let active: UInt64
    let total: UInt64
    let perCore: [(active: UInt64, total: UInt64)]
  }
}
