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

public enum WidgetRingColorRole: String, CaseIterable, Sendable {
  case high
  case medium
  case low
  case unlimited

  public var displayName: String {
    switch self {
    case .high:
      return "High (>=70%)"
    case .medium:
      return "Medium (40-69%)"
    case .low:
      return "Low (<40%)"
    case .unlimited:
      return "Unlimited"
    }
  }
}

public enum WidgetRingLayer: String, CaseIterable, Sendable {
  case outer
  case inner

  public var displayName: String {
    switch self {
    case .outer:
      return "Outer circle"
    case .inner:
      return "Inner circle"
    }
  }
}

public struct WidgetRingColors: Codable, Hashable, Sendable {
  public var outerHighHexColor: String
  public var outerMediumHexColor: String
  public var outerLowHexColor: String
  public var outerUnlimitedHexColor: String
  public var innerHighHexColor: String
  public var innerMediumHexColor: String
  public var innerLowHexColor: String
  public var innerUnlimitedHexColor: String

  public init(
    outerHighHexColor: String = "#34C759",
    outerMediumHexColor: String = "#FFCC00",
    outerLowHexColor: String = "#FF3B30",
    outerUnlimitedHexColor: String = "#0A84FF",
    innerHighHexColor: String = "#34C759",
    innerMediumHexColor: String = "#FFCC00",
    innerLowHexColor: String = "#FF3B30",
    innerUnlimitedHexColor: String = "#0A84FF"
  ) {
    self.outerHighHexColor = normalizeHexColor(outerHighHexColor) ?? "#34C759"
    self.outerMediumHexColor = normalizeHexColor(outerMediumHexColor) ?? "#FFCC00"
    self.outerLowHexColor = normalizeHexColor(outerLowHexColor) ?? "#FF3B30"
    self.outerUnlimitedHexColor = normalizeHexColor(outerUnlimitedHexColor) ?? "#0A84FF"
    self.innerHighHexColor = normalizeHexColor(innerHighHexColor) ?? "#34C759"
    self.innerMediumHexColor = normalizeHexColor(innerMediumHexColor) ?? "#FFCC00"
    self.innerLowHexColor = normalizeHexColor(innerLowHexColor) ?? "#FF3B30"
    self.innerUnlimitedHexColor = normalizeHexColor(innerUnlimitedHexColor) ?? "#0A84FF"
  }

  public func hexColor(for role: WidgetRingColorRole, layer: WidgetRingLayer) -> String {
    switch (layer, role) {
    case (.outer, .high):
      return outerHighHexColor
    case (.outer, .medium):
      return outerMediumHexColor
    case (.outer, .low):
      return outerLowHexColor
    case (.outer, .unlimited):
      return outerUnlimitedHexColor
    case (.inner, .high):
      return innerHighHexColor
    case (.inner, .medium):
      return innerMediumHexColor
    case (.inner, .low):
      return innerLowHexColor
    case (.inner, .unlimited):
      return innerUnlimitedHexColor
    }
  }

  public mutating func setHexColor(_ value: String, for role: WidgetRingColorRole, layer: WidgetRingLayer) {
    guard let normalized = normalizeHexColor(value) else {
      return
    }

    switch (layer, role) {
    case (.outer, .high):
      outerHighHexColor = normalized
    case (.outer, .medium):
      outerMediumHexColor = normalized
    case (.outer, .low):
      outerLowHexColor = normalized
    case (.outer, .unlimited):
      outerUnlimitedHexColor = normalized
    case (.inner, .high):
      innerHighHexColor = normalized
    case (.inner, .medium):
      innerMediumHexColor = normalized
    case (.inner, .low):
      innerLowHexColor = normalized
    case (.inner, .unlimited):
      innerUnlimitedHexColor = normalized
    }
  }

