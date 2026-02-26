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

public enum WidgetBackgroundStyle: String, CaseIterable, Codable, Sendable {
  case system
  case graphite
  case ocean
  case forest
  case sunset

  public var displayName: String {
    switch self {
    case .system:
      return "Default"
    case .graphite:
      return "Graphite"
    case .ocean:
      return "Ocean"
    case .forest:
      return "Forest"
    case .sunset:
      return "Sunset"
    }
  }
}

public enum WidgetRingPalette: String, CaseIterable, Codable, Sendable {
  case traffic
  case cool
  case warm
  case monochrome

  public var displayName: String {
    switch self {
    case .traffic:
      return "Traffic Light"
    case .cool:
      return "Cool"
    case .warm:
      return "Warm"
    case .monochrome:
      return "Monochrome"
    }
  }
}

public struct WidgetStyleSettings: Codable, Hashable, Sendable {
  public var backgroundStyle: WidgetBackgroundStyle
  public var ringPalette: WidgetRingPalette

  public init(
    backgroundStyle: WidgetBackgroundStyle = .system,
    ringPalette: WidgetRingPalette = .traffic
  ) {
    self.backgroundStyle = backgroundStyle
    self.ringPalette = ringPalette
  }

  private enum CodingKeys: String, CodingKey {
    case showBackground
    case backgroundStyle
    case ringPalette
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let decodedStyle = try container.decodeIfPresent(WidgetBackgroundStyle.self, forKey: .backgroundStyle) ?? .system
    let legacyShowBackground = try container.decodeIfPresent(Bool.self, forKey: .showBackground)

    backgroundStyle = (legacyShowBackground == false) ? .system : decodedStyle
    ringPalette = try container.decodeIfPresent(WidgetRingPalette.self, forKey: .ringPalette) ?? .traffic
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(backgroundStyle != .system, forKey: .showBackground)
    try container.encode(backgroundStyle, forKey: .backgroundStyle)
    try container.encode(ringPalette, forKey: .ringPalette)
  }

  public static var `default`: WidgetStyleSettings {
    WidgetStyleSettings()
  }
}

public struct ProviderStyleSettings: Codable, Hashable, Sendable {
  public var provider: QuotaProvider
  public var useCustomStyle: Bool
  public var style: WidgetStyleSettings

  public init(
    provider: QuotaProvider,
    useCustomStyle: Bool = false,
    style: WidgetStyleSettings = .default
  ) {
    self.provider = provider
    self.useCustomStyle = useCustomStyle
    self.style = style
  }

  public static func defaultValue(
    for provider: QuotaProvider,
    fallbackStyle: WidgetStyleSettings = .default
  ) -> ProviderStyleSettings {
    ProviderStyleSettings(provider: provider, useCustomStyle: false, style: fallbackStyle)
  }
}

public struct AppSettings: Codable, Hashable, Sendable {
  public var refreshIntervalMinutes: Int
  public var providers: [ProviderSettings]
  public var widgetStyle: WidgetStyleSettings
  public var providerStyleSettings: [ProviderStyleSettings]

  public init(
    refreshIntervalMinutes: Int = 30,
    providers: [ProviderSettings],
    widgetStyle: WidgetStyleSettings = .default,
    providerStyleSettings: [ProviderStyleSettings] = []
  ) {
    self.refreshIntervalMinutes = refreshIntervalMinutes
    self.providers = AppSettings.normalizedProviderSettings(providers)
    self.widgetStyle = widgetStyle
    self.providerStyleSettings = AppSettings.normalizedProviderStyleSettings(
      providerStyleSettings.isEmpty ? AppSettings.defaultProviderStyleSettings() : providerStyleSettings,
      fallbackStyle: widgetStyle
    )
  }

  public static var `default`: AppSettings {
    AppSettings(
      refreshIntervalMinutes: 30,
      providers: QuotaProvider.allCases.map { ProviderSettings(provider: $0, isEnabled: true) },
      widgetStyle: .default,
      providerStyleSettings: defaultProviderStyleSettings()
    )
  }

  public func isEnabled(_ provider: QuotaProvider) -> Bool {
    providers.first(where: { $0.provider == provider })?.isEnabled ?? false
  }

  public func styleOverride(for provider: QuotaProvider) -> ProviderStyleSettings {
    providerStyleSettings.first(where: { $0.provider == provider })
      ?? ProviderStyleSettings.defaultValue(for: provider, fallbackStyle: widgetStyle)
  }

  private enum CodingKeys: String, CodingKey {
    case refreshIntervalMinutes
    case providers
    case widgetStyle
    case providerStyleSettings
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    refreshIntervalMinutes = (try? container.decodeIfPresent(Int.self, forKey: .refreshIntervalMinutes)) ?? 30

    let decodedProviders = (try? container.decodeIfPresent([ProviderSettings].self, forKey: .providers))
      ?? QuotaProvider.allCases.map { ProviderSettings(provider: $0, isEnabled: true) }
    providers = AppSettings.normalizedProviderSettings(decodedProviders)

    widgetStyle = (try? container.decodeIfPresent(WidgetStyleSettings.self, forKey: .widgetStyle)) ?? .default

    let decodedStyleSettings = (try? container.decodeIfPresent(
      [ProviderStyleSettings].self,
      forKey: .providerStyleSettings
    )) ?? AppSettings.defaultProviderStyleSettings()
    providerStyleSettings = AppSettings.normalizedProviderStyleSettings(
      decodedStyleSettings,
      fallbackStyle: widgetStyle
    )
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(refreshIntervalMinutes, forKey: .refreshIntervalMinutes)
    try container.encode(providers, forKey: .providers)
    try container.encode(widgetStyle, forKey: .widgetStyle)
    try container.encode(providerStyleSettings, forKey: .providerStyleSettings)
  }

  private static func defaultProviderStyleSettings() -> [ProviderStyleSettings] {
    QuotaProvider.allCases.map { ProviderStyleSettings.defaultValue(for: $0) }
  }

  private static func normalizedProviderSettings(_ values: [ProviderSettings]) -> [ProviderSettings] {
    QuotaProvider.allCases.map { provider in
      values.first(where: { $0.provider == provider }) ?? ProviderSettings(provider: provider, isEnabled: true)
    }
  }

  private static func normalizedProviderStyleSettings(
    _ values: [ProviderStyleSettings],
    fallbackStyle: WidgetStyleSettings
  ) -> [ProviderStyleSettings] {
    QuotaProvider.allCases.map { provider in
      values.first(where: { $0.provider == provider })
        ?? ProviderStyleSettings.defaultValue(for: provider, fallbackStyle: fallbackStyle)
    }
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
