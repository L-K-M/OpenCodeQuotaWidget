import SwiftUI
import QuotaCore

struct SettingsView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        refreshSection
        providerSection
        actionSection
        snapshotSection
      }
      .padding(24)
    }
    .navigationTitle("OpenCodeQuota")
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

  private var providerSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Providers")
        .font(.headline)

      ForEach(QuotaProvider.allCases, id: \.self) { provider in
        let status = model.status(for: provider)

        VStack(alignment: .leading, spacing: 8) {
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
        .padding(14)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
    }
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
}
