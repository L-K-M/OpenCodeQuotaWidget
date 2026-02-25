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
  }
}
