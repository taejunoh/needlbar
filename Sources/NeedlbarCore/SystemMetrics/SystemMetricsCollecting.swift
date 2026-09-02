import Darwin
import Foundation

public protocol SystemMetricsCollecting: Sendable {
  func collect(at date: Date) async throws -> SystemMetricsSnapshot
}

public protocol PublicIPProviding: Sendable {
  func fetchPublicIP() async throws -> String
}

public protocol NeedlbarClock: Sendable {
  var now: Date { get }
  func sleep(for duration: Duration) async throws
}

public struct SystemMetricsClock: NeedlbarClock, Sendable {
  public init() {}

  public var now: Date { Date() }

  public func sleep(for duration: Duration) async throws {
    try await Task.sleep(for: duration)
  }
}

public struct URLSessionPublicIPProvider: PublicIPProviding, Sendable {
  public static let endpoint = URL(string: "https://api64.ipify.org?format=json")!

  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func fetchPublicIP() async throws -> String {
    var request = URLRequest(url: Self.endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 2
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
      throw PublicIPProviderError.httpFailure
    }
    let payload = try JSONDecoder().decode(PublicIPPayload.self, from: data)
    guard Self.isValidAddress(payload.ip) else {
      throw PublicIPProviderError.invalidAddress
    }
    return payload.ip
  }

  private static func isValidAddress(_ value: String) -> Bool {
    var address = in_addr()
    if value.withCString({ inet_pton(AF_INET, $0, &address) }) == 1 { return true }
    var address6 = in6_addr()
    return value.withCString({ inet_pton(AF_INET6, $0, &address6) }) == 1
  }
}

public enum PublicIPProviderError: Error, Sendable, Equatable {
  case httpFailure
  case invalidAddress
}

private struct PublicIPPayload: Decodable {
  let ip: String
}
