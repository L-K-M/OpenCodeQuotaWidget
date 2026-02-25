import Foundation
import WidgetKit
import QuotaCore

struct QuotaEntry: TimelineEntry {
  let date: Date
  let snapshot: QuotaSnapshot?
  let refreshIntervalMinutes: Int
  let settings: AppSettings
}

struct QuotaTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> QuotaEntry {
    QuotaEntry(
      date: Date(),
      snapshot: SampleSnapshotFactory.make(now: Date()),
      refreshIntervalMinutes: 30,
      settings: .default
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
    if context.isPreview {
      completion(
        QuotaEntry(
          date: Date(),
          snapshot: SampleSnapshotFactory.make(now: Date()),
          refreshIntervalMinutes: 30,
          settings: .default
        )
      )
      return
    }

    completion(makeCurrentEntry(now: Date()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
    let now = Date()
    let entry = makeCurrentEntry(now: now)
    let refreshMinutes = max(15, entry.refreshIntervalMinutes)
    let nextDate = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: now) ?? now.addingTimeInterval(1800)

    completion(Timeline(entries: [entry], policy: .after(nextDate)))
  }

  private func makeCurrentEntry(now: Date) -> QuotaEntry {
    let settings = loadSettings()
    let snapshot = loadSnapshot()
    let refreshInterval = max(15, settings.refreshIntervalMinutes)
    return QuotaEntry(
      date: now,
      snapshot: snapshot,
      refreshIntervalMinutes: refreshInterval,
      settings: settings
    )
  }

  private func loadSnapshot() -> QuotaSnapshot? {
    do {
      let store = SnapshotStore(fileURL: try SharedPaths.snapshotFileURL())
      return try store.load()
    } catch {
      return nil
    }
  }

  private func loadSettings() -> AppSettings {
    do {
      let store = SettingsStore(fileURL: try SharedPaths.settingsFileURL())
      return try store.load()
    } catch {
      return .default
    }
  }
}

private enum SampleSnapshotFactory {
  static func make(now: Date) -> QuotaSnapshot {
    QuotaSnapshot(
      generatedAt: now,
      providers: [
        ProviderUsage(
          provider: .openAI,
          title: "OpenAI",
          subtitle: "plus",
          metrics: [
            UsageMetric(
              id: "primary",
              label: "3-hour limit",
              remainingPercent: 72,
              usedDisplay: "28",
              totalDisplay: "100",
              resetIn: "1h 42m"
            ),
            UsageMetric(
              id: "secondary",
              label: "7-day limit",
              remainingPercent: 61,
              usedDisplay: "39",
              totalDisplay: "100",
              resetIn: "2d 3h"
            )
          ],
          maxUsagePercent: 39,
          fetchedAt: now
        ),
        ProviderUsage(
          provider: .zhipu,
          title: "Zhipu AI",
          subtitle: "Coding Plan",
          metrics: [
            UsageMetric(
              id: "tokens",
              label: "5-hour token limit",
              remainingPercent: 55,
              usedDisplay: "4.5M",
              totalDisplay: "10.0M",
              resetIn: "2h 10m"
            ),
            UsageMetric(
              id: "mcp",
              label: "MCP monthly quota",
              remainingPercent: 81,
              usedDisplay: "19",
              totalDisplay: "100"
            )
          ],
          maxUsagePercent: 45,
          fetchedAt: now
        ),
        ProviderUsage(
          provider: .googleAntigravity,
          title: "Google Cloud",
          subtitle: "workspace@example.com",
          metrics: [
            UsageMetric(
              id: "g3-pro",
              label: "G3 Pro",
              remainingPercent: 63,
              resetIn: "10h"
            )
          ],
          maxUsagePercent: 37,
          fetchedAt: now
        ),
        ProviderUsage(
          provider: .gitHubCopilot,
          title: "GitHub Copilot",
          subtitle: "pro",
          metrics: [
            UsageMetric(
              id: "premium",
              label: "Premium requests",
              remainingPercent: 58,
              usedDisplay: "126",
              totalDisplay: "300",
              resetIn: "4d 6h"
            )
          ],
          maxUsagePercent: 42,
          fetchedAt: now
        )
      ],
      failures: []
    )
  }
}
