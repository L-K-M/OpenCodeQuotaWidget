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
  private let settingsContentMaxWidth: CGFloat = 760

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
      .padding(.vertical, 7)
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
      .frame(maxWidth: settingsContentMaxWidth, alignment: .leading)
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

        settingsRow(title: "Background color") {
          Picker("", selection: model.widgetBackgroundStyleBinding()) {
            ForEach(WidgetBackgroundStyle.allCases, id: \.self) { style in
              Text(style.displayName).tag(style)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
        }

        Divider()

        settingsRow(title: "Circle graph colors") {
          Picker("", selection: model.widgetRingPaletteBinding()) {
            ForEach(WidgetRingPalette.allCases, id: \.self) { palette in
              Text(palette.displayName).tag(palette)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
        }
      }

      Text("These settings apply to all widgets unless a provider tab enables style overrides.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text("Choose Default to use only the system widget container. macOS always keeps the rounded widget shape.")
        .font(.caption)
        .foregroundStyle(.secondary)
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

          settingsRow(title: "Background color") {
            Picker("", selection: model.providerBackgroundStyleBinding(for: provider)) {
              ForEach(WidgetBackgroundStyle.allCases, id: \.self) { backgroundStyle in
                Text(backgroundStyle.displayName).tag(backgroundStyle)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
          }

          Divider()

          settingsRow(title: "Circle graph colors") {
            Picker("", selection: model.providerRingPaletteBinding(for: provider)) {
              ForEach(WidgetRingPalette.allCases, id: \.self) { palette in
                Text(palette.displayName).tag(palette)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
          }
        }
      }
      .frame(maxWidth: settingsContentMaxWidth, alignment: .leading)
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
    HStack(alignment: .center, spacing: 16) {
      Text(title)
        .frame(width: settingsLabelWidth, alignment: .leading)
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 8)
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