  public static func defaults(for palette: WidgetRingPalette) -> WidgetRingColors {
    switch palette {
    case .traffic:
      return WidgetRingColors(
        outerHighHexColor: "#34C759",
        outerMediumHexColor: "#FFCC00",
        outerLowHexColor: "#FF3B30",
        outerUnlimitedHexColor: "#0A84FF",
        innerHighHexColor: "#34C759",
        innerMediumHexColor: "#FFCC00",
        innerLowHexColor: "#FF3B30",
        innerUnlimitedHexColor: "#0A84FF"
      )
    case .cool:
      return WidgetRingColors(
        outerHighHexColor: "#29D6F2",
        outerMediumHexColor: "#3394FA",
        outerLowHexColor: "#4D6BF9",
        outerUnlimitedHexColor: "#78CCFC",
        innerHighHexColor: "#29D6F2",
        innerMediumHexColor: "#3394FA",
        innerLowHexColor: "#4D6BF9",
        innerUnlimitedHexColor: "#78CCFC"
      )
    case .warm:
      return WidgetRingColors(
        outerHighHexColor: "#F5A847",
        outerMediumHexColor: "#F57D36",
        outerLowHexColor: "#F24F3D",
        outerUnlimitedHexColor: "#FAC45C",
        innerHighHexColor: "#F5A847",
        innerMediumHexColor: "#F57D36",
        innerLowHexColor: "#F24F3D",
        innerUnlimitedHexColor: "#FAC45C"
      )
    case .monochrome:
      return WidgetRingColors(
        outerHighHexColor: "#FFFFFFF2",
        outerMediumHexColor: "#FFFFFFBF",
        outerLowHexColor: "#FFFFFF8C",
        outerUnlimitedHexColor: "#FFFFFFE6",
        innerHighHexColor: "#FFFFFFF2",
        innerMediumHexColor: "#FFFFFFBF",
        innerLowHexColor: "#FFFFFF8C",
        innerUnlimitedHexColor: "#FFFFFFE6"
      )
    }
  }

  public static var `default`: WidgetRingColors {
    defaults(for: .traffic)
  }

  private enum CodingKeys: String, CodingKey {
    case outerHighHexColor
    case outerMediumHexColor
    case outerLowHexColor
    case outerUnlimitedHexColor
    case innerHighHexColor
    case innerMediumHexColor
    case innerLowHexColor
    case innerUnlimitedHexColor

    case highHexColor
    case mediumHexColor
    case lowHexColor
    case unlimitedHexColor
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let defaults = WidgetRingColors.default
    let legacyHigh = (try? container.decodeIfPresent(String.self, forKey: .highHexColor)) ?? nil
    let legacyMedium = (try? container.decodeIfPresent(String.self, forKey: .mediumHexColor)) ?? nil
    let legacyLow = (try? container.decodeIfPresent(String.self, forKey: .lowHexColor)) ?? nil
    let legacyUnlimited = (try? container.decodeIfPresent(String.self, forKey: .unlimitedHexColor)) ?? nil

    let outerHigh = (try? container.decodeIfPresent(String.self, forKey: .outerHighHexColor)) ?? legacyHigh
    let outerMedium = (try? container.decodeIfPresent(String.self, forKey: .outerMediumHexColor)) ?? legacyMedium
    let outerLow = (try? container.decodeIfPresent(String.self, forKey: .outerLowHexColor)) ?? legacyLow
    let outerUnlimited = (try? container.decodeIfPresent(String.self, forKey: .outerUnlimitedHexColor)) ?? legacyUnlimited

    let innerHigh = (try? container.decodeIfPresent(String.self, forKey: .innerHighHexColor)) ?? legacyHigh
    let innerMedium = (try? container.decodeIfPresent(String.self, forKey: .innerMediumHexColor)) ?? legacyMedium
    let innerLow = (try? container.decodeIfPresent(String.self, forKey: .innerLowHexColor)) ?? legacyLow
    let innerUnlimited = (try? container.decodeIfPresent(String.self, forKey: .innerUnlimitedHexColor)) ?? legacyUnlimited

    outerHighHexColor = normalizeHexColor(outerHigh) ?? defaults.outerHighHexColor
    outerMediumHexColor = normalizeHexColor(outerMedium) ?? defaults.outerMediumHexColor
    outerLowHexColor = normalizeHexColor(outerLow) ?? defaults.outerLowHexColor
    outerUnlimitedHexColor = normalizeHexColor(outerUnlimited) ?? defaults.outerUnlimitedHexColor

