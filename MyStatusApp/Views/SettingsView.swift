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

  var body: some View {
    VStack(spacing: 0) {
      tabsHeader
      currentTabContent
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
      VStack(alignment: .leading, spacing: 20) {
        header
        refreshSection
        actionSection
        snapshotSection
      }
      .padding(24)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("OpenCode Credential Source")
        .font(.title2.weight(.semibold))

      Text("Credentials are loaded from your local OpenCode config files. No manual credential entry is required.")
        .foregroundStyle(.secondary)

      Text("Expected files: ~/.local/share/opencode/auth.json, ~/.config/opencode/antigravity-accounts.json, ~/.config/opencode/copilot-quota-token.json")
        .font(.caption)
        .foregroundStyle(.secondary)

      Text("If sandbox permissions block reads, use 'Grant File Access' once to create security-scoped bookmarks.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var refreshSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Refresh Settings")
        .font(.headline)

      Stepper(value: $model.refreshIntervalMinutes, in: 15...180, step: 5) {
        Text("Refresh interval: \(model.refreshIntervalMinutes) minutes")
      }
    }
    .padding(16)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var actionSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Button("Reload OpenCode Sources") {
          model.reloadCredentialStatuses()
        }
        .buttonStyle(.bordered)

        Button("Grant File Access") {
          model.grantOpenCodeFileAccess()
        }
        .buttonStyle(.bordered)

        Button("Save Preferences") {
          Task { await model.saveConfiguration() }
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
        .disabled(model.isRefreshing)
        .buttonStyle(.borderedProminent)
      }

      if !model.statusMessage.isEmpty {
        Text(model.statusMessage)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }

  private var snapshotSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Latest Snapshot")
        .font(.headline)

      if let snapshot = model.snapshot {
        Text("Updated: \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Text("Providers: \(snapshot.providers.count) | Failures: \(snapshot.failures.count)")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        ForEach(snapshot.providers) { usage in
          VStack(alignment: .leading, spacing: 2) {
            Text(usage.title)
              .font(.subheadline.weight(.medium))

            if let metric = usage.metrics.first {
              let remaining = metric.remainingPercent.map { "\($0)%" } ?? (metric.isUnlimited ? "INF" : "-")
              Text("\(metric.label): \(remaining)")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }

        if !snapshot.failures.isEmpty {
          Divider()
          ForEach(snapshot.failures) { failure in
            Text("\(failure.provider.displayName): \(failure.message)")
              .font(.caption)
              .foregroundStyle(.orange)
          }
        }
      } else {
        Text("No snapshot available yet.")
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private func tabDotColor(for provider: QuotaProvider) -> Color {
    (model.status(for: provider)?.available ?? false) ? .green : .red
  }

  private func tabTitle(for provider: QuotaProvider) -> String {
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

  private func providerFailure(for provider: QuotaProvider) -> ProviderFailure? {
    model.snapshot?.failures.first(where: { $0.provider == provider })
  }

  private func providerTab(for provider: QuotaProvider) -> some View {
    let status = model.status(for: provider)

    return ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 12) {
          Text("\(provider.displayName) Settings")
            .font(.title2.weight(.semibold))

          Toggle("Enable \(provider.displayName)", isOn: model.enabledBinding(for: provider))
            .toggleStyle(.switch)

          HStack(spacing: 6) {
            Circle()
              .fill((status?.available ?? false) ? Color.green : Color.orange)
              .frame(width: 8, height: 8)
            Text(status?.detail ?? "No status available")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Text(status?.source ?? "Unknown source")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        providerSnapshotSection(for: provider)

        VStack(alignment: .leading, spacing: 8) {
          Text("More settings soon")
            .font(.headline)
          Text("This tab is ready for provider-specific controls as we add deeper configuration options.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      .padding(24)
    }
  }

  private func providerSnapshotSection(for provider: QuotaProvider) -> some View {
    let usage = providerUsage(for: provider)
    let failure = providerFailure(for: provider)

    return VStack(alignment: .leading, spacing: 10) {
      Text("Latest \(provider.displayName) Snapshot")
        .font(.headline)

      if let usage {
        Text("Fetched: \(usage.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        if let subtitle = usage.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }

        if usage.metrics.isEmpty {
          Text("No usage metrics were returned.")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          ForEach(usage.metrics) { metric in
            VStack(alignment: .leading, spacing: 4) {
              Text(metric.label)
                .font(.subheadline.weight(.medium))

              if let usageLine = metric.usageLine {
                Text(usageLine)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              let remaining = metric.remainingPercent.map { "\($0)% remaining" } ?? (metric.isUnlimited ? "Unlimited" : "Remaining: -")
              Text(remaining)
                .font(.caption)
                .foregroundStyle(.secondary)

              if let resetIn = metric.resetIn {
                Text("Resets in: \(resetIn)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              if let detail = metric.detail, !detail.isEmpty {
                Text(detail)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
              }
            }
            .padding(10)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
          }
        }

        if let warning = usage.warning, !warning.isEmpty {
          Text(warning)
            .font(.caption)
            .foregroundStyle(.orange)
        }
      } else if let failure {
        Text("Last refresh reported an issue: \(failure.message)")
          .font(.subheadline)
          .foregroundStyle(.orange)
      } else {
        Text("No snapshot available for this provider yet.")
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
