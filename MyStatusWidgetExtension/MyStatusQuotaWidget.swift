import SwiftUI
import WidgetKit
import QuotaCore

struct OpenCodeQuotaWidget: Widget {
  private let kind = SharedConstants.widgetKind

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QuotaTimelineProvider()) { entry in
      DashboardWidgetRootView(entry: entry)
        .containerBackground(for: .widget) {
          widgetBackground(for: entry, provider: nil)
        }
    }
    .configurationDisplayName("OpenCodeQuota Dashboard")
    .description("Compact quota overview across all enabled providers.")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct OpenAIQuotaWidget: Widget {
  var body: some WidgetConfiguration {
    providerWidgetConfiguration(
      kind: SharedConstants.openAIWidgetKind,
      provider: .openAI,
      displayName: "OpenAI Rings",
      widgetDescription: "OpenAI short and long window limits."
    )
  }
}

struct ZhipuQuotaWidget: Widget {
  var body: some WidgetConfiguration {
    providerWidgetConfiguration(
      kind: SharedConstants.zhipuWidgetKind,
      provider: .zhipu,
      displayName: "Zhipu AI Rings",
      widgetDescription: "Zhipu token and quota limits."
    )
  }
}

struct ZAIQuotaWidget: Widget {
  var body: some WidgetConfiguration {
    providerWidgetConfiguration(
      kind: SharedConstants.zaiWidgetKind,
      provider: .zai,
      displayName: "Z.ai Rings",
      widgetDescription: "Z.ai token and quota limits."
    )
  }
}

struct GoogleQuotaWidget: Widget {
  var body: some WidgetConfiguration {
    providerWidgetConfiguration(
      kind: SharedConstants.googleWidgetKind,
      provider: .googleAntigravity,
      displayName: "Google Rings",
      widgetDescription: "Google Antigravity model limits."
    )
  }
}

struct CopilotQuotaWidget: Widget {
  var body: some WidgetConfiguration {
    providerWidgetConfiguration(
      kind: SharedConstants.copilotWidgetKind,
      provider: .gitHubCopilot,
      displayName: "Copilot Rings",
      widgetDescription: "GitHub Copilot quota limits."
    )
  }
}

private func providerWidgetConfiguration(
  kind: String,
  provider: QuotaProvider,
  displayName: String,
  widgetDescription: String
) -> some WidgetConfiguration {
  StaticConfiguration(kind: kind, provider: QuotaTimelineProvider()) { entry in
    ProviderSmallQuotaView(entry: entry, provider: provider)
      .containerBackground(for: .widget) {
        widgetBackground(for: entry, provider: provider)
      }
  }
  .configurationDisplayName(displayName)
  .description(widgetDescription)
  .supportedFamilies([.systemSmall])
}

private struct DashboardWidgetRootView: View {
  @Environment(\.widgetFamily) private var family
  let entry: QuotaEntry

  var body: some View {
    switch family {
    case .systemSmall:
      OverviewSmallQuotaView(entry: entry)
    default:
      MediumCompactQuotaView(entry: entry)
    }
  }
}

private struct OverviewSmallQuotaView: View {
  let entry: QuotaEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("OpenCodeQuota")
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)

      if let usage = featuredProvider {
        let style = entry.style(for: usage.provider)

        Text(usage.title)
          .font(.caption.weight(.semibold))
          .lineLimit(1)

        ConcentricQuotaChart(
          metrics: chartMetrics(for: usage),
          ringColors: style.ringColors,
          centerLabelStyle: entry.settings.widgetVisibility.showPercentageValues ? .metrics : .hidden
        )
          .frame(maxWidth: .infinity, minHeight: 88, maxHeight: .infinity)

        if entry.settings.widgetVisibility.showOverviewMetricSummary {
          Text(
            metricSummary(
              for: usage,
              showPercentages: entry.settings.widgetVisibility.showPercentageValues
            )
          )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      } else {
        Spacer(minLength: 0)
        Text("OpenCodeQuota app")
          .font(.caption.weight(.semibold))
        Text("Enable providers and refresh")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
    }
    .padding(10)
  }

  private var featuredProvider: ProviderUsage? {
    guard let providers = entry.snapshot?.providers, !providers.isEmpty else {
      return nil
    }

    let providersWithDualRings = providers.filter { chartMetrics(for: $0).count >= 2 }
    if let mostLoadedDual = providersWithDualRings.max(by: usageScoreSort) {
      return mostLoadedDual
    }

    return providers.max(by: usageScoreSort)
  }

  private func usageScoreSort(_ lhs: ProviderUsage, _ rhs: ProviderUsage) -> Bool {
    (lhs.maxUsagePercent ?? 0) < (rhs.maxUsagePercent ?? 0)
  }
}

