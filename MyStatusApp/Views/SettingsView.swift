import SwiftUI
import QuotaCore

struct SettingsView: View {
  @ObservedObject var model: AppModel
  private let providers = Array(QuotaProvider.allCases)

  var body: some View {
    TabView {
      generalTab
        .tabItem {
          Label("General", systemImage: "gearshape")
        }

      ForEach(providers, id: \.rawValue) { (provider: QuotaProvider) in
        providerTab(for: provider)
          .tabItem {
            Label(provider.displayName, systemImage: iconName(for: provider))
          }
      }
    }
    .navigationTitle("OpenCodeQuota")
  }

  private var generalTab: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        refreshSection
        providerOverviewSection
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

  private var providerOverviewSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Provider Overview")
        .font(.headline)

      ForEach(providers, id: \.rawValue) { (provider: QuotaProvider) in
        let status = model.status(for: provider)
        let enabled = model.providerEnabled[provider] ?? true

        HStack(alignment: .top, spacing: 10) {
          Circle()
            .fill((status?.available ?? false) ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
            .padding(.top, 5)

          VStack(alignment: .leading, spacing: 2) {
            HStack {
              Text(provider.displayName)
                .font(.subheadline.weight(.medium))
              Spacer()
              Text(enabled ? "Enabled" : "Disabled")
                .font(.caption)
                .foregroundStyle(enabled ? Color.secondary : Color.orange)
            }

            Text(status?.detail ?? "No status available")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
    .padding(16)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

  private func iconName(for provider: QuotaProvider) -> String {
    switch provider {
    case .openAI:
      return "sparkles"
    case .zhipu:
      return "bubble.left.and.bubble.right"
    case .zai:
      return "bolt"
    case .googleAntigravity:
      return "cloud"
    case .gitHubCopilot:
      return "chevron.left.forwardslash.chevron.right"
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
