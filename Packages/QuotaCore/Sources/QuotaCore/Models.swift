import Foundation

public enum QuotaProvider: String, CaseIterable, Codable, Sendable {
  case openAI = "openai"
  case zhipu = "zhipu"
  case zai = "zai"
  case googleAntigravity = "google-antigravity"
  case gitHubCopilot = "github-copilot"

  public var displayName: String {
    switch self {
    case .openAI:
      return "OpenAI"
    case .zhipu:
      return "Zhipu AI"
    case .zai:
      return "Z.ai"
    case .googleAntigravity:
      return "Google Cloud"
    case .gitHubCopilot:
      return "GitHub Copilot"
    }
  }
}

public enum QuotaErrorKind: String, Codable, Sendable {
  case notConfigured
  case auth
  case network
  case rateLimit
  case decoding
  case api
  case unknown
}

public struct UsageMetric: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public var label: String
  public var remainingPercent: Int?
  public var usedDisplay: String?
  public var totalDisplay: String?
  public var resetAt: Date?
  public var resetIn: String?
  public var isUnlimited: Bool
  public var detail: String?

  public init(
    id: String,
    label: String,
    remainingPercent: Int? = nil,
    usedDisplay: String? = nil,
    totalDisplay: String? = nil,
    resetAt: Date? = nil,
    resetIn: String? = nil,
    isUnlimited: Bool = false,
    detail: String? = nil
  ) {
    self.id = id
    self.label = label
    self.remainingPercent = remainingPercent
    self.usedDisplay = usedDisplay
    self.totalDisplay = totalDisplay
    self.resetAt = resetAt
    self.resetIn = resetIn
    self.isUnlimited = isUnlimited
    self.detail = detail
  }

  public var usageLine: String? {
    if isUnlimited {
      return "Unlimited"
    }

    guard let usedDisplay else {
      return nil
    }

    if let totalDisplay {
      return "\(usedDisplay) / \(totalDisplay)"
    }
    return usedDisplay
  }
}

public struct ProviderUsage: Codable, Hashable, Identifiable, Sendable {
  public var id: String { provider.rawValue }
  public var provider: QuotaProvider
  public var title: String
  public var subtitle: String?
  public var metrics: [UsageMetric]
  public var maxUsagePercent: Int?
  public var warning: String?
  public var fetchedAt: Date

  public init(
    provider: QuotaProvider,
    title: String,
    subtitle: String? = nil,
    metrics: [UsageMetric],
    maxUsagePercent: Int? = nil,
    warning: String? = nil,
    fetchedAt: Date
  ) {
    self.provider = provider
    self.title = title
    self.subtitle = subtitle
    self.metrics = metrics
    self.maxUsagePercent = maxUsagePercent
    self.warning = warning
    self.fetchedAt = fetchedAt
  }
}

public struct ProviderFailure: Codable, Hashable, Identifiable, Sendable {
  public var id: String { provider.rawValue }
  public var provider: QuotaProvider
  public var kind: QuotaErrorKind
  public var message: String

  public init(provider: QuotaProvider, kind: QuotaErrorKind, message: String) {
    self.provider = provider
    self.kind = kind
    self.message = message
  }
}

public struct QuotaSnapshot: Codable, Hashable, Sendable {
  public var version: Int
  public var generatedAt: Date
  public var providers: [ProviderUsage]
  public var failures: [ProviderFailure]

  public init(
    version: Int = 1,
    generatedAt: Date,
    providers: [ProviderUsage],
    failures: [ProviderFailure]
  ) {
    self.version = version
    self.generatedAt = generatedAt
    self.providers = providers
    self.failures = failures
  }

  public var isPartial: Bool { !failures.isEmpty }
}

public struct ProviderSettings: Codable, Hashable, Sendable {
  public var provider: QuotaProvider
  public var isEnabled: Bool

  public init(provider: QuotaProvider, isEnabled: Bool) {
    self.provider = provider
    self.isEnabled = isEnabled
  }
}

public struct AppSettings: Codable, Hashable, Sendable {
  public var refreshIntervalMinutes: Int
  public var providers: [ProviderSettings]

  public init(refreshIntervalMinutes: Int = 30, providers: [ProviderSettings]) {
    self.refreshIntervalMinutes = refreshIntervalMinutes
    self.providers = providers
  }

  public static var `default`: AppSettings {
    AppSettings(
      refreshIntervalMinutes: 30,
      providers: QuotaProvider.allCases.map { ProviderSettings(provider: $0, isEnabled: true) }
    )
  }

  public func isEnabled(_ provider: QuotaProvider) -> Bool {
    providers.first(where: { $0.provider == provider })?.isEnabled ?? false
  }
}

public struct ProviderRuntimeConfiguration: Hashable, Sendable {
  public var provider: QuotaProvider
  public var isEnabled: Bool
  public var credentials: [String: String]

  public init(
    provider: QuotaProvider,
    isEnabled: Bool,
    credentials: [String: String]
  ) {
    self.provider = provider
    self.isEnabled = isEnabled
    self.credentials = credentials
  }
}