    innerHighHexColor = normalizeHexColor(innerHigh) ?? defaults.innerHighHexColor
    innerMediumHexColor = normalizeHexColor(innerMedium) ?? defaults.innerMediumHexColor
    innerLowHexColor = normalizeHexColor(innerLow) ?? defaults.innerLowHexColor
    innerUnlimitedHexColor = normalizeHexColor(innerUnlimited) ?? defaults.innerUnlimitedHexColor
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(outerHighHexColor, forKey: .outerHighHexColor)
    try container.encode(outerMediumHexColor, forKey: .outerMediumHexColor)
    try container.encode(outerLowHexColor, forKey: .outerLowHexColor)
    try container.encode(outerUnlimitedHexColor, forKey: .outerUnlimitedHexColor)

    try container.encode(innerHighHexColor, forKey: .innerHighHexColor)
    try container.encode(innerMediumHexColor, forKey: .innerMediumHexColor)
    try container.encode(innerLowHexColor, forKey: .innerLowHexColor)
    try container.encode(innerUnlimitedHexColor, forKey: .innerUnlimitedHexColor)

    try container.encode(outerHighHexColor, forKey: .highHexColor)
    try container.encode(outerMediumHexColor, forKey: .mediumHexColor)
    try container.encode(outerLowHexColor, forKey: .lowHexColor)
    try container.encode(outerUnlimitedHexColor, forKey: .unlimitedHexColor)
  }

  var legacyPalette: WidgetRingPalette {
    if self == WidgetRingColors.defaults(for: .traffic) {
      return .traffic
    }
    if self == WidgetRingColors.defaults(for: .cool) {
      return .cool
    }
    if self == WidgetRingColors.defaults(for: .warm) {
      return .warm
    }
    if self == WidgetRingColors.defaults(for: .monochrome) {
      return .monochrome
    }
    return .traffic
  }
}

public struct WidgetStyleSettings: Codable, Hashable, Sendable {
  public var backgroundHexColor: String?
  public var ringColors: WidgetRingColors

  public init(
    backgroundHexColor: String? = nil,
    ringColors: WidgetRingColors = .default
  ) {
    self.backgroundHexColor = normalizeHexColor(backgroundHexColor)
    self.ringColors = ringColors
  }

  private enum CodingKeys: String, CodingKey {
    case backgroundHexColor
    case ringColors
    case showBackground
    case backgroundStyle
    case ringPalette
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    let decodedBackground = (try? container.decodeIfPresent(String.self, forKey: .backgroundHexColor)) ?? nil
    let decodedBackgroundHex = normalizeHexColor(decodedBackground)
    if let decodedBackgroundHex {
      backgroundHexColor = decodedBackgroundHex
    } else {
      let decodedStyle = (try? container.decodeIfPresent(WidgetBackgroundStyle.self, forKey: .backgroundStyle)) ?? .system
      let legacyShowBackground = try? container.decodeIfPresent(Bool.self, forKey: .showBackground)
      let resolvedStyle = (legacyShowBackground == false) ? WidgetBackgroundStyle.system : decodedStyle
      backgroundHexColor = resolvedStyle.defaultBackgroundHexColor
    }

    if let decodedRingColors = (try? container.decodeIfPresent(WidgetRingColors.self, forKey: .ringColors)) ?? nil {
      ringColors = decodedRingColors
    } else {
      let legacyPalette = (try? container.decodeIfPresent(WidgetRingPalette.self, forKey: .ringPalette)) ?? .traffic
      ringColors = WidgetRingColors.defaults(for: legacyPalette)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encodeIfPresent(backgroundHexColor, forKey: .backgroundHexColor)
    try container.encode(ringColors, forKey: .ringColors)

    try container.encode(backgroundHexColor != nil, forKey: .showBackground)
    try container.encode(WidgetBackgroundStyle.legacyStyle(for: backgroundHexColor), forKey: .backgroundStyle)
    try container.encode(ringColors.legacyPalette, forKey: .ringPalette)
  }