private struct ProviderSmallQuotaView: View {
  let entry: QuotaEntry
  let provider: QuotaProvider

  var body: some View {
    ZStack {
      if let usage = providerUsage {
        let metrics = chartMetrics(for: usage)

        ConcentricQuotaChart(
          metrics: metrics,
          ringColors: entry.style(for: provider).ringColors,
          centerLabelStyle: entry.settings.widgetVisibility.showPercentageValues ? .metrics : .hidden
        )
          .frame(maxWidth: .infinity, maxHeight: .infinity)

        if entry.settings.widgetVisibility.showPercentageValues {
          Text(compactProviderName(for: provider))
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
          Text(compactProviderName(for: provider))
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
        }

        if entry.settings.widgetVisibility.showResetInfo, let resetText = resetSummary(for: metrics) {
          Text(resetDisplayText(for: resetText))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .offset(y: 22)
        }
      } else {
        VStack(spacing: 2) {
          Text(compactProviderName(for: provider))
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
          Text("No data yet")
            .font(.caption2)
            .foregroundStyle(.secondary)
          Text("Refresh in app")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
      }
    }
    .padding(6)
  }

  private var providerUsage: ProviderUsage? {
    entry.snapshot?.providers.first(where: { $0.provider == provider })
  }
}

private struct MediumCompactQuotaView: View {
  let entry: QuotaEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("AI Quota")
          .font(.caption.weight(.semibold))
        Spacer()
        if entry.settings.widgetVisibility.showTimestamp, let snapshot = entry.snapshot {
          Text(snapshot.generatedAt, style: .time)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }

      if let snapshot = entry.snapshot, !snapshot.providers.isEmpty {
        let providerLimit = max(1, min(entry.settings.widgetVisibility.mediumProviderLimit, 12))

        ForEach(sortedProviders(snapshot.providers).prefix(providerLimit)) { usage in
          CompactProviderUsageRow(
            usage: usage,
            ringColors: entry.style(for: usage.provider).ringColors,
            showProgressBar: entry.settings.widgetVisibility.showMediumProgressBars,
            showPercentages: entry.settings.widgetVisibility.showPercentageValues
          )
        }

        if entry.settings.widgetVisibility.showFailureCount, !snapshot.failures.isEmpty {
          Text("\(snapshot.failures.count) unavailable")
            .font(.caption2)
            .foregroundStyle(.orange)
        }
      } else {
        Spacer(minLength: 0)
        Text("No providers configured")
          .font(.caption.weight(.semibold))
        Text("Load credentials from OpenCode config")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
    }
    .padding(10)
  }

  private func sortedProviders(_ providers: [ProviderUsage]) -> [ProviderUsage] {
    providers.sorted { lhs, rhs in
      (lhs.maxUsagePercent ?? 0) > (rhs.maxUsagePercent ?? 0)
    }
  }
}

private struct CompactProviderUsageRow: View {
  let usage: ProviderUsage
  let ringColors: WidgetRingColors
  let showProgressBar: Bool
  let showPercentages: Bool

  var body: some View {
    HStack(spacing: 6) {
      Text(shortName)
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .frame(width: 58, alignment: .leading)

      if showProgressBar {
        MiniProgressBar(
          percent: metric?.remainingPercent,
          unlimited: metric?.isUnlimited ?? false,
          ringColors: ringColors
        )
          .frame(height: 5)
      } else {
        Spacer(minLength: 0)
      }

      if showPercentages {
        Text(percentText(for: metric))
          .font(.caption2.weight(.semibold))
          .monospacedDigit()
          .frame(width: 32, alignment: .trailing)
      }
    }
  }

