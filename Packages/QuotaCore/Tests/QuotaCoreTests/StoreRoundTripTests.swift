import XCTest
@testable import QuotaCore

final class StoreRoundTripTests: XCTestCase {
  func testSnapshotStoreRoundTrip() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let fileURL = tempDir.appendingPathComponent("snapshot.json")
    let store = SnapshotStore(fileURL: fileURL)

    let snapshot = QuotaSnapshot(
      generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
      providers: [
        ProviderUsage(
          provider: .openAI,
          title: "OpenAI",
          subtitle: "plus",
          metrics: [UsageMetric(id: "primary", label: "3-hour limit", remainingPercent: 70)],
          maxUsagePercent: 30,
          fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
      ],
      failures: []
    )

    try store.save(snapshot)
    let loaded = try store.load()

    XCTAssertEqual(loaded?.providers.first?.provider, .openAI)
    XCTAssertEqual(loaded?.providers.first?.metrics.first?.remainingPercent, 70)
  }

  func testSettingsStoreDefaultsWhenMissing() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let fileURL = tempDir.appendingPathComponent("settings.json")
    let store = SettingsStore(fileURL: fileURL)

    let settings = try store.load()
    XCTAssertEqual(settings.refreshIntervalMinutes, 30)
    XCTAssertEqual(settings.providers.count, QuotaProvider.allCases.count)
    XCTAssertFalse(settings.widgetStyle.useTransparentBackground)
    XCTAssertTrue(settings.widgetVisibility.showTimestamp)
    XCTAssertTrue(settings.widgetVisibility.showFailureCount)
    XCTAssertTrue(settings.widgetVisibility.showResetInfo)
    XCTAssertTrue(settings.widgetVisibility.showOverviewMetricSummary)
    XCTAssertTrue(settings.widgetVisibility.showPercentageValues)
    XCTAssertTrue(settings.widgetVisibility.showMediumProgressBars)
    XCTAssertEqual(settings.widgetVisibility.mediumProviderLimit, 6)
  }

  func testSettingsStoreRoundTripPersistsWidgetVisibility() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let fileURL = tempDir.appendingPathComponent("settings.json")
    let store = SettingsStore(fileURL: fileURL)

    let settings = AppSettings(
      refreshIntervalMinutes: 45,
      providers: QuotaProvider.allCases.map { ProviderSettings(provider: $0, isEnabled: true) },
      widgetStyle: WidgetStyleSettings(useTransparentBackground: true),
      providerStyleSettings: QuotaProvider.allCases.map { ProviderStyleSettings.defaultValue(for: $0) },
      widgetVisibility: WidgetVisibilitySettings(
        showTimestamp: false,
        showFailureCount: true,
        showResetInfo: false,
        showOverviewMetricSummary: true,
        showPercentageValues: false,
        showMediumProgressBars: false,
        mediumProviderLimit: 4
      )
    )

    try store.save(settings)
    let loaded = try store.load()

    XCTAssertTrue(loaded.widgetStyle.useTransparentBackground)
    XCTAssertFalse(loaded.widgetVisibility.showTimestamp)
    XCTAssertTrue(loaded.widgetVisibility.showFailureCount)
    XCTAssertFalse(loaded.widgetVisibility.showResetInfo)
    XCTAssertTrue(loaded.widgetVisibility.showOverviewMetricSummary)
    XCTAssertFalse(loaded.widgetVisibility.showPercentageValues)
    XCTAssertFalse(loaded.widgetVisibility.showMediumProgressBars)
    XCTAssertEqual(loaded.widgetVisibility.mediumProviderLimit, 4)
  }
}