  public static var `default`: WidgetStyleSettings {
    WidgetStyleSettings()
  }
}

private extension WidgetBackgroundStyle {
  var defaultBackgroundHexColor: String? {
    switch self {
    case .system:
      return nil
    case .graphite:
      return "#475270"
    case .ocean:
      return "#1F9EFA"
    case .forest:
      return "#1FBD61"
    case .sunset:
      return "#FA7833"
    }
  }

  static func legacyStyle(for backgroundHexColor: String?) -> WidgetBackgroundStyle {
    guard let normalized = normalizeHexColor(backgroundHexColor) else {
      return .system
    }

    if normalized == WidgetBackgroundStyle.graphite.defaultBackgroundHexColor {
      return .graphite
    }
    if normalized == WidgetBackgroundStyle.ocean.defaultBackgroundHexColor {
      return .ocean
    }
    if normalized == WidgetBackgroundStyle.forest.defaultBackgroundHexColor {
      return .forest
    }
    if normalized == WidgetBackgroundStyle.sunset.defaultBackgroundHexColor {
      return .sunset
    }

    return .graphite
  }
}

private func normalizeHexColor(_ value: String?) -> String? {
  guard var raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
    return nil
  }

  if raw.hasPrefix("#") {
    raw.removeFirst()
  }

  if raw.count == 3 || raw.count == 4 {
    raw = raw.map { "\($0)\($0)" }.joined()
  }

  guard raw.count == 6 || raw.count == 8 else {
    return nil
  }

  guard raw.allSatisfy({ $0.isHexDigit }) else {
    return nil
  }

  return "#\(raw.uppercased())"
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

public struct WidgetVisibilitySettings: Codable, Hashable, Sendable {
  public var showTimestamp: Bool
  public var showFailureCount: Bool
  public var showResetInfo: Bool
  public var showOverviewMetricSummary: Bool

  public init(
    showTimestamp: Bool = true,
    showFailureCount: Bool = true,
    showResetInfo: Bool = true,
    showOverviewMetricSummary: Bool = true
  ) {
    self.showTimestamp = showTimestamp
    self.showFailureCount = showFailureCount
    self.showResetInfo = showResetInfo
    self.showOverviewMetricSummary = showOverviewMetricSummary
  }

  public static var `default`: WidgetVisibilitySettings {
    WidgetVisibilitySettings()
  }
}

public struct AppSettings: Codable, Hashable, Sendable {
  public var refreshIntervalMinutes: Int
  public var providers: [ProviderSettings]
  public var widgetStyle: WidgetStyleSettings
  public var providerStyleSettings: [ProviderStyleSettings]
  public var widgetVisibility: WidgetVisibilitySettings

  public init(
    refreshIntervalMinutes: Int = 30,
    providers: [ProviderSettings],
    widgetStyle: WidgetStyleSettings = .default,
    providerStyleSettings: [ProviderStyleSettings] = [],
    widgetVisibility: WidgetVisibilitySettings = .default
  ) {
    self.refreshIntervalMinutes = refreshIntervalMinutes
    self.providers = AppSettings.normalizedProviderSettings(providers)
    self.widgetStyle = widgetStyle
    self.providerStyleSettings = AppSettings.normalizedProviderStyleSettings(
      providerStyleSettings.isEmpty ? AppSettings.defaultProviderStyleSettings() : providerStyleSettings,
      fallbackStyle: widgetStyle
    )
    self.widgetVisibility = widgetVisibility
  }

  public static var `default`: AppSettings {
    AppSettings(
      refreshIntervalMinutes: 30,
      providers: QuotaProvider.allCases.map { ProviderSettings(provider: $0, isEnabled: true) },
      widgetStyle: .default,
      providerStyleSettings: defaultProviderStyleSettings(),
      widgetVisibility: .default
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
    case widgetVisibility
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

    widgetVisibility = (try? container.decodeIfPresent(WidgetVisibilitySettings.self, forKey: .widgetVisibility)) ?? .default
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(refreshIntervalMinutes, forKey: .refreshIntervalMinutes)
    try container.encode(providers, forKey: .providers)
    try container.encode(widgetStyle, forKey: .widgetStyle)
    try container.encode(providerStyleSettings, forKey: .providerStyleSettings)
    try container.encode(widgetVisibility, forKey: .widgetVisibility)
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
