import SwiftUI
import QuotaCore

struct SettingsView: View {
  private enum SettingsTab: Hashable {
    case general
    case provider(QuotaProvider)
  }

  @ObservedObject var model: AppModel
  @State private var selectedTab: SettingsTab = .general

  private let providers = Array(QuotaProvider.allCases)
  private let refreshIntervalOptions = [15, 30, 45, 60, 90, 120, 180]
  private let settingsLabelWidth: CGFloat = 180

  private var availableRefreshIntervalOptions: [Int] {
    Array(Set(refreshIntervalOptions + [model.refreshIntervalMinutes])).sorted()
  }

  var body: some View {
    VStack(spacing: 0) {
      tabsHeader
      currentTabContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .navigationTitle("OpenCodeQuota")
  }

  private var tabsHeader: some View {
    ZStack(alignment: .bottom) {
      Rectangle()
        .fill(Color.secondary.opacity(0.24))
        .frame(height: 1)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 0) {
          tabButton(for: .general, title: "General")

          ForEach(providers, id: \.rawValue) { (provider: QuotaProvider) in
            tabButton(
              for: .provider(provider),
              title: tabTitle(for: provider),
              provider: provider
            )
          }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, -1)
      }
    }
    .background(.regularMaterial)
  }

  @ViewBuilder
  private var currentTabContent: some View {
    switch selectedTab {
    case .general:
      generalTab
    case .provider(let provider):
      providerTab(for: provider)
    }
  }

  private func tabButton(
    for tab: SettingsTab,
    title: String,
    provider: QuotaProvider? = nil
  ) -> some View {
    let isSelected = selectedTab == tab

    return Button {
      selectedTab = tab
    } label: {
      HStack(spacing: 6) {
        if let provider {
          Circle()
            .fill(tabDotColor(for: provider))
            .frame(width: 6, height: 6)
        }

        Text(title)
          .font(.system(size: 14, weight: .semibold))
      }
      .frame(width: 110, alignment: .center)
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .frame(minHeight: 36)
      .contentShape(Rectangle())
      .background {
        if isSelected {
          TopTabFillShape(cornerRadius: 9)
            .fill(.background)
        }
      }
      .overlay {
        if isSelected {
          TopTabBorderShape(cornerRadius: 9)
            .stroke(Color.secondary.opacity(0.38), lineWidth: 1)
        }
      }
      .overlay(alignment: .bottom) {
        if isSelected {
          Rectangle()
            .fill(.background)
            .frame(height: 2)
            .offset(y: 1)
        }
      }
      .padding(.trailing, 4)
    }
    .buttonStyle(.plain)
    .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.92))
  }

  private var generalTab: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        authAccessSection
        generalSettingsSection
        actionsSection
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(24)
    }
  }

  private var authAccessSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Access to OpenCode auth")
        .font(.title3.weight(.semibold))

      Text("OpenCodeQuota reads credentials from `~/.local/share/opencode/auth.json` and related OpenCode files. Grant access once if the sandbox blocks file reads.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)

      authAccessBanner

      Button("Grant File Access") {
        model.grantOpenCodeFileAccess()
      }
      .buttonStyle(.borderedProminent)
    }
  }

  private var authAccessBanner: some View {
    let tint: Color = model.authAccessGranted ? .green : .red
    let title = model.authAccessGranted ? "Access granted" : "Access required"

    return VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(tint)

      Text(model.authAccessSummary)
        .font(.subheadline)

      if !model.authAccessDetail.isEmpty {
        Text(model.authAccessDetail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(tint.opacity(0.45), lineWidth: 1)
    )
  }

  private var generalSettingsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Settings")
        .font(.title3.weight(.semibold))

      VStack(spacing: 0) {
        settingsRow(title: "Refresh interval") {
          Picker("", selection: model.refreshIntervalBinding()) {
            ForEach(availableRefreshIntervalOptions, id: \.self) { minutes in
              Text("\(minutes) min").tag(minutes)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
        }

        Divider()

        settingsRow(title: "Visible information") {
          VStack(alignment: .leading, spacing: 8) {
            Toggle(
              "Show percentages in widgets",
              isOn: model.widgetVisibilityBinding(for: \.showPercentageValues)
            )
            Toggle(
              "Progress bars in medium widget",
              isOn: model.widgetVisibilityBinding(for: \.showMediumProgressBars)
            )
            Toggle(
              "Timestamp in medium widget",
              isOn: model.widgetVisibilityBinding(for: \.showTimestamp)
            )
            Toggle(
              "Failure count in medium widget",
              isOn: model.widgetVisibilityBinding(for: \.showFailureCount)
            )
            Toggle(
              "Reset countdown in provider widgets",
              isOn: model.widgetVisibilityBinding(for: \.showResetInfo)
            )
            Toggle(
              "Metric summary in overview widget",
              isOn: model.widgetVisibilityBinding(for: \.showOverviewMetricSummary)
            )

            HStack(spacing: 10) {
              Text("Providers in medium widget")
              Spacer()
              Stepper(
                "",
                value: model.widgetVisibilityIntBinding(for: \.mediumProviderLimit, range: 1...12),
                in: 1...12
              )
              .labelsHidden()

              Text("\(model.widgetVisibility.mediumProviderLimit)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 24, alignment: .trailing)
            }
          }
          .toggleStyle(.switch)
        }

        Divider()

        settingsRow(title: "Style preset") {
          Picker("", selection: model.widgetStylePresetBinding()) {
            Text("Custom").tag(model.customStylePresetID)
            ForEach(model.stylePresets) { preset in
              Text(preset.displayName).tag(preset.id)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(minWidth: 180, maxWidth: 260, alignment: .leading)
        }

        Divider()

        settingsRow(title: "Transparent background") {
          Toggle("", isOn: model.widgetTransparentBackgroundBinding())
            .labelsHidden()
            .toggleStyle(.switch)
        }

        Divider()

        settingsRow(title: "Background color") {
          ColorPicker("", selection: model.widgetBackgroundColorBinding(), supportsOpacity: true)
            .labelsHidden()
            .frame(width: 48)
            .disabled(model.widgetStyle.useTransparentBackground)
        }

        Divider()

        settingsRow(title: "Circle graph colors") {
          HStack(alignment: .top, spacing: 24) {
            ringColorLayerColumn(
              layer: .outer,
              high: model.widgetRingColorBinding(for: .high, layer: .outer),
              medium: model.widgetRingColorBinding(for: .medium, layer: .outer),
              low: model.widgetRingColorBinding(for: .low, layer: .outer),
              unlimited: model.widgetRingColorBinding(for: .unlimited, layer: .outer)
            )

            ringColorLayerColumn(
              layer: .inner,
              high: model.widgetRingColorBinding(for: .high, layer: .inner),
              medium: model.widgetRingColorBinding(for: .medium, layer: .inner),
              low: model.widgetRingColorBinding(for: .low, layer: .inner),
              unlimited: model.widgetRingColorBinding(for: .unlimited, layer: .inner)
            )
          }
        }
      }
    }
  }

  private var actionsSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Actions")
        .font(.title3.weight(.semibold))

      HStack(spacing: 10) {
        Button("Reload OpenCode Sources") {
          model.reloadCredentialStatuses()
        }
        .buttonStyle(.bordered)

        Button {
          Task { await model.refreshNow() }
        } label: {
          if model.isRefreshing {
            ProgressView()
              .controlSize(.small)
          } else {
            Text("Refresh Now")
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isRefreshing)
      }

      latestSnapshotCard

      if !model.statusMessage.isEmpty {
        Text(model.statusMessage)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var latestSnapshotCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Latest Snapshot")
          .font(.headline)
        Spacer()

        if let snapshot = model.snapshot {
          Text(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      if let snapshot = model.snapshot {
        HStack(spacing: 8) {
          summaryPill(title: "Providers", value: "\(snapshot.providers.count)", tint: .blue)
          summaryPill(
            title: "Failures",
            value: "\(snapshot.failures.count)",
            tint: snapshot.failures.isEmpty ? .green : .orange
          )
        }

        if snapshot.providers.isEmpty {
          Text("No provider data in latest snapshot.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(snapshot.providers.prefix(5))) { usage in
              HStack {
                Text(shortName(for: usage.provider))
                  .font(.caption.weight(.semibold))
                  .frame(width: 64, alignment: .leading)

                if let metric = usage.metrics.first {
                  Text(metric.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                  Spacer()

                  Text(percentText(metric))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                } else {
                  Spacer()
                  Text("No metrics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }

        if !snapshot.failures.isEmpty {
          Divider()
          VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(snapshot.failures.prefix(3))) { failure in
              Text("\(failure.provider.displayName): \(failure.message)")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
            }
          }
        }
      } else {
        Text("No snapshot available yet. Use Refresh Now to fetch usage.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func providerTab(for provider: QuotaProvider) -> some View {
    let providerStyle = model.providerStyle(for: provider)
    let credentialsAvailable = model.isProviderAvailable(provider)
    let dataLoaded = providerUsage(for: provider) != nil

    return ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        providerStatusRow(
          title: "Credentials",
          message: credentialsAvailable ? "Credentials available" : "Credentials unavailable",
          isPositive: credentialsAvailable
        )

        Divider()

        providerStatusRow(
          title: "Data",
          message: dataLoaded ? "Data loaded" : "No data loaded",
          isPositive: dataLoaded
        )

        Divider()

        settingsRow(title: "Override global styling") {
          Toggle("", isOn: model.providerOverrideEnabledBinding(for: provider))
            .labelsHidden()
            .toggleStyle(.switch)
        }

        if providerStyle.useCustomStyle {
          Divider()

          settingsRow(title: "Style preset") {
            Picker("", selection: model.providerStylePresetBinding(for: provider)) {
              Text("Custom").tag(model.customStylePresetID)
              ForEach(model.stylePresets) { preset in
                Text(preset.displayName).tag(preset.id)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 180, maxWidth: 260, alignment: .leading)
          }

          Divider()

          settingsRow(title: "Transparent background") {
            Toggle("", isOn: model.providerTransparentBackgroundBinding(for: provider))
              .labelsHidden()
              .toggleStyle(.switch)
          }

          Divider()

          settingsRow(title: "Background color") {
            ColorPicker("", selection: model.providerBackgroundColorBinding(for: provider), supportsOpacity: true)
              .labelsHidden()
              .frame(width: 48)
              .disabled(providerStyle.style.useTransparentBackground)
          }

          Divider()

          settingsRow(title: "Circle graph colors") {
            HStack(alignment: .top, spacing: 24) {
              ringColorLayerColumn(
                layer: .outer,
                high: model.providerRingColorBinding(for: provider, role: .high, layer: .outer),
                medium: model.providerRingColorBinding(for: provider, role: .medium, layer: .outer),
                low: model.providerRingColorBinding(for: provider, role: .low, layer: .outer),
                unlimited: model.providerRingColorBinding(for: provider, role: .unlimited, layer: .outer)
              )

              ringColorLayerColumn(
                layer: .inner,
                high: model.providerRingColorBinding(for: provider, role: .high, layer: .inner),
                medium: model.providerRingColorBinding(for: provider, role: .medium, layer: .inner),
                low: model.providerRingColorBinding(for: provider, role: .low, layer: .inner),
                unlimited: model.providerRingColorBinding(for: provider, role: .unlimited, layer: .inner)
              )
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(24)
    }
  }

  private func providerStatusRow(
    title: String,
    message: String,
    isPositive: Bool
  ) -> some View {
    HStack(spacing: 16) {
      Text(title)
        .frame(width: settingsLabelWidth, alignment: .leading)

      HStack(spacing: 8) {
        Circle()
          .fill(isPositive ? Color.green : Color.red)
          .frame(width: 8, height: 8)
        Text(message)
          .font(.subheadline)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 8)
  }

  private func settingsRow<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Text(title)
        .frame(width: settingsLabelWidth, alignment: .leading)
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 8)
  }

  private func ringColorPickerRow(title: String, binding: Binding<Color>) -> some View {
    HStack(spacing: 10) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: 130, alignment: .leading)

      ColorPicker("", selection: binding, supportsOpacity: false)
        .labelsHidden()
        .frame(width: 48)
    }
  }

  private func ringColorLayerColumn(
    layer: WidgetRingLayer,
    high: Binding<Color>,
    medium: Binding<Color>,
    low: Binding<Color>,
    unlimited: Binding<Color>
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(layer.displayName)
        .font(.caption.weight(.semibold))

      ringColorPickerRow(title: WidgetRingColorRole.high.displayName, binding: high)
      ringColorPickerRow(title: WidgetRingColorRole.medium.displayName, binding: medium)
      ringColorPickerRow(title: WidgetRingColorRole.low.displayName, binding: low)
      ringColorPickerRow(title: WidgetRingColorRole.unlimited.displayName, binding: unlimited)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func summaryPill(title: String, value: String, tint: Color) -> some View {
    HStack(spacing: 6) {
      Text(title)
      Text(value)
        .fontWeight(.semibold)
    }
    .font(.caption)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .background(tint.opacity(0.16), in: Capsule())
    .foregroundStyle(tint)
  }

  private func tabDotColor(for provider: QuotaProvider) -> Color {
    model.isProviderAvailable(provider) ? .green : .red
  }

  private func tabTitle(for provider: QuotaProvider) -> String {
    shortName(for: provider)
  }

  private func shortName(for provider: QuotaProvider) -> String {
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

  private func providerUsage(for provider: QuotaProvider) -> ProviderUsage? {
    model.snapshot?.providers.first(where: { $0.provider == provider })
  }

  private func percentText(_ metric: UsageMetric?) -> String {
    guard let metric else {
      return "--"
    }

    if metric.isUnlimited {
      return "INF"
    }

    guard let remaining = metric.remainingPercent else {
      return "--"
    }

    return "\(remaining)%"
  }
}

private struct TopTabFillShape: Shape {
  var cornerRadius: CGFloat

  func path(in rect: CGRect) -> Path {
    let radius = max(0, min(cornerRadius, rect.width / 2, rect.height))

    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + radius, y: rect.minY),
      control: CGPoint(x: rect.minX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + radius),
      control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

private struct TopTabBorderShape: Shape {
  var cornerRadius: CGFloat

  func path(in rect: CGRect) -> Path {
    let radius = max(0, min(cornerRadius, rect.width / 2, rect.height))

    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + radius, y: rect.minY),
      control: CGPoint(x: rect.minX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + radius),
      control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    return path
  }
}