  private var metric: UsageMetric? {
    usage.metrics.first(where: { $0.remainingPercent != nil || $0.isUnlimited }) ?? usage.metrics.first
  }

  private var shortName: String {
    compactProviderName(for: usage.provider)
  }
}

private struct ConcentricQuotaChart: View {
  enum CenterLabelStyle {
    case metrics
    case hidden
  }

  let metrics: [UsageMetric]
  let ringColors: WidgetRingColors
  var centerLabelStyle: CenterLabelStyle = .metrics

  var body: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      let outerMetric = metrics.first
      let innerMetric = metrics.dropFirst().first

      ZStack {
        if let outerMetric {
          CircularQuotaRing(
            metric: outerMetric,
            lineWidth: max(8, side * 0.12),
            ringColors: ringColors,
            ringLayer: .outer
          )
            .frame(width: side, height: side)
        }

        if let innerMetric {
          CircularQuotaRing(
            metric: innerMetric,
            lineWidth: max(6, side * 0.1),
            ringColors: ringColors,
            ringLayer: .inner
          )
            .frame(width: side * 0.64, height: side * 0.64)
        }

        if centerLabelStyle == .metrics {
          VStack(spacing: 1) {
            if let outerMetric {
              Text(percentText(for: outerMetric))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            } else {
              Text("--")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            if let innerMetric {
              Text(percentText(for: innerMetric))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
          }
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
  }
}

private struct CircularQuotaRing: View {
  let metric: UsageMetric
  let lineWidth: CGFloat
  let ringColors: WidgetRingColors
  let ringLayer: WidgetRingLayer

  var body: some View {
    ZStack {
      Circle()
        .stroke(Color.white.opacity(0.16), lineWidth: lineWidth)

      Circle()
        .trim(from: 0, to: progress)
        .stroke(
          ringColor(for: metric, colors: ringColors, layer: ringLayer),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
    }
  }

  private var progress: CGFloat {
    if metric.isUnlimited {
      return 1
    }
    let value = CGFloat(metric.remainingPercent ?? 0)
    return max(0, min(1, value / 100))
  }
}

private struct MiniProgressBar: View {
  let percent: Int?
  let unlimited: Bool
  let ringColors: WidgetRingColors

  var body: some View {
    GeometryReader { proxy in
      let width = max(0, proxy.size.width)
      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.white.opacity(0.16))

        if unlimited {
          Capsule().fill(unlimitedColor(for: ringColors, layer: .outer))
        } else {
          Capsule()
            .fill(progressColor)
            .frame(width: width * CGFloat(percent ?? 0) / 100.0)
        }
      }
    }
  }

  private var progressColor: Color {
    ringColor(for: percent ?? 0, colors: ringColors, layer: .outer)
  }
}

private func chartMetrics(for usage: ProviderUsage) -> [UsageMetric] {
  let candidates = usage.metrics.filter { $0.remainingPercent != nil || $0.isUnlimited }
  if candidates.isEmpty {
    return usage.metrics
  }
  return Array(candidates.prefix(2))
}

private func metricSummary(for usage: ProviderUsage, showPercentages: Bool) -> String {
  let metrics = chartMetrics(for: usage)
  guard let first = metrics.first else {
    return "No quota metrics"
  }

  guard showPercentages else {
    if metrics.count >= 2 {
      return "\(metrics.count) limits tracked"
    }
    return first.label
  }

  if metrics.count >= 2, let second = metrics.dropFirst().first {
    return "S: \(percentText(for: first))  L: \(percentText(for: second))"
  }

  return "\(first.label): \(percentText(for: first))"
}

private func compactProviderName(for provider: QuotaProvider) -> String {
  switch provider {
  case .openAI:
    return "OpenAI"
  case .zhipu:
    return "Zhipu"
  case .zai:
    return "Z.ai"
  case .googleAntigravity:
    return "Google"
  case .gitHubCopilot:
    return "Copilot"
  }
}

private func resetSummary(for metrics: [UsageMetric]) -> String? {
  for metric in metrics {
    if let resetIn = metric.resetIn?.trimmingCharacters(in: .whitespacesAndNewlines), !resetIn.isEmpty {
      return resetIn
    }

    if let resetAt = metric.resetAt {
      return relativeResetSummary(until: resetAt)
    }
  }

  return nil
}

private func resetDisplayText(for value: String) -> String {
  if value.lowercased().hasPrefix("in ") {
    return "Reset \(value)"
  }
  return "Reset in \(value)"
}

private func relativeResetSummary(until date: Date) -> String {
  let seconds = max(0, Int(date.timeIntervalSinceNow))
  if seconds < 60 {
    return "<1m"
  }

  let totalHours = seconds / 3600
  let minutes = (seconds % 3600) / 60

  if totalHours >= 24 {
    let days = totalHours / 24
    let hours = totalHours % 24
    return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
  }

  if totalHours > 0 {
    return minutes > 0 ? "\(totalHours)h \(minutes)m" : "\(totalHours)h"
  }

  return "\(minutes)m"
}

private func percentText(for metric: UsageMetric?) -> String {
  guard let metric else { return "--" }
  if metric.isUnlimited {
    return "INF"
  }
  if let remaining = metric.remainingPercent {
    return "\(remaining)%"
  }
  return "--"
}

@ViewBuilder
private func widgetBackground(for entry: QuotaEntry, provider: QuotaProvider?) -> some View {
  let style = entry.style(for: provider)
  if let color = Color(hexColor: style.backgroundHexColor) {
    color
  } else {
    Color.clear
  }
}

private func ringColor(for metric: UsageMetric, colors: WidgetRingColors, layer: WidgetRingLayer) -> Color {
  if metric.isUnlimited {
    return unlimitedColor(for: colors, layer: layer)
  }

  return ringColor(for: metric.remainingPercent ?? 0, colors: colors, layer: layer)
}

private func ringColor(for remainingPercent: Int, colors: WidgetRingColors, layer: WidgetRingLayer) -> Color {
  let value = max(0, min(100, remainingPercent))

  if value >= 70 { return Color(hexColor: colors.hexColor(for: .high, layer: layer)) ?? .green }
  if value >= 40 { return Color(hexColor: colors.hexColor(for: .medium, layer: layer)) ?? .yellow }
  return Color(hexColor: colors.hexColor(for: .low, layer: layer)) ?? .red
}

private func unlimitedColor(for colors: WidgetRingColors, layer: WidgetRingLayer) -> Color {
  Color(hexColor: colors.hexColor(for: .unlimited, layer: layer)) ?? .blue
}

private extension QuotaEntry {
  func style(for provider: QuotaProvider?) -> WidgetStyleSettings {
    let globalStyle = settings.widgetStyle

    guard let provider else {
      return globalStyle
    }

    let override = settings.styleOverride(for: provider)

    guard override.useCustomStyle else {
      return globalStyle
    }

    let resolvedBackground = override.style.backgroundHexColor ?? globalStyle.backgroundHexColor

    return WidgetStyleSettings(
      backgroundHexColor: resolvedBackground,
      ringColors: override.style.ringColors
    )
  }
}

private extension Color {
  init?(hexColor: String?) {
    guard var raw = hexColor?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
      return nil
    }

    if raw.hasPrefix("#") {
      raw.removeFirst()
    }

    if raw.count == 3 || raw.count == 4 {
      raw = raw.map { "\($0)\($0)" }.joined()
    }

    guard (raw.count == 6 || raw.count == 8), let parsed = UInt64(raw, radix: 16) else {
      return nil
    }

    if raw.count == 6 {
      let red = Double((parsed >> 16) & 0xFF) / 255.0
      let green = Double((parsed >> 8) & 0xFF) / 255.0
      let blue = Double(parsed & 0xFF) / 255.0
      self = Color(red: red, green: green, blue: blue)
      return
    }

    let red = Double((parsed >> 24) & 0xFF) / 255.0
    let green = Double((parsed >> 16) & 0xFF) / 255.0
    let blue = Double((parsed >> 8) & 0xFF) / 255.0
    let alpha = Double(parsed & 0xFF) / 255.0
    self = Color(red: red, green: green, blue: blue, opacity: alpha)
  }
}
